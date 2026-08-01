; FarmWatchdog.ahk — 刷图看门狗模块
; 监控局数停滞 + 游戏进程缺失, 触发重启建房

global g_FarmWatchdog_Enabled := false
global g_FarmWatchdog_Duration := 120
global g_FarmWatchdog_NoGameCount := 0
global g_FarmWatchdog_LastRunCount := -1
global g_FarmWatchdog_StuckCount := 0
global g_FarmWatchdog_RestartCount := 0

FarmWatchdog_GetWorkMode() {
    global g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled
    return RestartGamePolicy.DetectWorkMode(
        g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled)
}

FarmWatchdog_TriggerRestart(reason) {
    global g_FarmWatchdog_RestartCount
    if (!ConfigManager.IsModuleSupported("RestartGame")) {
        Logger.Error("FarmWatchdog: 当前服务端不支持 RestartGame, 无法重启建房")
        return false
    }
    workMode := FarmWatchdog_GetWorkMode()
    Logger.Info("FarmWatchdog: " reason ", 触发" RestartGamePolicy.WorkModeLabel(workMode) "重启建房")
    if (RestartGame_Start(workMode)) {
        g_FarmWatchdog_RestartCount++
        return true
    }
    return false
}

FarmWatchdog_Init() {
    global g_FarmWatchdog_Duration
    g_FarmWatchdog_Duration := ConfigManager.Read("FarmWatchdog", "Watch_Duration", 120)
    Logger.Info("FarmWatchdog 初始化完成 (停滞阈值=" g_FarmWatchdog_Duration "s)")
}

FarmWatchdog_Start() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_NoGameCount, g_FarmWatchdog_LastRunCount, g_FarmWatchdog_StuckCount
    global g_FarmWatchdog_RestartCount
    g_FarmWatchdog_Enabled := true
    g_FarmWatchdog_NoGameCount := 0
    g_FarmWatchdog_LastRunCount := -1
    g_FarmWatchdog_StuckCount := 0
    g_FarmWatchdog_RestartCount := 0
    Logger.Info("FarmWatchdog: 已启动")
}

FarmWatchdog_Stop() {
    global g_FarmWatchdog_Enabled
    g_FarmWatchdog_Enabled := false
    Logger.Info("FarmWatchdog: 已停止")
}

FarmWatchdog_Cleanup() {
    FarmWatchdog_Stop()
}

FarmWatchdog_Tick() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_Duration
    global g_FarmWatchdog_NoGameCount, g_FarmWatchdog_LastRunCount, g_FarmWatchdog_StuckCount
    global g_FarmWatchdog_RestartCount
    global g_RestartGame_Enabled, g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled
    global g_AutoFarm_RunCount, g_AutoFarmMulti_RunCount, g_AutoMatch_RunCount
    global g_AutoMatch_Enabled

    if (!g_FarmWatchdog_Enabled)
        return
    if (g_RestartGame_Enabled) {
        g_FarmWatchdog_NoGameCount := 0
        g_FarmWatchdog_StuckCount := 0
        return
    }

    ; --- 检测1: 游戏进程不存在 ---
    if (!GameUtils.IsGameRunning()) {
        g_FarmWatchdog_NoGameCount++
        if (g_FarmWatchdog_NoGameCount >= g_FarmWatchdog_Duration) {
            g_FarmWatchdog_NoGameCount := 0
            FarmWatchdog_TriggerRestart("游戏未运行 " g_FarmWatchdog_Duration "s")
        }
        return
    }
    g_FarmWatchdog_NoGameCount := 0

    ; --- 检测2: 局数/场次停滞 (刷图或刷场次任一在运行) ---
    anyFarmRunning := g_AutoFarm_Enabled || g_AutoFarmMulti_Enabled || g_AutoMatch_Enabled
    if (!anyFarmRunning) {
        g_FarmWatchdog_StuckCount := 0
        g_FarmWatchdog_LastRunCount := -1
        return
    }

    currentCount := g_AutoFarm_Enabled ? g_AutoFarm_RunCount : g_AutoFarmMulti_Enabled ? g_AutoFarmMulti_RunCount : g_AutoMatch_RunCount

    if (g_FarmWatchdog_LastRunCount == -1) {
        g_FarmWatchdog_LastRunCount := currentCount
        g_FarmWatchdog_StuckCount := 0
        return
    }

    if (currentCount != g_FarmWatchdog_LastRunCount) {
        g_FarmWatchdog_LastRunCount := currentCount
        g_FarmWatchdog_StuckCount := 0
        return
    }

    g_FarmWatchdog_StuckCount++
    if (g_FarmWatchdog_StuckCount >= g_FarmWatchdog_Duration) {
        g_FarmWatchdog_StuckCount := 0
        FarmWatchdog_TriggerRestart("局数停滞 " g_FarmWatchdog_Duration "s (当前" currentCount "局)")
    }
}
