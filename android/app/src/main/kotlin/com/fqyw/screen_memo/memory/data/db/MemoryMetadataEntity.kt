package com.fqyw.screen_memo.memory.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "memory_metadata")
data class MemoryMetadataEntity(
    @PrimaryKey val key: String,
    val value: String
)


