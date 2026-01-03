package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "memory_edges",
    foreignKeys = [
        ForeignKey(
            entity = MemoryEntityEntity::class,
            parentColumns = ["id"],
            childColumns = ["subject_entity_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = MemoryEntityEntity::class,
            parentColumns = ["id"],
            childColumns = ["object_entity_id"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index(value = ["subject_entity_id"], name = "idx_memory_edges_subject"),
        Index(value = ["object_entity_id"], name = "idx_memory_edges_object"),
        Index(value = ["predicate"], name = "idx_memory_edges_predicate"),
        Index(value = ["valid_from"], name = "idx_memory_edges_valid_from"),
        Index(value = ["valid_to"], name = "idx_memory_edges_valid_to")
    ]
)
data class MemoryEdgeEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Long = 0L,
    @ColumnInfo(name = "subject_entity_id")
    val subjectEntityId: Long,
    @ColumnInfo(name = "predicate")
    val predicate: String,
    @ColumnInfo(name = "object_entity_id")
    val objectEntityId: Long? = null,
    @ColumnInfo(name = "object_value")
    val objectValue: String? = null,
    @ColumnInfo(name = "qualifiers")
    val qualifiers: Map<String, String>? = emptyMap(),
    @ColumnInfo(name = "valid_from")
    val validFrom: Long,
    @ColumnInfo(name = "valid_to")
    val validTo: Long? = null,
    @ColumnInfo(name = "confidence")
    val confidence: Double = 0.6,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "last_modified_at")
    val lastModifiedAt: Long = System.currentTimeMillis()
)
