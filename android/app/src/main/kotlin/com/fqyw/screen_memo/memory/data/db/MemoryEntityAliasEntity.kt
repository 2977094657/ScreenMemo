package com.fqyw.screen_memo.memory.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "memory_entity_aliases",
    primaryKeys = ["alias_key"],
    foreignKeys = [
        ForeignKey(
            entity = MemoryEntityEntity::class,
            parentColumns = ["id"],
            childColumns = ["entity_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["entity_id"], name = "idx_memory_entity_aliases_entity")
    ]
)
data class MemoryEntityAliasEntity(
    @ColumnInfo(name = "alias_key")
    val aliasKey: String,
    @ColumnInfo(name = "entity_id")
    val entityId: Long,
    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)

