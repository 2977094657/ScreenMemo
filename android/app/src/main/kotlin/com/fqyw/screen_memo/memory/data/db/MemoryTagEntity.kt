package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.fqyw.screen_memo.memory.model.TagCategory
import com.fqyw.screen_memo.memory.model.TagStatus

@Entity(
    tableName = "memory_tags",
    indices = [
        Index(value = ["tag_key"], unique = true),
        Index(value = ["status"]),
        Index(value = ["category"])
    ]
)
data class MemoryTagEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "tag_key")
    val tagKey: String,
    @ColumnInfo(name = "label")
    val label: String,
    @ColumnInfo(name = "level1")
    val level1: String = "",
    @ColumnInfo(name = "level2")
    val level2: String = "",
    @ColumnInfo(name = "level3")
    val level3: String = "",
    @ColumnInfo(name = "level4")
    val level4: String = "",
    @ColumnInfo(name = "full_path")
    val fullPath: String = "",
    @ColumnInfo(name = "category")
    val category: TagCategory,
    @ColumnInfo(name = "status")
    val status: TagStatus = TagStatus.PENDING,
    @ColumnInfo(name = "occurrences")
    val occurrences: Int = 1,
    @ColumnInfo(name = "confidence")
    val confidence: Double = 0.5,
    @ColumnInfo(name = "first_seen_at")
    val firstSeenAt: Long,
    @ColumnInfo(name = "last_seen_at")
    val lastSeenAt: Long,
    @ColumnInfo(name = "auto_confirmed_at")
    val autoConfirmedAt: Long? = null,
    @ColumnInfo(name = "manual_confirmed_at")
    val manualConfirmedAt: Long? = null
)

