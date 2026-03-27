package com.fqyw.screen_memo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SegmentSummaryManagerOpenAiCompatParsingTest {
    private fun extractOpenAi(body: String): String {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "extractTextFromOpenAiCompatibleBody",
            String::class.java,
        )
        method.isAccessible = true
        return method.invoke(SegmentSummaryManager, body) as String
    }

    private fun guessMime(path: String): String {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "guessMime",
            String::class.java,
        )
        method.isAccessible = true
        return method.invoke(SegmentSummaryManager, path) as String
    }

    private fun buildAiPayloadFailureMessage(
        providerLabel: String,
        body: String,
    ): String {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "buildAiPayloadFailureMessage",
            String::class.java,
            String::class.java,
        )
        method.isAccessible = true
        return method.invoke(SegmentSummaryManager, providerLabel, body) as String
    }

    @Suppress("UNCHECKED_CAST")
    private fun normalizeAndDedupTextOnlyDescriptions(
        descriptions: List<String>,
    ): List<String> {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "normalizeAndDedupTextOnlyDescriptionsForMergePrompt",
            List::class.java,
        )
        method.isAccessible = true
        return method.invoke(SegmentSummaryManager, descriptions) as List<String>
    }

    @Suppress("UNCHECKED_CAST")
    private fun limitTextOnlyDescriptions(
        descriptions: List<String>,
        maxEntries: Int,
        maxChars: Int,
    ): List<String> {
        val method = SegmentSummaryManager::class.java.getDeclaredMethod(
            "limitTextOnlyDescriptionsForMergePrompt",
            List::class.java,
            Int::class.javaPrimitiveType,
            Int::class.javaPrimitiveType,
        )
        method.isAccessible = true
        return method.invoke(
            SegmentSummaryManager,
            descriptions,
            maxEntries,
            maxChars,
        ) as List<String>
    }

    @Test
    fun extractOpenAi_shouldParseSseBodyWithDataPrefixes() {
        val body = """
            data: {"choices":[{"delta":{"content":[{"type":"text","text":"hello "} ]}}]}

            data: {"choices":[{"delta":{"content":[{"type":"text","text":"world"}]}}]}

            data: [DONE]
        """.trimIndent()

        assertEquals("hello world", extractOpenAi(body))
    }

    @Test
    fun extractOpenAi_shouldParsePrettyPrintedJsonChunksWithoutDataPrefixes() {
        val body = """
            {
              "choices": [
                {
                  "delta": {
                    "content": [
                      {"type":"text","text":"hello "}
                    ]
                  }
                }
              ]
            }
            {
              "choices": [
                {
                  "delta": {
                    "content": [
                      {"type":"text","text":"world"}
                    ]
                  }
                }
              ]
            }
        """.trimIndent()

        assertEquals("hello world", extractOpenAi(body))
    }

    @Test
    fun extractOpenAi_shouldSkipEmptyAssistantRoleChunkAndKeepLaterDelta() {
        val body = """
            {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant","content":""},"finish_reason":null}]}
            {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"content":"hello "},"finish_reason":null}]}
            {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{"content":"world"},"finish_reason":null}]}
            {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"delta":{},"finish_reason":"stop"}]}
        """.trimIndent()

        assertEquals("hello world", extractOpenAi(body))
    }

    @Test
    fun guessMime_shouldRecognizeWebpImages() {
        assertEquals("image/webp", guessMime("/tmp/demo.webp"))
    }

    @Test
    fun buildAiPayloadFailureMessage_shouldExplainEmptyChoicesResponses() {
        val body = """
            data: {"choices":[{"delta":{"role":"assistant","content":""}}]}
            data: {"choices":[],"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}}
            data: [DONE]

            --- fallback: non-stream chat.completions ---
            {"choices":[],"usage":{"prompt_tokens":11572,"completion_tokens":0,"total_tokens":11572}}
        """.trimIndent()

        val message = buildAiPayloadFailureMessage("OpenAI兼容", body)

        assertTrue(message.contains("空 choices"))
        assertTrue(message.contains("completion_tokens=0"))
    }

    @Test
    fun mergePromptTextOnlyDescriptions_shouldDedupAndRespectBudgets() {
        val normalized = normalizeAndDedupTextOnlyDescriptions(
            listOf(
                "  第一段  描述  ",
                "第一段 描述",
                "",
                "第二段描述\n\n\n带换行",
                "第三段描述",
            ),
        )
        assertEquals(
            listOf("第一段 描述", "第二段描述\n\n带换行", "第三段描述"),
            normalized,
        )

        val limited = limitTextOnlyDescriptions(
            normalized,
            maxEntries = 2,
            maxChars = 16,
        )
        assertEquals(listOf("第一段 描述"), limited)
    }
}
