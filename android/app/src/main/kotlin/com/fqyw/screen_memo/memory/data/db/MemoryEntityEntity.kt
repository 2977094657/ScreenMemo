package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "memory_entities",
    indices = [
        Index(value = ["entity_key"], unique = true, name = "idx_memory_entities_key"),
        Index(value = ["type"], name = "idx_memory_entities_type"),
        Index(value = ["name"], name = "idx_memory_entities_name")
    ]
)
data class MemoryEntityEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "entity_key")
    val entityKey: String,
    @ColumnInfo(name = "type")
    val type: String,
    @ColumnInfo(name = "name")
    val name: String,
    @ColumnInfo(name = "aliases")
    val aliases: List<String>? = emptyList(),
    @ColumnInfo(name = "metadata")
    val metadata: Map<String, String>? = emptyMap(),
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "last_modified_at")
    val lastModifiedAt: Long = System.currentTimeMillis()
)
