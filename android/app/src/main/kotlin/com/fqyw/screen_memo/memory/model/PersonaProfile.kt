package com.fqyw.screen_memo.memory.model

import org.json.JSONArray
import org.json.JSONObject
import java.util.LinkedHashMap

/**
 * 结构化的用户画像数据，支持增量更新。
 */
data class PersonaProfile(
    val title: String,
    val sections: LinkedHashMap<String, PersonaSection>,
    val traits: List<String>,
    val version: Int,
    val lastUpdatedAt: Long
) {

    fun toJsonString(): String {
        return toJson().toString()
    }

    fun toPrettyJsonString(indent: Int = 2): String {
        return runCatching { toJson().toString(indent) }.getOrElse { toJsonString() }
    }

    fun toJson(): JSONObject {
        val sectionsArray = JSONArray()
        sections.values.forEach { section ->
            sectionsArray.put(section.toJson())
        }
        val traitsArray = JSONArray()
        traits.forEach { trait -> traitsArray.put(trait) }
        return JSONObject()
            .put("title", title)
            .put("version", version)
            .put("lastUpdatedAt", lastUpdatedAt)
            .put("sections", sectionsArray)
            .put("traits", traitsArray)
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "title" to title,
            "version" to version,
            "lastUpdatedAt" to lastUpdatedAt,
            "sections" to sections.values.map { it.toMap() },
            "traits" to traits
        )
    }

    fun toMarkdown(): String {
        val builder = StringBuilder()
        builder.append(title.trim()).append("\n\n")
        sections.values.forEach { section ->
            if (section.items.isEmpty()) return@forEach
            builder.append(section.title.trim()).append("\n\n")
            section.items.forEach { item ->
                val heading = item.heading.trim()
                val detail = item.detail.trim()
                builder.append("*   **${item.slot}. $heading**")
                if (detail.isNotEmpty()) {
                    builder.append(": ").append(detail)
                }
                builder.append("\n")
            }
            builder.append("\n")
        }
        if (traits.isNotEmpty()) {
            builder.append("#### **用户核心特质总结**\n\n")
            traits.forEach { trait ->
                builder.append("* ").append(trait.trim()).append("\n")
            }
        }
        return builder.toString().trim()
    }

    fun applyPatch(patch: PersonaProfilePatch): PersonaProfile {
        val updatedTitle = patch.title?.takeIf { it.isNotBlank() } ?: title
        val sectionMap = LinkedHashMap(sections)
        patch.sections.forEach { (rawId, sectionPatch) ->
            val id = rawId.trim()
            if (id.isEmpty()) return@forEach
            val existing = sectionMap[id]
            val updated = if (existing != null) {
                existing.copy(
                    title = sectionPatch.title?.takeIf { it.isNotBlank() } ?: existing.title,
                    items = sectionPatch.items ?: existing.items
                )
            } else {
                val title = sectionPatch.title?.takeIf { it.isNotBlank() } ?: defaultSectionTitle(id)
                val items = sectionPatch.items ?: emptyList()
                PersonaSection(
                    id = id,
                    title = title,
                    items = items
                )
            }
            sectionMap[id] = updated
        }
        val updatedTraits = patch.traits ?: traits
        return copy(
            title = updatedTitle,
            sections = sectionMap,
            traits = updatedTraits,
            lastUpdatedAt = System.currentTimeMillis()
        )
    }

    private fun defaultSectionTitle(id: String): String {
        val trimmed = id.trim()
        return if (trimmed.isEmpty()) "未命名领域" else trimmed
    }

    companion object {
        private const val CURRENT_VERSION = 1

        fun default(): PersonaProfile {
            return PersonaProfile(
                title = "### **正在构建的个人画像**",
                sections = LinkedHashMap(),
                traits = emptyList(),
                version = CURRENT_VERSION,
                lastUpdatedAt = System.currentTimeMillis()
            )
        }

        fun fromJsonString(raw: String?): PersonaProfile? {
            if (raw.isNullOrBlank()) return null
            return runCatching {
                fromJson(JSONObject(raw))
            }.getOrNull()
        }

        fun fromJson(json: JSONObject): PersonaProfile {
            val version = json.optInt("version", CURRENT_VERSION)
            val title = json.optString("title").ifBlank { "### **正在构建的个人画像**" }
            val sectionsArray = json.optJSONArray("sections") ?: JSONArray()
            val sectionMap = LinkedHashMap<String, PersonaSection>()
            for (i in 0 until sectionsArray.length()) {
                val obj = sectionsArray.optJSONObject(i) ?: continue
                val section = PersonaSection.fromJson(obj) ?: continue
                sectionMap[section.id] = section
            }
            val traitsArray = json.optJSONArray("traits") ?: JSONArray()
            val traits = mutableListOf<String>()
            for (i in 0 until traitsArray.length()) {
                val value = traitsArray.optString(i)
                if (value.isNotBlank()) traits += value.trim()
            }
            val updatedAt = json.optLong("lastUpdatedAt", System.currentTimeMillis())
            return PersonaProfile(
                title = title,
                sections = sectionMap,
                traits = traits,
                version = version,
                lastUpdatedAt = updatedAt
            )
        }

        fun fromLegacySummary(summary: String?): PersonaProfile {
            val base = default()
            val sanitized = summary?.trim().orEmpty()
            if (sanitized.isEmpty()) return base
            return base.copy(
                title = sanitized.lines().firstOrNull { it.startsWith("###") } ?: base.title,
                traits = emptyList()
            )
        }
    }
}

