package com.fqyw.screen_memo.memory.service

data class ExtractionContext(
    val providerId: Int?,
    val providerName: String?,
    val providerType: String?,
    val baseUrl: String?,
    val chatPath: String?,
    val useResponseApi: Boolean,
    val apiKey: String?,
    val model: String?,
    val extra: Map<String, Any?> = emptyMap()
) {
    val isValid: Boolean
        get() = !apiKey.isNullOrBlank() && !model.isNullOrBlank() && !baseUrl.isNullOrBlank()

    fun toLogSafeString(): String {
        return buildString {
            append("providerId=").append(providerId ?: "null")
            append(", providerType=").append(providerType ?: "null")
            append(", model=").append(model ?: "null")
            append(", baseUrl=").append(baseUrl?.take(64) ?: "null")
            append(", useResponseApi=").append(useResponseApi)
        }
    }

    companion object {
        fun fromMap(map: Map<*, *>?): ExtractionContext? {
            if (map == null) return null
            val extraMap = (map["extra"] as? Map<*, *>)?.entries
                ?.associate { (k, v) -> k?.toString().orEmpty() to v }
                ?.filterKeys { it.isNotEmpty() }
                ?: emptyMap()
            return ExtractionContext(
                providerId = (map["providerId"] as? Number)?.toInt(),
                providerName = map["providerName"] as? String,
                providerType = map["providerType"] as? String,
                baseUrl = map["baseUrl"] as? String,
                chatPath = map["chatPath"] as? String,
                useResponseApi = (map["useResponseApi"] as? Boolean) ?: false,
                apiKey = map["apiKey"] as? String,
                model = map["model"] as? String,
                extra = extraMap
            )
        }
    }
}

