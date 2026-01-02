package com.fqyw.screen_memo

import android.content.Context
import com.chuckerteam.chucker.api.ChuckerInterceptor
import okhttp3.Interceptor
import okhttp3.OkHttpClient

/**
 * 统一 OkHttpClient.Builder 构造入口：
 * - Debug：自动注入 ChuckerInterceptor，便于应用内抓包/导出。
 * - Release：依赖 library-no-op，保持 API 存在但不产生开销。
 */
object OkHttpClientFactory {

    @Volatile private var cachedChucker: Interceptor? = null

    fun newBuilder(context: Context? = AppContextProvider.context()): OkHttpClient.Builder {
        val builder = OkHttpClient.Builder()
        try {
            val appCtx = context?.applicationContext
            if (appCtx != null) {
                builder.addInterceptor(getOrCreateChucker(appCtx))
            }
        } catch (_: Throwable) {}
        return builder
    }

    private fun getOrCreateChucker(context: Context): Interceptor {
        val existing = cachedChucker
        if (existing != null) return existing
        synchronized(this) {
            val again = cachedChucker
            if (again != null) return again
            val created: Interceptor = ChuckerInterceptor.Builder(context).build()
            cachedChucker = created
            return created
        }
    }
}

