package com.fqyw.screen_memo.memory.data.db

import androidx.room.Embedded
import androidx.room.Relation

data class TagWithEvidence(
    @Embedded
    val tag: MemoryTagEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "tag_id"
    )
    val evidences: List<MemoryTagEvidenceEntity>
)

