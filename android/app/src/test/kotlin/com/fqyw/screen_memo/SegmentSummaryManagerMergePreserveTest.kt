package com.fqyw.screen_memo

import org.junit.Assert.assertEquals
import org.junit.Test

class SegmentSummaryManagerMergePreserveTest {
    @Test
    fun mergeImageDescriptions_shouldNotClobberWhenMergedStructuredJsonInvalid() {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "mergeImageDescriptionsIntoStructuredJson",
            String::class.java,
            List::class.java,
            List::class.java,
            String::class.java,
            List::class.java,
            String::class.java,
            List::class.java,
        )
        method.isAccessible = true

        val invalidStructured = "{invalid json"
        val sample = SegmentDatabaseHelper.Sample(
            id = 0L,
            segmentId = 1L,
            captureTime = 1L,
            filePath = "/tmp/a.png",
            appPackageName = "pkg",
            appName = "App",
            positionIndex = 0,
        )

        val result = method.invoke(
            SegmentSummaryManager,
            invalidStructured,
            listOf(sample),
            listOf(sample),
            null,
            emptyList<SegmentDatabaseHelper.Sample>(),
            null,
            emptyList<SegmentDatabaseHelper.Sample>(),
        ) as String?

        assertEquals(invalidStructured, result)
    }
}

