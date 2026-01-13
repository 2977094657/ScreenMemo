package com.fqyw.screen_memo.memory.data.db

import androidx.room.TypeConverter
import org.json.JSONArray
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
    fun fromStringList(list: List<String>?): String? {
        if (list.isNullOrEmpty()) return null
        val arr = JSONArray()
        list.forEach { item ->
            val v = item.trim()
            if (v.isNotEmpty()) arr.put(v)
        }
        return arr.toString()
    }

    @TypeConverter
    fun toStringList(json: String?): List<String> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            val out = mutableListOf<String>()
            for (i in 0 until arr.length()) {
                val v = arr.optString(i).trim()
                if (v.isNotEmpty()) out += v
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }
}
