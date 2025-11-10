package com.fqyw.screen_memo.memory.data.db

import androidx.room.TypeConverter
import com.fqyw.screen_memo.memory.model.TagCategory
import com.fqyw.screen_memo.memory.model.TagStatus
import org.json.JSONObject

class MemoryTypeConverters {

    @TypeConverter
    fun fromMetadataMap(map: Map<String, String>?): String? {
        if (map.isNullOrEmpty()) return null
        return JSONObject(map).toString()
    }

    @TypeConverter
    fun toMetadataMap(json: String?): Map<String, String> {
        if (json.isNullOrBlank()) return emptyMap()
        return try {
            val obj = JSONObject(json)
            val result = mutableMapOf<String, String>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = obj.optString(key, "")
                result[key] = value
            }
            result
        } catch (_: Exception) {
            emptyMap()
        }
    }

    @TypeConverter
    fun fromTagStatus(status: TagStatus?): String? = status?.storageValue

    @TypeConverter
    fun toTagStatus(value: String?): TagStatus = TagStatus.fromStorageValue(value)

    @TypeConverter
    fun fromTagCategory(category: TagCategory?): String? = category?.storageValue

    @TypeConverter
    fun toTagCategory(value: String?): TagCategory = TagCategory.fromStorageValue(value)
}