data class PersonaSection(
    val id: String,
    val title: String,
    val items: List<PersonaItem>
) {
    fun toJson(): JSONObject {
        val itemsArray = JSONArray()
        items.forEach { itemsArray.put(it.toJson()) }
        return JSONObject()
            .put("id", id)
            .put("title", title)
            .put("items", itemsArray)
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "title" to title,
            "items" to items.map { it.toMap() }
        )
    }

    companion object {
        fun fromJson(json: JSONObject): PersonaSection? {
            val rawId = json.optString("id")
            val id = rawId.trim()
            if (id.isEmpty()) return null
            val title = json.optString("title").takeIf { it.isNotBlank() } ?: id
            val itemsArray = json.optJSONArray("items") ?: JSONArray()
            val items = mutableListOf<PersonaItem>()
            for (i in 0 until itemsArray.length()) {
                val itemObj = itemsArray.optJSONObject(i) ?: continue
                val item = PersonaItem.fromJson(itemObj) ?: continue
                items += item
            }
            return PersonaSection(
                id = id,
                title = title,
                items = items
            )
        }
    }
}

data class PersonaItem(
    val slot: String,
    val heading: String,
    val detail: String
) {
    fun toJson(): JSONObject {
        return JSONObject()
            .put("slot", slot)
            .put("heading", heading)
            .put("detail", detail)
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "slot" to slot,
            "heading" to heading,
            "detail" to detail
        )
    }

    companion object {
        fun fromJson(json: JSONObject): PersonaItem? {
            val slot = json.optString("slot")
            if (slot.isNullOrBlank()) return null
            val heading = json.optString("heading").ifBlank { return null }
            val detail = json.optString("detail")
            return PersonaItem(
                slot = slot.trim(),
                heading = heading.trim(),
                detail = detail.trim()
            )
        }
    }
}

data class PersonaProfilePatch(
    val title: String? = null,
    val sections: LinkedHashMap<String, PersonaSectionPatch> = linkedMapOf(),
    val traits: List<String>? = null
) {
    companion object {
        fun fromJson(json: JSONObject?): PersonaProfilePatch? {
            if (json == null) return null
            val title = json.optString("title").takeIf { it.isNotBlank() }
            val sectionsArray = json.optJSONArray("sections") ?: JSONArray()
            val sectionMap = linkedMapOf<String, PersonaSectionPatch>()
            for (i in 0 until sectionsArray.length()) {
                val obj = sectionsArray.optJSONObject(i) ?: continue
                val id = obj.optString("id").trim()
                if (id.isEmpty()) continue
                val patch = PersonaSectionPatch.fromJson(obj)
                if (patch != null) {
                    sectionMap[id] = patch
                }
            }
            val traitsArray = json.optJSONArray("traits")
            val traits = traitsArray?.let { arr ->
                val list = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val value = arr.optString(i)
                    if (value.isNotBlank()) list += value.trim()
                }
                list
            }
            return PersonaProfilePatch(
                title = title,
                sections = sectionMap,
                traits = traits
            )
        }
    }
}

data class PersonaSectionPatch(
    val title: String? = null,
    val items: List<PersonaItem>? = null
) {
    companion object {
        fun fromJson(json: JSONObject): PersonaSectionPatch? {
            val title = json.optString("title").takeIf { it.isNotBlank() }
            val itemsArray = json.optJSONArray("items")
            val items = itemsArray?.let { arr ->
                val list = mutableListOf<PersonaItem>()
                for (i in 0 until arr.length()) {
                    val itemObj = arr.optJSONObject(i) ?: continue
                    val item = PersonaItem.fromJson(itemObj) ?: continue
                    list += item
                }
                list
            }
            return PersonaSectionPatch(
                title = title,
                items = items
            )
        }
    }
}


