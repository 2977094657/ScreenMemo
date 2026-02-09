package com.fqyw.screen_memo

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SegmentSummaryManagerNormalizeImageRefsTest {
    private fun normalize(rawJson: String, samples: List<SegmentDatabaseHelper.Sample>): String {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "normalizeImageRefsToFilenames",
            String::class.java,
            List::class.java,
        )
        method.isAccessible = true
        return method.invoke(SegmentSummaryManager, rawJson, samples) as String
    }

    private fun sample(path: String, t: Long): SegmentDatabaseHelper.Sample {
        return SegmentDatabaseHelper.Sample(
            id = 0L,
            segmentId = 1L,
            captureTime = t,
            filePath = path,
            appPackageName = "pkg",
            appName = "App",
            positionIndex = 0,
        )
    }

    @Test
    fun normalizeImageRefs_shouldConvertIndexStringsToFilenames() {
        val samples = listOf(
            sample("/tmp/a.png", 1000L),
            sample("/tmp/b.png", 2000L),
            sample("/tmp/c.png", 3000L),
        )

        val raw = """
            {
              "image_tags": [{"file": "2", "tags": ["x"]}],
              "image_descriptions": [{"from_file": "1", "to_file": "#3", "description": "desc"}],
              "described_images": [{"file": "1", "summary": "s"}],
              "key_actions": [{"ref_image": "3", "detail": "d"}],
              "content_groups": [{"representative_images": ["1", "#2"]}]
            }
        """.trimIndent()

        val out = JSONObject(normalize(raw, samples))
        assertEquals("b.png", out.getJSONArray("image_tags").getJSONObject(0).getString("file"))

        val desc = out.getJSONArray("image_descriptions").getJSONObject(0)
        assertEquals("a.png", desc.getString("from_file"))
        assertEquals("c.png", desc.getString("to_file"))

        assertEquals("a.png", out.getJSONArray("described_images").getJSONObject(0).getString("file"))
        assertEquals("c.png", out.getJSONArray("key_actions").getJSONObject(0).getString("ref_image"))

        val reps = out.getJSONArray("content_groups").getJSONObject(0).getJSONArray("representative_images")
        assertEquals("a.png", reps.getString(0))
        assertEquals("b.png", reps.getString(1))
    }

    @Test
    fun normalizeImageRefs_shouldDropInvalidNumericRefsAndKeepStructureWithoutNumbers() {
        val samples = listOf(
            sample("/tmp/a.png", 1000L),
            sample("/tmp/b.png", 2000L),
        )

        val raw = """
            {
              "image_tags": [{"file": "9", "tags": ["x"]}, {"file": "1", "tags": ["y"]}],
              "image_descriptions": [
                {"from_file": "9", "to_file": "10", "description": "bad"},
                {"from_file": "1", "to_file": "2", "description": "ok"}
              ],
              "described_images": [{"file": "#9", "summary": "s"}],
              "key_actions": [{"ref_image": "#8", "detail": "d"}],
              "content_groups": [{"representative_images": ["9", "2"]}]
            }
        """.trimIndent()

        val outText = normalize(raw, samples)
        val out = JSONObject(outText)

        val tags = out.getJSONArray("image_tags")
        assertEquals(1, tags.length())
        assertEquals("a.png", tags.getJSONObject(0).getString("file"))

        val descArr = out.getJSONArray("image_descriptions")
        assertEquals(1, descArr.length())
        assertEquals("a.png", descArr.getJSONObject(0).getString("from_file"))
        assertEquals("b.png", descArr.getJSONObject(0).getString("to_file"))

        val described = out.getJSONArray("described_images")
        assertEquals(0, described.length())

        val keyActions = out.getJSONArray("key_actions")
        assertFalse(keyActions.getJSONObject(0).has("ref_image"))

        val reps = out.getJSONArray("content_groups").getJSONObject(0).getJSONArray("representative_images")
        assertEquals(1, reps.length())
        assertEquals("b.png", reps.getString(0))

        assertFalse(outText.contains("\"9\""))
        assertTrue(outText.contains("a.png"))
        assertTrue(outText.contains("b.png"))
    }
}

