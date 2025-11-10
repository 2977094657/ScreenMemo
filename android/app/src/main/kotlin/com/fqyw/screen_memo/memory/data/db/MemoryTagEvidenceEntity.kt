package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "memory_tag_evidence",
    foreignKeys = [
        ForeignKey(
            entity = MemoryTagEntity::class,
            parentColumns = ["id"],
            childColumns = ["tag_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = MemoryEventEntity::class,
            parentColumns = ["id"],
            childColumns = ["event_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["tag_id"]),
        Index(value = ["event_id"]),
        Index(value = ["tag_id", "event_id"], unique = true)
    ]
)
data class MemoryTagEvidenceEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "tag_id")
    val tagId: Long,
    @ColumnInfo(name = "event_id")
    val eventId: Long,
    @ColumnInfo(name = "excerpt")
    val excerpt: String,
    @ColumnInfo(name = "confidence")
    val confidence: Double = 0.5,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "last_modified_at")
    val lastModifiedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "is_user_edited")
    val isUserEdited: Boolean = false,
    @ColumnInfo(name = "notes")
    val notes: String? = null
)

