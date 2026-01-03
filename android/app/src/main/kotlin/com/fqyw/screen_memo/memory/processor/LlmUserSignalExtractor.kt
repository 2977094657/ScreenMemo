package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.FileLogger
import com.fqyw.screen_memo.OkHttpClientFactory
import com.fqyw.screen_memo.memory.model.PersonaProfile
import com.fqyw.screen_memo.memory.model.PersonaProfilePatch
import com.fqyw.screen_memo.memory.model.TagCategory
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
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult {
        if (context == null || !context.isValid) return UserSignalExtractionResult(emptyList(), null, null)
        if (!supportsContext(context)) return UserSignalExtractionResult(emptyList(), null, null)
        return try {
            if (isGoogleContext(context)) {
                callGeminiEndpoint(event, context, existingTagPaths, currentPersonaSummary, currentPersonaProfile)
            } else {
                callOpenAiStyleEndpoint(event, context, existingTagPaths, currentPersonaSummary, currentPersonaProfile)
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
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult {
        if (shouldAttemptStreaming(context)) {
            try {
                return callOpenAiStyleEndpointStreaming(
                    event = event,
                    context = context,
                    existingTagPaths = existingTagPaths,
                    currentPersonaSummary = currentPersonaSummary,
                    currentPersonaProfile = currentPersonaProfile
                )
            } catch (e: StreamingNotSupportedException) {
                FileLogger.w(TAG, "不支持流式：${e.message}")
            } catch (e: Throwable) {
                FileLogger.w(TAG, "流式失败，回退到非流式：${e.message}")
            }
        }
        return callOpenAiStyleEndpointBlocking(
            event = event,
            context = context,
            existingTagPaths = existingTagPaths,
            currentPersonaSummary = currentPersonaSummary,
            currentPersonaProfile = currentPersonaProfile
        )
    }

    private suspend fun callOpenAiStyleEndpointBlocking(
        event: UserEvent,
        context: ExtractionContext,
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildOpenAiUrl(event, context)
        val headers = buildOpenAiHeaders(context)
        val payload = buildOpenAiRequestBody(
            event,
            context,
            existingTagPaths,
            currentPersonaSummary,
            currentPersonaProfile,
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
            parseCandidates(text, event, context)
        }
    }

    private suspend fun callOpenAiStyleEndpointStreaming(
        event: UserEvent,
        context: ExtractionContext,
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildOpenAiUrl(event, context)
        val headers = buildOpenAiHeaders(context).toMutableMap()
        headers["Accept"] = "text/event-stream"
        val payload = buildOpenAiRequestBody(
            event,
            context,
            existingTagPaths,
            currentPersonaSummary,
            currentPersonaProfile,
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
            parseCandidates(finalText, event, context)
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
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile,
        stream: Boolean = false
    ): String {
        val metadataJson = JSONObject(event.metadata)
        val model = context.model?.trim().orEmpty()
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            existingTags = existingTagPaths,
            personaSummary = currentPersonaSummary,
            personaProfile = currentPersonaProfile
        )
        val systemPrompt = MemoryPromptProvider.systemPrompt()
        return if (context.useResponseApi) {
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

    private fun parseCandidates(text: String, event: UserEvent, context: ExtractionContext): UserSignalExtractionResult {
        val payload = extractJsonPayload(text)
        val personaSegment = analyzePersonaSegment(payload.trailingText)
        return try {
            val root = JSONObject(payload.jsonText)
            if (root.optString("error").isNotBlank()) {
                FileLogger.w(TAG, "LLM 报告错误：${root.optString("error")}")
                val persona = personaSegment.sanitized
                val patch = PersonaProfilePatch.fromJson(root.optJSONObject("persona_profile_patch"))
                UserSignalExtractionResult(
                    candidates = emptyList(),
                    personaProfilePatch = patch,
                    personaSummaryFallback = persona,
                    rawResponse = payload.rawResponse,
                    isMalformed = false
                )
            } else {
                val filteredOut = root.optBoolean("filtered_out", false)
                if (filteredOut) {
                    val persona = personaSegment.sanitized
                    val patch = PersonaProfilePatch.fromJson(root.optJSONObject("persona_profile_patch"))
                    return UserSignalExtractionResult(
                        candidates = emptyList(),
                        personaProfilePatch = patch,
                        personaSummaryFallback = persona,
                        rawResponse = payload.rawResponse,
                        isMalformed = false,
                        graphEntities = emptyList(),
                        graphEdges = emptyList(),
                        graphEdgeClosures = emptyList()
                    )
                }
                val confirmedTags = collectConfirmedTags(root.optJSONArray("update_tags"))
                val clues = root.optJSONArray("extracted_user_related_clues") ?: JSONArray()
                val list = mutableListOf<TagCandidate>()
                for (i in 0 until clues.length()) {
                    val clue = clues.optJSONObject(i) ?: continue
                    val suggestedRaw = clue.optString("tag_suggested")
                    val hierarchy = parseHierarchy(suggestedRaw) ?: continue
                    val key = buildTagKey(hierarchy)
                    if (key.isBlank()) continue
                    val label = hierarchy.fullPath
                    val category = inferCategoryFromLevel(hierarchy.level1)
                    val statusRaw = clue.optString("tag_status")
                    val inference = clue.optString("clue_text").trim()
                    val isConfirmed = normalizeStatus(statusRaw) || confirmedTags.contains(key)
                    val confidence = if (isConfirmed) 0.85 else 0.6
                    val evidenceIds = extractEvidenceIds(clue.optJSONArray("evidence"))
                    val evidenceText = buildEvidenceText(
                        clue.optString("clue_text"),
                        clue.optString("event_brief"),
                        evidenceIds
                    )

                    list += TagCandidate(
                        tagKey = key,
                        label = label,
                        category = category,
                        hierarchy = hierarchy,
                        inference = inference.ifBlank { null },
                        confidence = confidence,
                        evidence = evidenceText,
                        notes = null,
                        autoConfirmThreshold = if (isConfirmed) 1 else TagCandidate.DEFAULT_AUTO_CONFIRM_THRESHOLD,
                        shouldOverrideLabel = false,
                        forceOverrideEvidence = false,
                        metadata = mapOf(
                            "tag_status" to statusRaw,
                            "level1" to hierarchy.level1,
                            "level2" to hierarchy.level2,
                            "level3" to hierarchy.level3,
                            "level4" to hierarchy.level4,
                            "full_path" to hierarchy.fullPath,
                            "provider_type" to (context.providerType ?: ""),
                            "provider_name" to (context.providerName ?: ""),
                            "model" to (context.model ?: ""),
                            "evidence_refs" to evidenceIds.joinToString(",")
                        )
                    )
                }
                val persona = personaSegment.sanitized
                val patch = PersonaProfilePatch.fromJson(root.optJSONObject("persona_profile_patch"))
                val graphEntities = parseGraphEntities(root.optJSONArray("graph_entities"))
                val graphEdges = parseGraphEdges(root.optJSONArray("graph_edges"))
                val graphClosures = parseGraphEdgeClosures(root.optJSONArray("graph_edge_closures"))
                UserSignalExtractionResult(
                    candidates = list,
                    personaProfilePatch = patch,
                    personaSummaryFallback = persona,
                    rawResponse = payload.rawResponse,
                    isMalformed = false,
                    graphEntities = graphEntities,
                    graphEdges = graphEdges,
                    graphEdgeClosures = graphClosures
                )
            }
        } catch (t: Throwable) {
            FileLogger.w(TAG, "解析 LLM JSON 失败：${t.message}")
            val persona = personaSegment.sanitized
            UserSignalExtractionResult(emptyList(), null, persona, payload.rawResponse, false)
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
            return JsonPayload("{\"extracted_user_related_clues\":[]}", trimmed, text)
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
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildGeminiUrl(event, context)
        val payload = buildGeminiRequestBody(event, existingTagPaths, currentPersonaSummary, currentPersonaProfile)

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
            val text = extractContent(body, context)
            parseCandidates(text, event, context)
        }
    }

    private fun buildGeminiUrl(event: UserEvent, context: ExtractionContext): HttpUrl {
        val base = resolveBaseUrl(context.baseUrl, DEFAULT_GEMINI_BASE, event)
        val model = context.model?.takeIf { it.isNotBlank() } ?: DEFAULT_GEMINI_MODEL
        val rawPath = context.chatPath?.trim().orEmpty()
        val effectivePath = when {
            rawPath.isEmpty() -> "/v1beta/models/$model:generateContent"
            rawPath.contains("chat/completions", ignoreCase = true) -> "/v1beta/models/$model:generateContent"
            !rawPath.contains("models", ignoreCase = true) -> "/v1beta/models/$model:generateContent"
            else -> rawPath
        }
        return resolveEndpointUrl(base, effectivePath, event)
    }

    private fun buildGeminiRequestBody(
        event: UserEvent,
        existingTagPaths: List<String>,
        currentPersonaSummary: String,
        currentPersonaProfile: PersonaProfile
    ): String {
        val metadataJson = JSONObject(event.metadata)
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            existingTags = existingTagPaths,
            personaSummary = currentPersonaSummary,
            personaProfile = currentPersonaProfile
        )
        val systemPrompt = MemoryPromptProvider.systemPrompt()

        val systemInstruction = JSONObject()
            .put("parts", JSONArray().put(JSONObject().put("text", systemPrompt)))
        val userContent = JSONObject()
            .put("role", "user")
            .put("parts", JSONArray().put(JSONObject().put("text", userPrompt)))

        return JSONObject()
            .put("system_instruction", systemInstruction)
            .put("contents", JSONArray().put(userContent))
            .put(
                "generationConfig",
                JSONObject()
                    .put("temperature", 0.1)
                    .put("responseMimeType", "application/json")
            )
            .toString()
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

    private fun collectConfirmedTags(array: JSONArray?): Set<String> {
        if (array == null) return emptySet()
        val set = mutableSetOf<String>()
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val hierarchy = parseHierarchy(item.optString("tag")) ?: continue
            val tag = buildTagKey(hierarchy)
            val newStatus = item.optString("new_status")
            if (tag.isNotBlank() && normalizeStatus(newStatus)) {
                set += tag
            }
        }
        return set
    }

    private fun normalizeStatus(status: String?): Boolean {
        val v = status?.trim()?.lowercase() ?: return false
        return v == "已确认" || v == "已確認" || v == "confirmed" || v == "确认" || v == "confirm"
    }

    private fun inferCategoryFromLevel(level1: String): TagCategory {
        val normalized = level1.trim().lowercase()
        return when {
            normalized.contains("兴趣") || normalized.contains("爱好") || normalized.contains("hobby") -> TagCategory.INTEREST
            normalized.contains("关系") || normalized.contains("family") || normalized.contains("亲友") -> TagCategory.RELATIONSHIP
            normalized.contains("行为") || normalized.contains("习惯") || normalized.contains("behavior") -> TagCategory.BEHAVIOR
            normalized.contains("偏好") || normalized.contains("喜好") || normalized.contains("preference") -> TagCategory.PREFERENCE
            normalized.contains("身份") || normalized.contains("昵称") || normalized.contains("姓名") || normalized.contains("职业") || normalized.contains("角色") -> TagCategory.IDENTITY
            normalized.contains("技能") || normalized.contains("skill") -> TagCategory.PREFERENCE
            else -> TagCategory.OTHER
        }
    }

    private fun extractEvidenceIds(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        val list = mutableListOf<String>()
        for (i in 0 until array.length()) {
            val value = array.optString(i)
            if (value.isNotBlank()) list += value
        }
        return list
    }

    private fun buildEvidenceText(clue: String, brief: String, refs: List<String>): String {
        val normalizedClue = clue.trim()
        val normalizedBrief = brief.trim()
        val base = when {
            normalizedBrief.isNotEmpty() -> normalizedBrief
            normalizedClue.isNotEmpty() -> normalizedClue
            else -> "用户相关线索"
        }
        if (refs.isEmpty()) {
            return base
        }
        return buildString {
            append(base)
            append(" [ref=")
            append(refs.joinToString(","))
            append("]")
        }
    }

    private fun parseHierarchy(raw: String?): TagHierarchy? {
        if (raw.isNullOrBlank()) return null
        val normalized = raw.replace("／", "/").replace("｜", "|")
        val segments = normalized.split('/', '|')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (segments.size < 4) return null
        val fixed = segments.take(4)
        val hierarchy = TagHierarchy(
            level1 = fixed[0],
            level2 = fixed[1],
            level3 = fixed[2],
            level4 = fixed[3]
        )
        return if (hierarchy.isValid()) hierarchy else null
    }

    private fun buildTagKey(hierarchy: TagHierarchy): String {
        val segments = listOf(hierarchy.level1, hierarchy.level2, hierarchy.level3, hierarchy.level4)
        val slug = segments.joinToString("|") { slugify(it) }
        return slug.lowercase()
    }

    private fun slugify(input: String): String {
        val normalized = input.trim()
            .lowercase()
            .replace('：', ':')
            .replace('/', ' ')
            .replace('|', ' ')
        val builder = StringBuilder()
        for (ch in normalized) {
            when {
                ch in 'a'..'z' || ch in '0'..'9' -> builder.append(ch)
                ch == '-' || ch == '_' -> builder.append(ch)
                ch.isWhitespace() -> {
                    if (builder.length > 0 && builder[builder.length - 1] != '_') {
                        builder.append('_')
                    }
                }
                else -> {}
            }
        }
        val result = builder.toString().trim('_')
        return if (result.isNotEmpty()) result else normalized.replace("\\s+".toRegex(), "_")
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
