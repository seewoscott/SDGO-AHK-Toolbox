; AntiAFK.ahk — 防掉线模块
; 定时心跳 + 断线检测 + 自动重登状态机

global g_AntiAFK_Enabled := false
global g_AntiAFK_HeartbeatTimer := 0
global g_AntiAFK_LogWatcherTimer := 0
global g_AntiAFK_ReconnectAttempts := 0
global g_AntiAFK_HeartbeatInterval := 300
global g_AntiAFK_DisconnectPattern := "Socket failed: 10053"
global g_AntiAFK_Reconnecting := false

AntiAFK_Init() {
    cfg := ConfigManager.LoadSection("AntiAFK")
    g_AntiAFK_HeartbeatInterval := cfg.Get("HeartbeatInterval", 300) * 1000
    g_AntiAFK_DisconnectPattern := cfg.Get("DisconnectPattern", "Socket failed: 10053")
    g_AntiAFK_ReconnectAttempts := 0
    Logger.Info("AntiAFK 模块初始化完成 (间隔=" Round(g_AntiAFK_HeartbeatInterval/1000) "s)")
}

AntiAFK_Start() {
    if (!GameUtils.IsGameRunning()) {
        Logger.Warn("AntiAFK: 游戏未运行")
        return false
    }
    g_AntiAFK_Enabled := true
    ; 心跳定时器
    g_AntiAFK_HeartbeatTimer := SetTimer(AntiAFK_SendHeartbeat, g_AntiAFK_HeartbeatInterval)
    ; 断线检测定时器 (每15秒检查)
    g_AntiAFK_LogWatcherTimer := SetTimer(AntiAFK_CheckDisconnect, 15000)
    AntiAFK_SendHeartbeat()
    Logger.Info("AntiAFK: 已启动 (心跳间隔=" Round(g_AntiAFK_HeartbeatInterval/1000) "s)")
    return true
}

AntiAFK_Stop() {
    g_AntiAFK_Enabled := false
    if (g_AntiAFK_HeartbeatTimer)
        SetTimer(g_AntiAFK_HeartbeatTimer, 0)
    if (g_AntiAFK_LogWatcherTimer)
        SetTimer(g_AntiAFK_LogWatcherTimer, 0)
    g_AntiAFK_HeartbeatTimer := 0
    g_AntiAFK_LogWatcherTimer := 0
    g_AntiAFK_Reconnecting := false
    Logger.Info("AntiAFK: 已停止")
}

AntiAFK_Tick() {
    ; 由主循环 SetTimer 调用, 占位
}

AntiAFK_Cleanup() {
    AntiAFK_Stop()
    Logger.Info("AntiAFK: 已清理")
}

; 发送心跳按键 (空格)
AntiAFK_SendHeartbeat() {
    if (!g_AntiAFK_Enabled || g_AntiAFK_Reconnecting)
        return
    if (!GameUtils.IsGameRunning()) {
        Logger.Warn("AntiAFK: 游戏不存在, 尝试重登...")
        AntiAFK_StartReconnect()
        return
    }
    GameUtils.SendGameKeyOnce("Space", 0)
}

; 检查是否断线
AntiAFK_CheckDisconnect() {
    if (!g_AntiAFK_Enabled || !GameUtils.IsGameRunning())
        return
    if (!GameUtils.IsGameRunning()) {
        Logger.Warn("AntiAFK: 游戏进程消失")
        AntiAFK_StartReconnect()
        return
    }
    if (GameUtils.CheckLogFile(g_AntiAFK_DisconnectPattern)) {
        Logger.Warn("AntiAFK: 检测到断线 (" g_AntiAFK_DisconnectPattern ")")
        AntiAFK_StartReconnect()
    }
}

; 自动重登状态机
AntiAFK_StartReconnect() {
    if (g_AntiAFK_Reconnecting)
        return
    maxAttempts := ConfigManager.Read("AntiAFK", "MaxReconnectAttempts", 3)
    if (g_AntiAFK_ReconnectAttempts >= maxAttempts) {
        Logger.Error("AntiAFK: 重登已达最大尝试次数 (" maxAttempts "), 停止重试")
        g_AntiAFK_ReconnectAttempts := 0
        return
    }
    g_AntiAFK_Reconnecting := true
    g_AntiAFK_ReconnectAttempts++
    Logger.Info("AntiAFK: 开始重登流程 (第 " g_AntiAFK_ReconnectAttempts "/" maxAttempts " 次)")

    reconnectDelay := ConfigManager.Read("AntiAFK", "ReconnectDelay", 30)
    Sleep(reconnectDelay * 1000)

    ; 等待游戏进程恢复 (可能已自动重启)
    if (!GameUtils.IsGameRunning()) {
        Logger.Warn("AntiAFK: 等待游戏进程...")
        if (!GameUtils.WaitFor(ObjBindMethod(GameUtils, "IsGameRunning"), 60000)) {
            Logger.Error("AntiAFK: 等待游戏进程超时")
            g_AntiAFK_Reconnecting := false
            return
        }
        Sleep(5000)  ; 等待窗口完全创建
    }

    ; 执行登录流程
    if (!AntiAFK_DoLogin()) {
        Logger.Error("AntiAFK: 登录流程失败")
        g_AntiAFK_Reconnecting := false
        ; 递归重试
        SetTimer(AntiAFK_StartReconnect, -5000)
        return
    }

    g_AntiAFK_Reconnecting := false
    g_AntiAFK_ReconnectAttempts := 0
    Logger.Info("AntiAFK: 重登成功!")
}

; 登录流程 - 委托给 GameUtils.DoLogin() 共享方法
AntiAFK_DoLogin() {
    return GameUtils.DoLogin()
}
