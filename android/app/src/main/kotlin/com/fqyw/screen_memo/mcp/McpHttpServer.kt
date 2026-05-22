package com.fqyw.screen_memo.mcp

import android.content.Context
import com.fqyw.screen_memo.logging.FileLogger
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URI
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class McpHttpServer(
    private val context: Context,
    private val port: Int,
    private val tokenProvider: () -> String,
) {
    companion object {
        private const val TAG = "McpHttpServer"
        private const val ENDPOINT = "/mcp"
        private const val MAX_HEADER_BYTES = 64 * 1024
        private const val MAX_BODY_BYTES = 2 * 1024 * 1024
        private const val PROTOCOL_VERSION = "2025-06-18"
    }

    private val running = AtomicBoolean(false)
    private val acceptExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val clientExecutor: ExecutorService = Executors.newCachedThreadPool()
    private val registry = McpToolRegistry(context) { McpServerService.statusForTool(context) }

    @Volatile
    private var serverSocket: ServerSocket? = null

    fun isRunning(): Boolean = running.get()

    @Synchronized
    @Throws(IOException::class)
    fun start() {
        if (running.get()) return
        val socket = ServerSocket()
        socket.reuseAddress = true
        socket.bind(InetSocketAddress("0.0.0.0", port))
        serverSocket = socket
        running.set(true)
        acceptExecutor.execute { acceptLoop(socket) }
        FileLogger.i(TAG, "MCP HTTP server started on 0.0.0.0:$port")
    }

    @Synchronized
    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        clientExecutor.shutdownNow()
        acceptExecutor.shutdownNow()
        FileLogger.i(TAG, "MCP HTTP server stopped")
    }

    private fun acceptLoop(socket: ServerSocket) {
        while (running.get()) {
            try {
                val client = socket.accept()
                client.soTimeout = 15_000
                clientExecutor.execute { handleClient(client) }
            } catch (e: IOException) {
                if (running.get()) {
                    FileLogger.w(TAG, "MCP accept failed: ${e.message}")
                }
            } catch (e: Exception) {
                if (running.get()) {
                    FileLogger.w(TAG, "MCP accept error: ${e.message}")
                }
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            try {
                val request = readRequest(client)
                val response = handleRequest(request)
                writeResponse(client, response)
            } catch (e: HttpException) {
                writeResponse(client, textResponse(e.status, e.messageText))
            } catch (e: Exception) {
                FileLogger.w(TAG, "MCP request failed: ${e.message}")
                writeResponse(client, jsonResponse(500, jsonRpcError(null, -32603, "Internal error")))
            }
        }
    }

    private fun handleRequest(request: HttpRequest): HttpResponse {
        val path = request.path.substringBefore('?')
        if (path != ENDPOINT) {
            return textResponse(404, "Not Found")
        }

        val origin = request.headers["origin"].orEmpty()
        if (!isAllowedOrigin(origin)) {
            return textResponse(403, "Forbidden")
        }

        if (request.method == "OPTIONS") {
            return HttpResponse(
                status = 204,
                contentType = "text/plain; charset=utf-8",
                body = ByteArray(0),
                headers = mapOf(
                    "Allow" to "POST, GET, OPTIONS",
                    "Access-Control-Allow-Methods" to "POST, GET, OPTIONS",
                    "Access-Control-Allow-Headers" to "Authorization, Content-Type",
                ),
            )
        }

        if (!isAuthorized(request.headers["authorization"])) {
            return HttpResponse(
                status = 401,
                contentType = "text/plain; charset=utf-8",
                body = "Unauthorized".toByteArray(StandardCharsets.UTF_8),
                headers = mapOf("WWW-Authenticate" to "Bearer"),
            )
        }

        if (request.method == "GET") {
            return textResponse(405, "Method Not Allowed", mapOf("Allow" to "POST"))
        }
        if (request.method != "POST") {
            return textResponse(405, "Method Not Allowed", mapOf("Allow" to "POST"))
        }
        if (request.body.isEmpty()) {
            return jsonResponse(400, jsonRpcError(null, -32700, "Empty JSON-RPC body"))
        }

        return handleJsonRpcBody(request.body)
    }

    private fun handleJsonRpcBody(body: ByteArray): HttpResponse {
        val raw = body.toString(StandardCharsets.UTF_8)
        val parsed = try {
            JSONTokener(raw).nextValue()
        } catch (_: Exception) {
            return jsonResponse(400, jsonRpcError(null, -32700, "Parse error"))
        }

        if (parsed is JSONArray) {
            val responses = JSONArray()
            for (i in 0 until parsed.length()) {
                val obj = parsed.optJSONObject(i)
                val response = if (obj == null) {
                    jsonRpcError(null, -32600, "Invalid Request")
                } else {
                    handleJsonRpcObject(obj)
                }
                if (response != null) responses.put(response)
            }
            return if (responses.length() == 0) {
                HttpResponse(202, "text/plain; charset=utf-8", ByteArray(0))
            } else {
                jsonResponse(200, responses)
            }
        }

        if (parsed !is JSONObject) {
            return jsonResponse(400, jsonRpcError(null, -32600, "Invalid Request"))
        }
        val response = handleJsonRpcObject(parsed)
        return if (response == null) {
            HttpResponse(202, "text/plain; charset=utf-8", ByteArray(0))
        } else {
            jsonResponse(200, response)
        }
    }

    private fun handleJsonRpcObject(request: JSONObject): JSONObject? {
        val id = if (request.has("id")) request.opt("id") else null
        val isNotification = !request.has("id")
        val method = request.optString("method", "").trim()
        if (request.optString("jsonrpc") != "2.0" || method.isEmpty()) {
            return jsonRpcError(id, -32600, "Invalid Request")
        }

        if (isNotification && method == "notifications/initialized") {
            return null
        }

        return try {
            val result = when (method) {
                "initialize" -> initializeResult(request.optJSONObject("params"))
                "ping" -> JSONObject()
                "tools/list" -> JSONObject().put("tools", registry.listTools())
                "tools/call" -> {
                    val params = request.optJSONObject("params")
                        ?: throw IllegalArgumentException("params is required")
                    val name = params.optString("name", "").trim()
                    val arguments = params.optJSONObject("arguments") ?: JSONObject()
                    if (name.isEmpty()) throw IllegalArgumentException("tool name is required")
                    registry.callTool(name, arguments)
                }
                else -> return jsonRpcError(id, -32601, "Method not found")
            }
            jsonRpcResult(id, result)
        } catch (e: IllegalArgumentException) {
            jsonRpcError(id, -32602, e.message ?: "Invalid params")
        } catch (e: Exception) {
            FileLogger.w(TAG, "MCP method $method failed: ${e.message}")
            jsonRpcError(id, -32603, "Internal error")
        }
    }

    private fun initializeResult(params: JSONObject?): JSONObject {
        val requestedVersion = params?.optString("protocolVersion", "").orEmpty()
        val protocolVersion = if (requestedVersion.isNotBlank()) requestedVersion else PROTOCOL_VERSION
        return JSONObject()
            .put("protocolVersion", protocolVersion)
            .put(
                "capabilities",
                JSONObject().put("tools", JSONObject().put("listChanged", false)),
            )
            .put(
                "serverInfo",
                JSONObject()
                    .put("name", "screenmemo-lan-mcp")
                    .put("version", "1.0.0"),
            )
            .put(
                "instructions",
                "Read-only ScreenMemo LAN MCP server. OCR text and images are returned only when explicitly requested by tool arguments.",
            )
    }

    private fun readRequest(socket: Socket): HttpRequest {
        val input = BufferedInputStream(socket.getInputStream())
        val headerBytes = ByteArrayOutputStream()
        var prev3 = -1
        var prev2 = -1
        var prev1 = -1
        while (true) {
            val b = input.read()
            if (b < 0) throw HttpException(400, "Bad Request")
            headerBytes.write(b)
            if (headerBytes.size() > MAX_HEADER_BYTES) {
                throw HttpException(431, "Request Header Fields Too Large")
            }
            if (prev3 == '\r'.code && prev2 == '\n'.code && prev1 == '\r'.code && b == '\n'.code) {
                break
            }
            prev3 = prev2
            prev2 = prev1
            prev1 = b
        }

        val headerText = headerBytes.toByteArray().toString(Charset.forName("ISO-8859-1"))
        val lines = headerText.split("\r\n").filter { it.isNotEmpty() }
        if (lines.isEmpty()) throw HttpException(400, "Bad Request")
        val requestLine = lines.first().split(" ")
        if (requestLine.size < 2) throw HttpException(400, "Bad Request")
        val method = requestLine[0].uppercase(Locale.US)
        val path = requestLine[1]
        val headers = LinkedHashMap<String, String>()
        for (i in 1 until lines.size) {
            val line = lines[i]
            val sep = line.indexOf(':')
            if (sep <= 0) continue
            headers[line.substring(0, sep).trim().lowercase(Locale.US)] =
                line.substring(sep + 1).trim()
        }
        val contentLength = headers["content-length"]?.toIntOrNull() ?: 0
        if (contentLength < 0 || contentLength > MAX_BODY_BYTES) {
            throw HttpException(413, "Payload Too Large")
        }
        val body = ByteArray(contentLength)
        var read = 0
        while (read < contentLength) {
            val n = input.read(body, read, contentLength - read)
            if (n < 0) throw HttpException(400, "Incomplete request body")
            read += n
        }
        return HttpRequest(method, path, headers, body)
    }

    private fun writeResponse(socket: Socket, response: HttpResponse) {
        val output = socket.getOutputStream()
        val statusLine = "HTTP/1.1 ${response.status} ${reasonPhrase(response.status)}\r\n"
        output.write(statusLine.toByteArray(StandardCharsets.US_ASCII))
        val headers = LinkedHashMap<String, String>()
        headers["Content-Type"] = response.contentType
        headers["Content-Length"] = response.body.size.toString()
        headers["Connection"] = "close"
        headers["Cache-Control"] = "no-store"
        headers.putAll(response.headers)
        for ((key, value) in headers) {
            output.write("$key: $value\r\n".toByteArray(StandardCharsets.US_ASCII))
        }
        output.write("\r\n".toByteArray(StandardCharsets.US_ASCII))
        if (response.body.isNotEmpty()) {
            output.write(response.body)
        }
        output.flush()
    }

    private fun isAuthorized(header: String?): Boolean {
        val expected = tokenProvider().trim()
        if (expected.isEmpty()) return false
        val raw = header?.trim().orEmpty()
        if (!raw.startsWith("Bearer ", ignoreCase = true)) return false
        return raw.substringAfter(' ').trim() == expected
    }

    private fun isAllowedOrigin(origin: String): Boolean {
        if (origin.isBlank() || origin == "null") return true
        val host = try {
            URI(origin).host?.trim().orEmpty()
        } catch (_: Exception) {
            return false
        }
        if (host.isBlank()) return false
        val normalized = host.lowercase(Locale.US)
        if (normalized == "localhost") return true
        if (isPrivateIpv4(normalized)) return true
        if (normalized.contains(":")) {
            return try {
                val address = InetAddress.getByName(normalized)
                address.isLoopbackAddress || address.isLinkLocalAddress || address.isSiteLocalAddress
            } catch (_: Exception) {
                false
            }
        }
        return false
    }

    private fun isPrivateIpv4(host: String): Boolean {
        val parts = host.split('.')
        if (parts.size != 4) return false
        val nums = parts.map { it.toIntOrNull() ?: return false }
        if (nums.any { it !in 0..255 }) return false
        return nums[0] == 10 ||
            nums[0] == 127 ||
            nums[0] == 169 && nums[1] == 254 ||
            nums[0] == 192 && nums[1] == 168 ||
            nums[0] == 172 && nums[1] in 16..31
    }

    private fun jsonRpcResult(id: Any?, result: JSONObject): JSONObject {
        return JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", id ?: JSONObject.NULL)
            .put("result", result)
    }

    private fun jsonRpcError(id: Any?, code: Int, message: String): JSONObject {
        return JSONObject()
            .put("jsonrpc", "2.0")
            .put("id", id ?: JSONObject.NULL)
            .put(
                "error",
                JSONObject()
                    .put("code", code)
                    .put("message", message),
            )
    }

    private fun jsonResponse(status: Int, value: Any): HttpResponse {
        val body = when (value) {
            is JSONObject -> value.toString()
            is JSONArray -> value.toString()
            else -> JSONObject().put("value", value).toString()
        }.toByteArray(StandardCharsets.UTF_8)
        return HttpResponse(status, "application/json; charset=utf-8", body)
    }

    private fun textResponse(
        status: Int,
        text: String,
        headers: Map<String, String> = emptyMap(),
    ): HttpResponse {
        return HttpResponse(
            status = status,
            contentType = "text/plain; charset=utf-8",
            body = text.toByteArray(StandardCharsets.UTF_8),
            headers = headers,
        )
    }

    private fun reasonPhrase(status: Int): String {
        return when (status) {
            200 -> "OK"
            202 -> "Accepted"
            204 -> "No Content"
            400 -> "Bad Request"
            401 -> "Unauthorized"
            403 -> "Forbidden"
            404 -> "Not Found"
            405 -> "Method Not Allowed"
            413 -> "Payload Too Large"
            431 -> "Request Header Fields Too Large"
            else -> "Internal Server Error"
        }
    }

    private data class HttpRequest(
        val method: String,
        val path: String,
        val headers: Map<String, String>,
        val body: ByteArray,
    )

    private data class HttpResponse(
        val status: Int,
        val contentType: String,
        val body: ByteArray,
        val headers: Map<String, String> = emptyMap(),
    )

    private class HttpException(
        val status: Int,
        val messageText: String,
    ) : Exception(messageText)
}
