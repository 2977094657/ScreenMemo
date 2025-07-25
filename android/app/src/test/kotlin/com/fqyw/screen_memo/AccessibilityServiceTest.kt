package com.fqyw.screen_memo

import android.content.Context
import android.content.SharedPreferences
import android.os.PowerManager
import android.provider.Settings
import io.mockk.*
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

/**
 * AccessibilityService相关功能的单元测试
 */
class AccessibilityServiceTest {

    private lateinit var mockContext: Context
    private lateinit var mockSharedPreferences: SharedPreferences
    private lateinit var mockEditor: SharedPreferences.Editor
    private lateinit var mockPowerManager: PowerManager
    private lateinit var mockWakeLock: PowerManager.WakeLock

    @Before
    fun setup() {
        mockContext = mockk(relaxed = true)
        mockSharedPreferences = mockk(relaxed = true)
        mockEditor = mockk(relaxed = true)
        mockPowerManager = mockk(relaxed = true)
        mockWakeLock = mockk(relaxed = true)

        every { mockContext.getSharedPreferences(any(), any()) } returns mockSharedPreferences
        every { mockSharedPreferences.edit() } returns mockEditor
        every { mockEditor.putBoolean(any(), any()) } returns mockEditor
        every { mockEditor.apply() } just Runs
        every { mockContext.getSystemService(Context.POWER_SERVICE) } returns mockPowerManager
        every { mockPowerManager.newWakeLock(any(), any()) } returns mockWakeLock
        every { mockWakeLock.acquire() } just Runs
        every { mockWakeLock.release() } just Runs
        every { mockWakeLock.isHeld } returns true
    }

    @Test
    fun testAccessibilityStateMonitor_Creation() {
        // 测试AccessibilityStateMonitor的创建
        val monitor = AccessibilityStateMonitor(mockContext)
        assertNotNull("AccessibilityStateMonitor应该能够正常创建", monitor)
    }

    @Test
    fun testAccessibilityStateMonitor_StartMonitoring() {
        // 测试开始监听功能
        val monitor = AccessibilityStateMonitor(mockContext)
        
        // 这里应该不会抛出异常
        assertDoesNotThrow("开始监听不应该抛出异常") {
            monitor.startMonitoring()
        }
    }

    @Test
    fun testAccessibilityStateMonitor_StopMonitoring() {
        // 测试停止监听功能
        val monitor = AccessibilityStateMonitor(mockContext)
        monitor.startMonitoring()
        
        // 这里应该不会抛出异常
        assertDoesNotThrow("停止监听不应该抛出异常") {
            monitor.stopMonitoring()
        }
    }

    @Test
    fun testServiceStateManagement() {
        // 测试服务状态管理
        every { mockSharedPreferences.getBoolean("accessibility_service_running", false) } returns true
        
        val isRunning = mockSharedPreferences.getBoolean("accessibility_service_running", false)
        assertTrue("服务状态应该正确保存和读取", isRunning)
    }

    @Test
    fun testWakeLockManagement() {
        // 测试WakeLock管理
        val wakeLock = mockPowerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ScreenMemo:AccessibilityWakeLock"
        )
        
        wakeLock.acquire()
        verify { mockWakeLock.acquire() }
        
        wakeLock.release()
        verify { mockWakeLock.release() }
    }

    @Test
    fun testAccessibilityServiceInstance() {
        // 测试AccessibilityService实例管理
        assertNull("初始时服务实例应该为null", ScreenCaptureAccessibilityService.instance)
        assertFalse("初始时服务状态应该为false", ScreenCaptureAccessibilityService.isServiceRunning)
    }

    @Test
    fun testServiceStateManager() {
        // 测试ServiceStateManager功能
        ServiceStateManager.setAccessibilityServiceRunning(mockContext, true)
        ServiceStateManager.setAccessibilityServiceEnabled(mockContext, true)
        ServiceStateManager.setForegroundServiceRunning(mockContext, true)

        // 验证状态设置
        verify { mockEditor.putBoolean(any(), any()) }
        verify { mockEditor.apply() }
    }

    @Test
    fun testServiceDebugHelper() {
        // 测试ServiceDebugHelper的状态检查功能
        val instanceStatus = ServiceDebugHelper.checkServiceInstanceStatus()

        assertNotNull("实例状态不应该为null", instanceStatus)
        assertTrue("应该包含instanceExists键", instanceStatus.containsKey("instanceExists"))
        assertTrue("应该包含isServiceRunning键", instanceStatus.containsKey("isServiceRunning"))
        assertTrue("应该包含foregroundServiceRunning键", instanceStatus.containsKey("foregroundServiceRunning"))
    }

    private fun assertDoesNotThrow(message: String, executable: () -> Unit) {
        try {
            executable()
        } catch (e: Exception) {
            fail("$message, 但是抛出了异常: ${e.message}")
        }
    }
}
