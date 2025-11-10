package com.fqyw.screen_memo.memory.processor

import com.fqyw.screen_memo.FileLogger
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
    private val okHttpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .writeTimeout(0, TimeUnit.SECONDS)
        .build()
) : UserSignalExtractor {

    override suspend fun extractSignals(
        event: UserEvent,
        context: ExtractionContext?,
        existingTagPaths: List<String>,
        currentPersonaSummary: String
    ): UserSignalExtractionResult {
        if (context == null || !context.isValid) return UserSignalExtractionResult(emptyList(), null)
        if (!supportsContext(context)) return UserSignalExtractionResult(emptyList(), null)
        return try {
            when (context.providerType?.lowercase()) {
                "gemini" -> callGeminiEndpoint(event, context, existingTagPaths, currentPersonaSummary)
                else -> callOpenAiStyleEndpoint(event, context, existingTagPaths, currentPersonaSummary)
            }
        } catch (t: Throwable) {
            FileLogger.w(TAG, "LLM extraction failed: ${t.message}")
            throw t
        }
    }

    private fun supportsContext(context: ExtractionContext): Boolean {
        val type = context.providerType?.lowercase()
        return type == "openai" || type == "custom" || type == "azure_openai" || type == "gemini"
    }

    private suspend fun callOpenAiStyleEndpoint(
        event: UserEvent,
        context: ExtractionContext,
        existingTagPaths: List<String>,
        currentPersonaSummary: String
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildOpenAiUrl(event, context)
        val headers = buildOpenAiHeaders(context)
        val payload = buildOpenAiRequestBody(event, context, existingTagPaths, currentPersonaSummary)

        val request = Request.Builder()
            .url(url)
            .apply { headers.forEach { (k, v) -> addHeader(k, v) } }
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        okHttpClient.newCall(request).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "LLM request failed: code=${resp.code} body=${snippet}")
                throw LlmHttpException(resp.code, snippet, event.externalId)
            }
            val text = extractContent(body, context)
            parseCandidates(text, event, context)
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
        currentPersonaSummary: String
    ): String {
        val metadataJson = JSONObject(event.metadata)
        val model = context.model?.trim().orEmpty()
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            existingTags = existingTagPaths,
            personaSummary = currentPersonaSummary
        )
        val systemPrompt = MemoryPromptProvider.systemPrompt()
        return if (context.useResponseApi) {
            JSONObject()
                .put("model", model)
                .put("input", JSONArray().put(JSONObject().put("role", "user").put("content", userPrompt)))
                .put("temperature", 0.1)
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

    private fun parseCandidates(text: String, event: UserEvent, context: ExtractionContext): UserSignalExtractionResult {
        val payload = extractJsonPayload(text)
        val personaSegment = analyzePersonaSegment(payload.trailingText)
        return try {
            val root = JSONObject(payload.jsonText)
            if (root.optString("error").isNotBlank()) {
                FileLogger.w(TAG, "LLM reported error: ${root.optString("error")}")
                val persona = personaSegment.sanitized
                UserSignalExtractionResult(emptyList(), persona, payload.rawResponse, false)
            } else {
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
                UserSignalExtractionResult(list, persona, payload.rawResponse, false)
            }
        } catch (t: Throwable) {
            FileLogger.w(TAG, "Failed to parse LLM JSON: ${t.message}")
            val persona = personaSegment.sanitized
            UserSignalExtractionResult(emptyList(), persona, payload.rawResponse, false)
        }
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
        currentPersonaSummary: String
    ): UserSignalExtractionResult = withContext(Dispatchers.IO) {
        val url = buildGeminiUrl(event, context)
        val payload = buildGeminiRequestBody(event, existingTagPaths, currentPersonaSummary)

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("x-goog-api-key", context.apiKey.orEmpty())
            .post(payload.toRequestBody(JSON_MEDIA_TYPE))
            .build()

        okHttpClient.newCall(request).execute().use { resp ->
            val body = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                val snippet = body.take(MAX_ERROR_BODY_CHARS)
                FileLogger.w(TAG, "Gemini request failed: code=${resp.code} body=${snippet}")
                throw LlmHttpException(resp.code, snippet, event.externalId)
            }
            val text = extractContent(body, context)
            parseCandidates(text, event, context)
        }
    }

    private fun buildGeminiUrl(event: UserEvent, context: ExtractionContext): HttpUrl {
        val base = resolveBaseUrl(context.baseUrl, DEFAULT_GEMINI_BASE, event)
        val model = context.model?.takeIf { it.isNotBlank() } ?: DEFAULT_GEMINI_MODEL
        val path = context.chatPath?.takeIf { it.isNotBlank() } ?: "/v1beta/models/$model:generateContent"
        return resolveEndpointUrl(base, path, event)
    }

    private fun buildGeminiRequestBody(
        event: UserEvent,
        existingTagPaths: List<String>,
        currentPersonaSummary: String
    ): String {
        val metadataJson = JSONObject(event.metadata)
        val userPrompt = MemoryPromptProvider.userPrompt(
            eventId = metadataJson.optString("event_id").ifBlank { event.externalId ?: "" },
            timestamp = metadataJson.optString("event_timestamp").ifBlank { formatTimestamp(event.occurredAt) },
            content = event.content,
            metadata = metadataJson,
            existingTags = existingTagPaths,
            personaSummary = currentPersonaSummary
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
        val builder = StringBuilder()
        if (clue.isNotBlank()) {
            builder.append(clue.trim())
        }
        if (brief.isNotBlank() && !brief.equals(clue, ignoreCase = true)) {
            if (builder.isNotEmpty()) builder.append(" / ")
            builder.append(brief.trim())
        }
        if (refs.isNotEmpty()) {
            if (builder.isNotEmpty()) builder.append(" ")
            builder.append("[ref=").append(refs.joinToString(",")).append("]")
        }
        if (builder.isEmpty()) {
            builder.append(clue.ifBlank { brief.ifBlank { "用户相关线索" } })
        }
        return builder.toString()
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
        return if (withoutPrefix.isNotEmpty()) withoutPrefix else trimmed
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

