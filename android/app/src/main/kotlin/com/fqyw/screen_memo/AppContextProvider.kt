package com.fqyw.screen_memo

import android.annotation.SuppressLint
import android.content.Context

object AppContextProvider {
    @SuppressLint("StaticFieldLeak")
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun context(): Context? = appContext
}

