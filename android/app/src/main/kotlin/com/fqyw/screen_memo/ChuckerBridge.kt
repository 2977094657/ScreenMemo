package com.fqyw.screen_memo

import android.content.Context
import android.content.Intent
import com.chuckerteam.chucker.api.Chucker

object ChuckerBridge {
    fun open(context: Context): Boolean {
        return try {
            val intent = Chucker.getLaunchIntent(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}

