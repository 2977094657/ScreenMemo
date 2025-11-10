package com.fqyw.screen_memo.memory.data.db

import androidx.room.Embedded
import androidx.room.Relation

data class EventWithTagIds(
    @Embedded
    val event: MemoryEventEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "event_id",
        entity = MemoryTagEvidenceEntity::class,
        projection = ["tag_id"]
    )
    val relatedTagIds: List<Long>
)

