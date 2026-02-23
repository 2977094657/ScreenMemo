package com.fqyw.screen_memo.replay

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.view.Surface

class EglCore(sharedContext: EGLContext? = null) {
    val eglDisplay: EGLDisplay
    val eglContext: EGLContext
    private val eglConfig: EGLConfig

    init {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
            throw RuntimeException("EGL14: unable to get display")
        }

        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw RuntimeException("EGL14: unable to initialize")
        }

        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_NONE
        )

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(
                eglDisplay,
                attribList,
                0,
                configs,
                0,
                configs.size,
                numConfigs,
                0
            )
        ) {
            throw RuntimeException("EGL14: unable to find a suitable EGLConfig")
        }
        val cfg = configs[0] ?: throw RuntimeException("EGL14: no EGLConfig")
        eglConfig = cfg

        val contextAttribs = intArrayOf(
            EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL14.EGL_NONE
        )
        val sc = sharedContext ?: EGL14.EGL_NO_CONTEXT
        val ctx = EGL14.eglCreateContext(eglDisplay, eglConfig, sc, contextAttribs, 0)
        if (ctx == null || ctx == EGL14.EGL_NO_CONTEXT) {
            throw RuntimeException("EGL14: failed to create context")
        }
        eglContext = ctx
    }

    fun createWindowSurface(surface: Surface): EGLSurface {
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        val eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay,
            eglConfig,
            surface,
            surfaceAttribs,
            0
        )
        if (eglSurface == null || eglSurface == EGL14.EGL_NO_SURFACE) {
            throw RuntimeException("EGL14: failed to create window surface")
        }
        return eglSurface
    }

    fun makeCurrent(surface: EGLSurface) {
        if (!EGL14.eglMakeCurrent(eglDisplay, surface, surface, eglContext)) {
            throw RuntimeException("EGL14: eglMakeCurrent failed")
        }
    }

    fun swapBuffers(surface: EGLSurface): Boolean {
        return EGL14.eglSwapBuffers(eglDisplay, surface)
    }

    fun setPresentationTime(surface: EGLSurface, nsecs: Long) {
        EGLExt.eglPresentationTimeANDROID(eglDisplay, surface, nsecs)
    }

    fun releaseSurface(surface: EGLSurface) {
        EGL14.eglDestroySurface(eglDisplay, surface)
    }

    fun release() {
        EGL14.eglMakeCurrent(
            eglDisplay,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT
        )
        EGL14.eglDestroyContext(eglDisplay, eglContext)
        EGL14.eglReleaseThread()
        EGL14.eglTerminate(eglDisplay)
    }
}

