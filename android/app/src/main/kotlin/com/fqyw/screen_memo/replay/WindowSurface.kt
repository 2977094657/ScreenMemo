package com.fqyw.screen_memo.replay

import android.opengl.EGLSurface
import android.view.Surface

class WindowSurface(
    private val eglCore: EglCore,
    surface: Surface,
) {
    private val eglSurface: EGLSurface = eglCore.createWindowSurface(surface)

    fun makeCurrent() {
        eglCore.makeCurrent(eglSurface)
    }

    fun swapBuffers(): Boolean {
        return eglCore.swapBuffers(eglSurface)
    }

    fun setPresentationTime(nsecs: Long) {
        eglCore.setPresentationTime(eglSurface, nsecs)
    }

    fun release() {
        eglCore.releaseSurface(eglSurface)
    }
}

