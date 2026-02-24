package com.fqyw.screen_memo

import android.content.Context
import okhttp3.OkHttpClient

/**
 * 统一 OkHttpClient.Builder 构造入口：
 */
object OkHttpClientFactory {

    fun newBuilder(context: Context? = AppContextProvider.context()): OkHttpClient.Builder {
        return OkHttpClient.Builder()
    }
}

