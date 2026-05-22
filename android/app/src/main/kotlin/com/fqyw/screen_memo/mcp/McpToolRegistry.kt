package com.fqyw.screen_memo.mcp

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class McpToolRegistry(
    context: Context,
    private val serviceStatusProvider: () -> Map<String, Any?>,
) {
    private val repository = ScreenMemoMcpRepository(context.applicationContext)

    fun listTools(): JSONArray {
        return JSONArray()
            .put(tool("screenmemo_status", "Return ScreenMemo MCP service and database status.", objectSchema()))
            .put(
                tool(
                    "list_recent_dynamics",
                    "List recent dynamic summaries. OCR and image data are excluded unless explicitly requested.",
                    objectSchema(
                        "limit" to intSchema("Maximum records to return. Default 20, max 100.", 1, 100),
                        "offset" to intSchema("Pagination offset. Default 0.", 0, null),
                        "include_ocr" to boolSchema("Include truncated OCR text. Default false."),
                    ),
                ),
            )
            .put(
                tool(
                    "search_dynamics",
                    "Search dynamic summaries, categories, and structured JSON.",
                    objectSchema(
                        "query" to stringSchema("Search query."),
                        "limit" to intSchema("Maximum records to return. Default 20, max 100.", 1, 100),
                        "offset" to intSchema("Pagination offset. Default 0.", 0, null),
                        "start_time" to intSchema("Optional start timestamp in milliseconds.", 0, null),
                        "end_time" to intSchema("Optional end timestamp in milliseconds.", 0, null),
                        "include_ocr" to boolSchema("Include truncated OCR text. Default false."),
                    ),
                    required = listOf("query"),
                ),
            )
            .put(
                tool(
                    "get_dynamic_context",
                    "Return AI-friendly dynamic context in a time window.",
                    objectSchema(
                        "start_time" to intSchema("Start timestamp in milliseconds.", 0, null),
                        "end_time" to intSchema("End timestamp in milliseconds.", 0, null),
                        "limit" to intSchema("Maximum records to return. Default 20, max 100.", 1, 100),
                        "include_ocr" to boolSchema("Include truncated OCR text. Default false."),
                    ),
                    required = listOf("start_time", "end_time"),
                ),
            )
            .put(
                tool(
                    "get_segment",
                    "Return one dynamic segment by segment_id.",
                    objectSchema(
                        "segment_id" to intSchema("Segment ID.", 1, null),
                        "include_ocr" to boolSchema("Include truncated OCR text. Default false."),
                        "include_images" to boolSchema("Include image reference metadata. Default false."),
                    ),
                    required = listOf("segment_id"),
                ),
            )
            .put(
                tool(
                    "search_docs",
                    "Search daily summaries, morning insights, weekly summaries, favorites, and notes in search_docs.",
                    objectSchema(
                        "query" to stringSchema("Search query."),
                        "doc_type" to stringSchema("Optional doc type filter."),
                        "limit" to intSchema("Maximum records to return. Default 20, max 100.", 1, 100),
                        "offset" to intSchema("Pagination offset. Default 0.", 0, null),
                        "start_time" to intSchema("Optional start timestamp in milliseconds.", 0, null),
                        "end_time" to intSchema("Optional end timestamp in milliseconds.", 0, null),
                    ),
                    required = listOf("query"),
                ),
            )
            .put(
                tool(
                    "search_screenshots",
                    "Search screenshot OCR and metadata. Returns references and truncated summaries by default.",
                    objectSchema(
                        "query" to stringSchema("Search query."),
                        "limit" to intSchema("Maximum records to return. Default 20, max 100.", 1, 100),
                        "offset" to intSchema("Pagination offset. Default 0.", 0, null),
                        "start_time" to intSchema("Optional start timestamp in milliseconds.", 0, null),
                        "end_time" to intSchema("Optional end timestamp in milliseconds.", 0, null),
                        "include_ocr" to boolSchema("Include truncated OCR text. Default false."),
                    ),
                    required = listOf("query"),
                ),
            )
            .put(
                tool(
                    "get_evidence_images",
                    "Return up to 5 evidence images by segment_id or image_refs. This is the only image-returning tool.",
                    objectSchema(
                        "segment_id" to intSchema("Optional segment ID.", 1, null),
                        "image_refs" to arraySchema("Optional screenshot reference IDs returned by other tools."),
                        "limit" to intSchema("Maximum images to return. Default 3, max 5.", 1, 5),
                    ),
                ),
            )
    }

    fun callTool(name: String, arguments: JSONObject): JSONObject {
        val result = try {
            when (name) {
                "screenmemo_status" -> repository.status(serviceStatusProvider())
                "list_recent_dynamics" -> repository.listRecentDynamics(arguments)
                "search_dynamics" -> repository.searchDynamics(arguments)
                "get_dynamic_context" -> repository.getDynamicContext(arguments)
                "get_segment" -> repository.getSegment(arguments)
                "search_docs" -> repository.searchDocs(arguments)
                "search_screenshots" -> repository.searchScreenshots(arguments)
                "get_evidence_images" -> return repository.getEvidenceImages(arguments)
                else -> return toolError("Unknown tool: $name")
            }
        } catch (e: IllegalArgumentException) {
            return toolError(e.message ?: "Invalid arguments")
        } catch (e: Exception) {
            return toolError("Tool failed: ${e.message ?: e.javaClass.simpleName}")
        }
        return toolResult(result)
    }

    private fun toolResult(data: JSONObject): JSONObject {
        return JSONObject()
            .put(
                "content",
                JSONArray().put(
                    JSONObject()
                        .put("type", "text")
                        .put("text", data.toString(2)),
                ),
            )
            .put("structuredContent", data)
            .put("isError", false)
    }

    private fun toolError(message: String): JSONObject {
        return JSONObject()
            .put(
                "content",
                JSONArray().put(
                    JSONObject()
                        .put("type", "text")
                        .put("text", message),
                ),
            )
            .put("isError", true)
    }

    private fun tool(
        name: String,
        description: String,
        inputSchema: JSONObject,
        required: List<String> = emptyList(),
    ): JSONObject {
        if (required.isNotEmpty()) {
            inputSchema.put("required", JSONArray(required))
        }
        return JSONObject()
            .put("name", name)
            .put("description", description)
            .put("inputSchema", inputSchema)
    }

    private fun objectSchema(
        vararg properties: Pair<String, JSONObject>,
    ): JSONObject {
        val props = JSONObject()
        for ((key, schema) in properties) {
            props.put(key, schema)
        }
        return JSONObject()
            .put("type", "object")
            .put("properties", props)
            .put("additionalProperties", false)
    }

    private fun stringSchema(description: String): JSONObject {
        return JSONObject()
            .put("type", "string")
            .put("description", description)
    }

    private fun boolSchema(description: String): JSONObject {
        return JSONObject()
            .put("type", "boolean")
            .put("description", description)
            .put("default", false)
    }

    private fun intSchema(description: String, minimum: Int?, maximum: Int?): JSONObject {
        val obj = JSONObject()
            .put("type", "integer")
            .put("description", description)
        if (minimum != null) obj.put("minimum", minimum)
        if (maximum != null) obj.put("maximum", maximum)
        return obj
    }

    private fun arraySchema(description: String): JSONObject {
        return JSONObject()
            .put("type", "array")
            .put("description", description)
            .put("items", stringSchema("Screenshot reference ID."))
    }
}
