package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.OkHttpClientFactory
import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.PersonaProfilePatch
import com.fqyw.screen_memo.memory.model.UserEvent
import com.fqyw.screen_memo.memory.service.ExtractionContext
import com.fqyw.screen_memo.memory.service.MemoryPromptProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit

class LlmUserSignalExtractor(
    private val okHttpClient: OkHttpClient = OkHttpClientFactory.newBuilder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .writeTimeout(0, TimeUnit.SECONDS)
        .build()
) : UserSignalExtractor {

    override suspend fun extractSignals(
        event: UserEvent,
        context: ExtractionContext?,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult {
        if (context == null || !context.isValid) {
            return UserSignalExtractionResult(
                personaProfilePatch = null,
                personaSummaryFallback = null
            )
        }
        if (!supportsContext(context)) {
            return UserSignalExtractionResult(
                personaProfilePatch = null,
                personaSummaryFallback = null
            )
        }
        return try {
            if (isGoogleContext(context)) {
                callGeminiEndpoint(event, context, currentPersonaSummary, currentPersonaProfile)
            } else {
                callOpenAiStyleEndpoint(event, context, currentPersonaSummary, currentPersonaProfile)
            }
        } catch (t: Throwable) {
            FileLogger.w(TAG, "LLM 提取失败：${t.message}")
            throw t
        }
    }

    private fun supportsContext(context: ExtractionContext): Boolean {
        val type = context.providerType?.lowercase()
        if (type == "openai" || type == "custom" || type == "azure_openai" || type == "gemini") {
            return true
        }
        return isGoogleContext(context)
    }

    private fun isGoogleContext(context: ExtractionContext): Boolean {
        val type = context.providerType?.lowercase()
        if (type == "gemini") return true
        val base = context.baseUrl?.trim()?.lowercase().orEmpty()
        if (base.contains("googleapis.com") || base.contains("generativelanguage")) {
            return true
        }
        return false
    }

    private suspend fun callOpenAiStyleEndpoint(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult {
        if (!shouldAttemptStreaming(context)) {
            return callOpenAiStyleEndpointBlocking(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        }
        return try {
            callOpenAiStyleEndpointStreaming(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        } catch (e: StreamingNotSupportedException) {
            FileLogger.i(TAG, "OpenAI 流式不可用，回退非流式：${e.message}")
            callOpenAiStyleEndpointBlocking(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        }
    }

    private suspend fun callOpenAiStyleEndpointBlocking(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildOpenAiUrl(event, context)
        val headers = buildOpenAiHeaders(context)
        val payload = buildOpenAiRequestBody(
            event,
            context,
            currentPersonaSummary,
            currentPersonaProfile,
            url = url,
            stream = false
        )

        val request = Request.Builder()
            .url(url)
            .apply { headers.forEach { (k, v) -> addHeader(k, v) } }
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        FileLogger.i(TAG, "LLM(OpenAI风格) 请求：url=$url model=${context.model}")
        FileLogger.d(TAG, "LLM(OpenAI风格) 请求体=$payload")

        okHttpClient.newCall(request).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            FileLogger.d(TAG, "LLM(OpenAI风格) 响应：code=${resp.code} body=$body")
            if (!resp.isSuccessful) {
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "LLM 请求失败：code=${resp.code} body=${snippet}")
                throw LlmHttpException(resp.code, snippet, event.externalId)
            }
            val text = extractContent(body, context)
            parseCandidates(text)
        }
    }

    private suspend fun callOpenAiStyleEndpointStreaming(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildOpenAiUrl(event, context)
        val headers = buildOpenAiHeaders(context).toMutableMap()
        headers["Accept"] = "text/event-stream"
        val payload = buildOpenAiRequestBody(
            event,
            context,
            currentPersonaSummary,
            currentPersonaProfile,
            url = url,
            stream = true
        )

        val request = Request.Builder()
            .url(url)
            .apply { headers.forEach { (k, v) -> addHeader(k, v) } }
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        FileLogger.i(TAG, "LLM(OpenAI流式) 请求：url=$url model=${context.model}")
        FileLogger.d(TAG, "LLM(OpenAI流式) 请求体=$payload")

        okHttpClient.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) {
                val body = resp.body?.string().orEmpty()
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "流式请求失败：code=${resp.code} body=$snippet")
                throw StreamingNotSupportedException("HTTP ${resp.code}")
            }
            val responseBody = resp.body ?: throw StreamingNotSupportedException("Empty response body")
            val reader = responseBody.charStream().buffered()
            val aggregated = StringBuilder()
            val rawEvents = StringBuilder()
            var sawData = false
            reader.use { buffered ->
                while (true) {
                    val line = buffered.readLine() ?: break
                    if (line.isEmpty()) continue
                    if (!line.startsWith("data:")) continue
                    val data = line.substring(5).trim()
                    if (data.isEmpty()) continue
                    if (data == "[DONE]") {
                        break
                    }
                    sawData = true
                    rawEvents.append(data).append('\n')
                    try {
                        val json = JSONObject(data)
                        val type = json.optString("type")
                        if (type.isNotBlank()) {
                            when (type) {
                                "response.output_text.delta" -> {
                                    appendResponseDelta(json, aggregated)
                                }
                                "response.output_text.done",
                                "response.completed",
                                "response.created",
                                "response.output_text.delta.stop" -> {
                                    // no-op
                                }
                                "response.error" -> {
                                    val message = json.optJSONObject("error")?.optString("message")
                                        ?: json.optString("error")
                                    throw LlmHttpException(
                                        resp.code,
                                        message.take(MAX_ERROR_BODY_CHARS),
                                        event.externalId
                                    )
                                }
                                else -> {
                                    // ignore other event types (reasoning etc.)
                                }
                            }
                            continue
                        }
                        appendChoicesDelta(json, aggregated)
                    } catch (ex: Exception) {
                        // 回退到直接拼接原始文本，确保不会因解析失败丢内容
                        aggregated.append(data)
                    }
                }
            }
            if (!sawData) {
                FileLogger.w(TAG, "流式返回无数据；raw=${rawEvents.take(MAX_ERROR_BODY_CHARS)}")
                throw StreamingNotSupportedException("No data received")
            }
            val finalText = aggregated.toString().ifBlank {
                rawEvents.toString()
            }
            FileLogger.d(TAG, "LLM(OpenAI流式) 聚合长度=${finalText.length}")
            parseCandidates(finalText)
        }
    }

    private fun buildOpenAiUrl(event: UserEvent, context: ExtractionContext): HttpUrl {
        val base = resolveBaseUrl(context.baseUrl, DEFAULT_OPENAI_BASE, event)
        val path = when {
            context.useResponseApi -> OPENAI_RESPONSES_PATH
            !context.chatPath.isNullOrBlank() -> context.chatPath!!
            else -> DEFAULT_OPENAI_CHAT_PATH
        }
        return resolveEndpointUrl(base, path, event)
    }

    private fun buildOpenAiHeaders(context: ExtractionContext): Map<String, String> {
        val headers = linkedMapOf(
            "Content-Type" to "application/json"
        )
        when (context.providerType?.lowercase()) {
            "azure_openai" -> {
                val apiVersion = context.extra["api_version"]?.toString() ?: context.extra["apiVersion"]?.toString()
                if (!apiVersion.isNullOrBlank()) {
                    headers["api-version"] = apiVersion
                }
                headers["api-key"] = context.apiKey.orEmpty()
            }
            else -> headers["Authorization"] = "Bearer ${context.apiKey.orEmpty()}"
        }
        return headers
    }

    private fun buildOpenAiRequestBody(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile,
        url: HttpUrl,
        stream: Boolean = false
    ): String {
        val metadataJson = buildPromptMetadataJson(event)
        val model = context.model?.trim().orEmpty()
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            personaSummary = currentPersonaSummary,
            personaProfile = currentPersonaProfile
        )
        val systemPrompt = MemoryPromptProvider.systemPrompt()
        val body = if (context.useResponseApi) {
            JSONObject()
                .put("model", model)
                .put("input", JSONArray().put(JSONObject().put("role", "user").put("content", userPrompt)))
                .put("temperature", 0.1)
                .apply {
                    if (stream) {
                        put("stream", true)
                    }
                }
                .toString()
        } else {
            val messages = JSONArray()
                .put(JSONObject().put("role", "system").put("content", systemPrompt))
                .put(JSONObject().put("role", "user").put("content", userPrompt))
            JSONObject()
                .put("model", model)
                .put("messages", messages)
                .put("temperature", 0.1)
                .put("response_format", JSONObject().put("type", "json_object"))
                .apply {
                    if (stream) {
                        put("stream", true)
                    }
                }
                .toString()
        }

        recordLastRequestDebug(
            event = event,
            context = context,
            url = url,
            stream = stream,
            systemPrompt = systemPrompt,
            userPrompt = userPrompt,
            requestBody = body,
            metadataJson = metadataJson,
            currentPersonaSummary = currentPersonaSummary,
            currentPersonaProfile = currentPersonaProfile
        )
        return body
    }

    private fun buildPromptMetadataJson(event: UserEvent): JSONObject {
        if (event.metadata.isEmpty()) return JSONObject()

        val type = event.type.trim().lowercase()
        val allowKeys: Set<String> = when (type) {
            "segment" -> setOf(
                "segment_id",
                "segment_start",
                "segment_end",
                "segment_status"
            )
            "daily_aggregate" -> setOf(
                "event_date",
                "aggregation_scope",
                "day_start",
                "day_end_exclusive",
                "events_count"
            )
            "chat_message" -> setOf(
                "conversation_cid",
                "role",
                "message_id",
                "created_at_ms"
            )
            else -> emptySet()
        }

        val sanitized = LinkedHashMap<String, Any?>()
        val dropKeys = setOf(
            // Large and not useful for persona / temporal graph extraction.
            "segment_samples",
            "aggregated_events",
            "ai_output_text",
            "ai_structured_json",
            "reasoning"
        )

        if (allowKeys.isNotEmpty()) {
            allowKeys.forEach { key ->
                val value = event.metadata[key]?.trim().orEmpty()
                if (value.isNotEmpty()) {
                    sanitized[key] = clipMetadataValue(value, maxChars = 400)
                }
            }
        } else {
            event.metadata.entries.forEach { (key, rawValue) ->
                val normalizedKey = key.trim()
                if (normalizedKey.isEmpty() || dropKeys.contains(normalizedKey)) return@forEach
                val value = rawValue.trim()
                if (value.isNotEmpty()) {
                    sanitized[normalizedKey] = clipMetadataValue(value, maxChars = 200)
                }
                if (sanitized.size >= 8) return@forEach
            }
        }

        return JSONObject(sanitized)
    }

    private fun clipMetadataValue(value: String, maxChars: Int): String {
        if (value.length <= maxChars) return value
        if (maxChars <= 1) return "…"
        val cutoff = (maxChars - 1).coerceAtLeast(0)
        return value.substring(0, cutoff) + "…"
    }

    private fun recordLastRequestDebug(
        event: UserEvent,
        context: ExtractionContext,
        url: HttpUrl,
        stream: Boolean,
        systemPrompt: String,
        userPrompt: String,
        requestBody: String,
        metadataJson: JSONObject,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ) {
        val providerType = context.providerType?.trim().orEmpty().ifBlank {
            if (isGoogleContext(context)) "gemini" else "openai"
        }
        val model = context.model?.trim().orEmpty()
        val debug = linkedMapOf<String, Any?>(
            "captured_at_ms" to System.currentTimeMillis(),
            "provider_type" to providerType,
            "model" to model,
            "base_url" to context.baseUrl?.trim(),
            "chat_path" to context.chatPath?.trim(),
            "use_response_api" to context.useResponseApi,
            "stream" to stream,
            "url" to url.toString(),
            "event_external_id" to event.externalId,
            "event_type" to event.type,
            "event_occurred_at" to event.occurredAt,
            "event_content_len" to event.content.length,
            "metadata_json_len" to metadataJson.toString().length,
            "persona_summary_len" to currentPersonaSummary.length,
            "persona_profile_json_len" to currentPersonaProfile.toJsonString().length,
            "system_prompt_len" to systemPrompt.length,
            "user_prompt_len" to userPrompt.length,
            "request_body_len" to requestBody.length,
            "system_prompt" to systemPrompt,
            "user_prompt" to userPrompt,
            "request_body" to requestBody
        )
        lastRequestDebug = debug
    }

    private fun extractContent(raw: String, context: ExtractionContext): String {
        val json = JSONObject(raw)
        if (context.providerType.equals("gemini", ignoreCase = true)) {
            val candidates = json.optJSONArray("candidates") ?: return raw
            val sb = StringBuilder()
            for (i in 0 until candidates.length()) {
                val candidate = candidates.optJSONObject(i) ?: continue
                val content = candidate.optJSONObject("content") ?: continue
                val parts = content.optJSONArray("parts") ?: continue
                for (j in 0 until parts.length()) {
                    val part = parts.optJSONObject(j) ?: continue
                    val text = part.optString("text")
                    if (text.isNotBlank()) sb.append(text)
                }
            }
            return sb.toString().ifBlank { raw }
        }

        if (context.useResponseApi) {
            val output = json.optJSONArray("output") ?: return raw
            val sb = StringBuilder()
            for (i in 0 until output.length()) {
                val item = output.optJSONObject(i) ?: continue
                if (item.optString("type") == "message") {
                    val content = item.optJSONArray("content") ?: continue
                    for (j in 0 until content.length()) {
                        val part = content.optJSONObject(j) ?: continue
                        if (part.optString("type") == "output_text") {
                            sb.append(part.optString("text"))
                        }
                    }
                }
            }
            return sb.toString().ifBlank { raw }
        }

        val choices = json.optJSONArray("choices") ?: return raw
        if (choices.length() == 0) return raw
        val first = choices.optJSONObject(0) ?: return raw
        val message = first.optJSONObject("message") ?: return raw
        return message.optString("content", raw)
    }

    private fun shouldAttemptStreaming(context: ExtractionContext): Boolean {
        val disableFlag = context.extra["disable_streaming"]
            ?: context.extra["disable_stream"]
            ?: context.extra["memory_stream_disabled"]
        if (disableFlag != null && disableFlag.toString().equals("true", ignoreCase = true)) {
            return false
        }
        return true
    }

    private fun appendResponseDelta(event: JSONObject, target: StringBuilder) {
        val delta = event.opt("delta")
        appendContentSegment(delta, target)
        val output = event.optJSONArray("output_text")
        if (output != null) {
            for (i in 0 until output.length()) {
                appendContentSegment(output.opt(i), target)
            }
        }
    }

    private fun appendChoicesDelta(event: JSONObject, target: StringBuilder) {
        val choices = event.optJSONArray("choices") ?: return
        for (i in 0 until choices.length()) {
            val choice = choices.optJSONObject(i) ?: continue
            val delta = choice.optJSONObject("delta")
            if (delta != null) {
                appendContentSegment(delta.opt("content"), target)
            }
        }
    }

    private fun appendContentSegment(segment: Any?, target: StringBuilder) {
        when (segment) {
            null -> return
            is String -> target.append(segment)
            is JSONObject -> {
                val directText = if (segment.has("text") && segment.opt("text") is String) {
                    segment.optString("text")
                } else null

                val nestedText = segment.optJSONObject("text")?.optString("value")
                val valueField = if (segment.has("value") && segment.opt("value") is String) {
                    segment.optString("value")
                } else null
                val contentField = if (segment.opt("content") is String) {
                    segment.optString("content")
                } else null

                val chosen = listOfNotNull(directText, nestedText, valueField, contentField).firstOrNull()
                if (!chosen.isNullOrBlank()) {
                    target.append(chosen)
                }

                val nestedContent = segment.opt("content")
                if (nestedContent != null && nestedContent !is String) {
                    appendContentSegment(nestedContent, target)
                }
            }
            is JSONArray -> {
                for (i in 0 until segment.length()) {
                    appendContentSegment(segment.opt(i), target)
                }
            }
            else -> target.append(segment.toString())
        }
    }

    private class StreamingNotSupportedException(message: String) : Exception(message)

    private fun parseCandidates(text: String): UserSignalExtractionResult {
        val payload = extractJsonPayload(text)
        val personaSegment = analyzePersonaSegment(payload.trailingText)
        return try {
            val root = JSONObject(payload.jsonText)
            val persona = personaSegment.sanitized
            val patch = PersonaProfilePatch.fromJson(root.optJSONObject("persona_profile_patch"))
            val filteredOut = root.optBoolean("filtered_out", false)
            val graphEntities = if (filteredOut) emptyList() else parseGraphEntities(root.optJSONArray("graph_entities"))
            val graphEdges = if (filteredOut) emptyList() else parseGraphEdges(root.optJSONArray("graph_edges"))
            val graphClosures =
                if (filteredOut) emptyList() else parseGraphEdgeClosures(root.optJSONArray("graph_edge_closures"))

            val hasError = root.optString("error").isNotBlank()
            if (hasError) {
                FileLogger.w(TAG, "LLM 报告错误：${root.optString("error")}")
            }

            UserSignalExtractionResult(
                personaProfilePatch = patch,
                personaSummaryFallback = persona,
                rawResponse = payload.rawResponse,
                isMalformed = hasError,
                graphEntities = graphEntities,
                graphEdges = graphEdges,
                graphEdgeClosures = graphClosures
            )
        } catch (t: Throwable) {
            FileLogger.w(TAG, "解析 LLM JSON 失败：${t.message}")
            val persona = personaSegment.sanitized
            UserSignalExtractionResult(
                personaProfilePatch = null,
                personaSummaryFallback = persona,
                rawResponse = payload.rawResponse,
                isMalformed = true
            )
        }
    }

    private fun parseGraphEntities(array: JSONArray?): List<GraphEntityCandidate> {
        if (array == null || array.length() == 0) return emptyList()
        val out = mutableListOf<GraphEntityCandidate>()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val key = obj.optString("entity_key").trim()
            if (key.isBlank()) continue
            val type = obj.optString("type").trim().ifBlank { key.substringBefore(':', missingDelimiterValue = "Unknown") }
            val name = obj.optString("name").trim().ifBlank { key.substringAfter(':', missingDelimiterValue = key) }
            val aliases = parseStringList(obj.optJSONArray("aliases"))
            val metadata = parseStringMap(obj.optJSONObject("metadata"))
            val confidence = obj.optDouble("confidence", 0.6).coerceIn(0.0, 1.0)
            out += GraphEntityCandidate(
                entityKey = key,
                type = type,
                name = name,
                aliases = aliases,
                metadata = metadata,
                confidence = confidence
            )
        }
        return out
    }

    private fun parseGraphEdges(array: JSONArray?): List<GraphEdgeCandidate> {
        if (array == null || array.length() == 0) return emptyList()
        val out = mutableListOf<GraphEdgeCandidate>()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val subjectKey = obj.optString("subject_key").trim()
            val predicate = obj.optString("predicate").trim()
            if (subjectKey.isBlank() || predicate.isBlank()) continue
            val objectKey = obj.optString("object_key").trim().ifBlank { null }
            val objectValue = obj.optString("object_value").trim().ifBlank { null }
            if (objectKey == null && objectValue == null) continue
            val qualifiers = parseStringMap(obj.optJSONObject("qualifiers"))
            val isState: Boolean? = when {
                obj.has("is_state") -> obj.optBoolean("is_state")
                obj.has("stateful") -> obj.optBoolean("stateful")
                obj.has("is_stateful") -> obj.optBoolean("is_stateful")
                else -> null
            }
            val confidence = obj.optDouble("confidence", 0.6).coerceIn(0.0, 1.0)
            val excerpt = obj.optString("evidence_excerpt").trim().ifBlank { null }
            out += GraphEdgeCandidate(
                subjectKey = subjectKey,
                predicate = predicate,
                objectKey = objectKey,
                objectValue = objectValue,
                qualifiers = qualifiers,
                isState = isState,
                confidence = confidence,
                evidenceExcerpt = excerpt
            )
        }
        return out
    }

    private fun parseGraphEdgeClosures(array: JSONArray?): List<GraphEdgeClosureCandidate> {
        if (array == null || array.length() == 0) return emptyList()
        val out = mutableListOf<GraphEdgeClosureCandidate>()
        for (i in 0 until array.length()) {
            val obj = array.optJSONObject(i) ?: continue
            val subjectKey = obj.optString("subject_key").trim()
            val predicate = obj.optString("predicate").trim()
            if (subjectKey.isBlank() || predicate.isBlank()) continue
            val objectKey = obj.optString("object_key").trim().ifBlank { null }
            val objectValue = obj.optString("object_value").trim().ifBlank { null }
            val qualifiers = parseStringMap(obj.optJSONObject("qualifiers"))
            val reason = obj.optString("reason").trim().ifBlank { null }
            out += GraphEdgeClosureCandidate(
                subjectKey = subjectKey,
                predicate = predicate,
                objectKey = objectKey,
                objectValue = objectValue,
                qualifiers = qualifiers,
                reason = reason
            )
        }
        return out
    }

    private fun parseStringList(array: JSONArray?): List<String> {
        if (array == null || array.length() == 0) return emptyList()
        val out = mutableListOf<String>()
        for (i in 0 until array.length()) {
            val v = array.optString(i).trim()
            if (v.isNotEmpty()) out += v
        }
        return out
    }

    private fun parseStringMap(obj: JSONObject?): Map<String, String> {
        if (obj == null || obj.length() == 0) return emptyMap()
        val out = LinkedHashMap<String, String>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next().trim()
            if (key.isEmpty()) continue
            val value = obj.optString(key).trim()
            if (value.isNotEmpty()) {
                out[key] = value
            }
        }
        return out
    }

    private fun extractJsonPayload(text: String): JsonPayload {
        val trimmed = text.trim()
        val start = trimmed.indexOf('{')
        val end = trimmed.lastIndexOf('}')
        if (start < 0 || end <= start) {
            return JsonPayload("{\"filtered_out\":true}", trimmed, text)
        }
        val jsonText = trimmed.substring(start, end + 1)
        val trailing = if (end + 1 < trimmed.length) trimmed.substring(end + 1).trim() else ""
        return JsonPayload(jsonText, trailing, text)
    }

    private fun analyzePersonaSegment(raw: String?): PersonaSegment {
        val segment = raw?.trim() ?: ""
        if (segment.isEmpty()) {
            return PersonaSegment(null, false, raw ?: "")
        }
        val lowered = segment.lowercase()
        val hasMarker = PERSONA_MARKERS.any { lowered.startsWith(it) }
        val sanitized = sanitizePersonaSummary(segment)
        return PersonaSegment(sanitized, hasMarker, raw ?: "")
    }

    private suspend fun callGeminiEndpoint(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult {
        if (!shouldAttemptStreaming(context)) {
            return callGeminiEndpointBlocking(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        }
        return try {
            callGeminiEndpointStreaming(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        } catch (e: StreamingNotSupportedException) {
            FileLogger.i(TAG, "Gemini 流式不可用，回退非流式：${e.message}")
            callGeminiEndpointBlocking(
                event = event,
                context = context,
                currentPersonaSummary = currentPersonaSummary,
                currentPersonaProfile = currentPersonaProfile
            )
        }
    }

    private suspend fun callGeminiEndpointBlocking(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildGeminiUrl(event, context, stream = false)
        val payload = buildGeminiRequestBody(
            event,
            context,
            currentPersonaSummary,
            currentPersonaProfile,
            url = url,
            stream = false
        )

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("x-goog-api-key", context.apiKey.orEmpty())
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        FileLogger.i(TAG, "LLM(Gemini) 请求：url=$url model=${context.model}")
        FileLogger.d(TAG, "LLM(Gemini) 请求体=$payload")

        okHttpClient.newCall(request).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            FileLogger.d(TAG, "LLM(Gemini) 响应：code=${resp.code} body=$body")
            if (!resp.isSuccessful) {
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "Gemini 请求失败：code=${resp.code} body=${snippet}")
                throw LlmHttpException(resp.code, snippet, event.externalId)
            }
            val text = extractContent(body, context.copy(providerType = "gemini"))
            parseCandidates(text)
        }
    }

    private suspend fun callGeminiEndpointStreaming(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildGeminiUrl(event, context, stream = true)
        val payload = buildGeminiRequestBody(
            event,
            context,
            currentPersonaSummary,
            currentPersonaProfile,
            url = url,
            stream = true
        )

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("Accept", "text/event-stream")
            .addHeader("x-goog-api-key", context.apiKey.orEmpty())
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        FileLogger.i(TAG, "LLM(Gemini流式) 请求：url=$url model=${context.model}")
        FileLogger.d(TAG, "LLM(Gemini) 请求体=$payload")

        okHttpClient.newCall(request).execute().use { resp ->
            if (!resp.isSuccessful) {
                val body = resp.body?.string().orEmpty()
                FileLogger.d(TAG, "LLM(Gemini流式) 响应：code=${resp.code} body=$body")
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "Gemini 请求失败：code=${resp.code} body=${snippet}")
                if (resp.code == 400 || resp.code == 404 || resp.code == 405) {
                    throw StreamingNotSupportedException("HTTP ${resp.code}")
                }
                throw LlmHttpException(resp.code, snippet, event.externalId)
            }
            val responseBody = resp.body ?: throw StreamingNotSupportedException("Empty response body")
            val reader = responseBody.charStream().buffered()
            val aggregated = StringBuilder()
            val rawEvents = StringBuilder()
            var sawData = false
            var lastCumulative = ""
            reader.use { buffered ->
                while (true) {
                    val line = buffered.readLine() ?: break
                    if (line.isEmpty()) continue
                    if (!line.startsWith("data:")) continue
                    val data = line.substring(5).trim()
                    if (data.isEmpty()) continue
                    if (data == "[DONE]") break
                    sawData = true
                    rawEvents.append(data).append('\n')
                    try {
                        val json = JSONObject(data)
                        if (json.has("error")) {
                            val message = json.optJSONObject("error")?.optString("message")
                                ?: json.optString("error")
                            throw LlmHttpException(resp.code, message.take(MAX_ERROR_BODY_CHARS), event.externalId)
                        }
                        var chunkText = ""
                        val candidates = json.optJSONArray("candidates")
                        if (candidates != null && candidates.length() > 0) {
                            val c0 = candidates.optJSONObject(0)
                            val ct = c0?.optJSONObject("content")
                            val parts = ct?.optJSONArray("parts")
                            if (parts != null && parts.length() > 0) {
                                val sb = StringBuilder()
                                for (i in 0 until parts.length()) {
                                    val p = parts.optJSONObject(i) ?: continue
                                    val t = p.optString("text")
                                    if (t.isNotBlank()) sb.append(t)
                                }
                                chunkText = sb.toString()
                            }
                        }
                        if (chunkText.isBlank()) continue
                        val delta = if (chunkText.startsWith(lastCumulative)) {
                            chunkText.substring(lastCumulative.length)
                        } else {
                            chunkText
                        }
                        if (delta.isNotBlank()) {
                            aggregated.append(delta)
                        }
                        lastCumulative = if (chunkText.startsWith(lastCumulative)) {
                            chunkText
                        } else {
                            lastCumulative + chunkText
                        }
                    } catch (ex: Exception) {
                        aggregated.append(data)
                    }
                }
            }
            if (!sawData) {
                FileLogger.w(TAG, "Gemini 流式返回无数据；raw=${rawEvents.take(MAX_ERROR_BODY_CHARS)}")
                throw StreamingNotSupportedException("No data received")
            }
            val finalText = aggregated.toString().ifBlank { rawEvents.toString() }
            FileLogger.d(TAG, "LLM(Gemini流式) 聚合长度=${finalText.length}")
            parseCandidates(finalText)
        }
    }

    private fun buildGeminiUrl(event: UserEvent, context: ExtractionContext, stream: Boolean): HttpUrl {
        val base = resolveBaseUrl(context.baseUrl, DEFAULT_GEMINI_BASE, event)
        val model = context.model?.takeIf { it.isNotBlank() } ?: DEFAULT_GEMINI_MODEL
        val rawPath = context.chatPath?.trim().orEmpty()
        val defaultPath = if (stream) {
            "/v1beta/models/$model:streamGenerateContent"
        } else {
            "/v1beta/models/$model:generateContent"
        }
        val effectivePath = when {
            rawPath.isEmpty() -> defaultPath
            stream && rawPath.contains("streamGenerateContent", ignoreCase = true) -> rawPath
            !stream && rawPath.contains("generateContent", ignoreCase = true) &&
                !rawPath.contains("streamGenerateContent", ignoreCase = true) -> rawPath
            stream && rawPath.contains("generateContent", ignoreCase = true) -> rawPath.replace(
                "generateContent",
                "streamGenerateContent",
                ignoreCase = true
            )
            !stream && rawPath.contains("streamGenerateContent", ignoreCase = true) -> rawPath.replace(
                "streamGenerateContent",
                "generateContent",
                ignoreCase = true
            )
            rawPath.contains("chat/completions", ignoreCase = true) -> defaultPath
            rawPath.contains("models", ignoreCase = true) && rawPath.contains(":") -> rawPath
            else -> defaultPath
        }
        val resolved = resolveEndpointUrl(base, effectivePath, event)
        return if (stream) {
            resolved.newBuilder().addQueryParameter("alt", "sse").build()
        } else {
            resolved
        }
    }

    private fun buildGeminiRequestBody(
        event: UserEvent,
        context: ExtractionContext,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile,
        url: HttpUrl,
        stream: Boolean
    ): String {
        val metadataJson = buildPromptMetadataJson(event)
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            personaSummary = currentPersonaSummary,
            personaProfile = currentPersonaProfile
        )
        val systemPrompt = MemoryPromptProvider.systemPrompt()

        val systemInstruction = JSONObject()
            .put("parts", JSONArray().put(JSONObject().put("text", systemPrompt)))
        val userContent = JSONObject()
            .put("role", "user")
            .put("parts", JSONArray().put(JSONObject().put("text", userPrompt)))

        val body = JSONObject()
            .put("system_instruction", systemInstruction)
            .put("contents", JSONArray().put(userContent))
            .put(
                "generationConfig",
                JSONObject()
                    .put("temperature", 0.1)
                    .put("responseMimeType", "application/json")
            )
            .toString()

        recordLastRequestDebug(
            event = event,
            context = context.copy(providerType = "gemini"),
            url = url,
            stream = stream,
            systemPrompt = systemPrompt,
            userPrompt = userPrompt,
            requestBody = body,
            metadataJson = metadataJson,
            currentPersonaSummary = currentPersonaSummary,
            currentPersonaProfile = currentPersonaProfile
        )
        return body
    }

    private fun resolveBaseUrl(raw: String?, fallback: String, event: UserEvent): HttpUrl {
        val candidate = raw?.trim().takeIf { !it.isNullOrEmpty() } ?: fallback
        val direct = candidate.toHttpUrlOrNull()
        if (direct != null) return direct
        val httpsCandidate = "https://$candidate"
        val httpsParsed = httpsCandidate.toHttpUrlOrNull()
        if (httpsParsed != null) return httpsParsed
        throw LlmEndpointConfigurationException("Invalid base URL: $candidate", event.externalId)
    }

    private fun resolveEndpointUrl(base: HttpUrl, rawPath: String, event: UserEvent): HttpUrl {
        val candidate = rawPath.trim()
        if (candidate.startsWith("http", ignoreCase = true)) {
            return candidate.toHttpUrlOrNull()
                ?: throw LlmEndpointConfigurationException("Invalid endpoint URL: $candidate", event.externalId)
        }
        val normalized = if (candidate.startsWith("/")) candidate else "/$candidate"
        return base.resolve(normalized)
            ?: throw LlmEndpointConfigurationException("Invalid endpoint path: $candidate", event.externalId)
    }

    private data class JsonPayload(
        val jsonText: String,
        val trailingText: String,
        val rawResponse: String
    )

    private data class PersonaSegment(
        val sanitized: String?,
        val hasMarker: Boolean,
        val rawSegment: String
    )

    private fun sanitizePersonaSummary(raw: String?): String? {
        if (raw == null) return null
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val withoutPrefix = trimmed
            .removePrefix("当前用户描述：")
            .removePrefix("当前用户描述:")
            .removePrefix("Persona summary:")
            .removePrefix("User summary:")
            .trim()
        val candidate = (if (withoutPrefix.isNotEmpty()) withoutPrefix else trimmed).trim()
        if (candidate.isEmpty()) return null
        val hasAlphanumeric = candidate.any { it.isLetterOrDigit() }
        if (!hasAlphanumeric) return null
        val meaningfulCharCount = candidate.count { it.isLetterOrDigit() }
        if (candidate.length <= 6 && meaningfulCharCount <= 1) return null
        return candidate
    }

    private fun formatTimestamp(epochMillis: Long): String {
        return runCatching {
            DateTimeFormatter.ISO_OFFSET_DATE_TIME.format(
                Instant.ofEpochMilli(epochMillis).atOffset(ZoneOffset.UTC)
            )
        }.getOrDefault("")
    }

    companion object {
        private const val TAG = "LlmUserSignalExtractor"
        private const val DEFAULT_OPENAI_BASE = "https://api.openai.com"
        private const val DEFAULT_OPENAI_CHAT_PATH = "/v1/chat/completions"
        private const val OPENAI_RESPONSES_PATH = "/v1/responses"
        private const val DEFAULT_GEMINI_BASE = "https://generativelanguage.googleapis.com"
        private const val DEFAULT_GEMINI_MODEL = "gemini-1.5-pro"
        private const val MAX_ERROR_BODY_CHARS = 4000
        private val JSON_MEDIA_TYPE = "application/json".toMediaType()
        private val PERSONA_MARKERS = listOf(
            "当前用户描述：",
            "当前用户描述:",
            "persona summary:",
            "user summary:"
        )

        @Volatile
        private var lastRequestDebug: Map<String, Any?>? = null

        fun getLastRequestDebug(): Map<String, Any?>? = lastRequestDebug
    }
}

class LlmHttpException(
    val statusCode: Int,
    val responseBody: String,
    val eventExternalId: String?
) : Exception("LLM HTTP $statusCode")

class LlmEndpointConfigurationException(
    message: String,
    val eventExternalId: String?
) : Exception(message)
