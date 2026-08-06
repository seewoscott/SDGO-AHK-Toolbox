; FarmWatchdog.ahk — 刷图/场次看门狗模块
; 独立监控刷图停滞、刷场次停滞和游戏进程缺失，触发对应模式的重启建房。

global g_FarmWatchdog_Enabled := false
global g_FarmWatchdog_FarmStallDuration := 180
global g_FarmWatchdog_MatchStallDuration := 1200
global g_FarmWatchdog_NoGameDuration := 60
global g_FarmWatchdog_NoGameCount := 0
global g_FarmWatchdog_LastRunCount := -1
global g_FarmWatchdog_StuckCount := 0
global g_FarmWatchdog_CurrentSource := FarmWatchdogPolicy.NoneSource
global g_FarmWatchdog_RestartCount := 0
global g_FarmWatchdog_RestartRecoveryPending := false
global g_FarmWatchdog_LastRestartStopGeneration := 0

FarmWatchdog_CancelRestartRecovery() {
    global g_FarmWatchdog_RestartRecoveryPending
    SetTimer(FarmWatchdog_RestartRecoveryTimer, 0)
    g_FarmWatchdog_RestartRecoveryPending := false
}

FarmWatchdog_CheckRestartStop() {
    global g_FarmWatchdog_RestartRecoveryPending, g_FarmWatchdog_LastRestartStopGeneration
    global g_RestartGame_StopGeneration

    if (g_RestartGame_StopGeneration == g_FarmWatchdog_LastRestartStopGeneration)
        return
    g_FarmWatchdog_LastRestartStopGeneration := g_RestartGame_StopGeneration
    FarmWatchdog_CancelRestartRecovery()

    scene := RestartGame_DetectScene("IN_ROOM", 1)
    if (scene == "IN_ROOM")
        return

    g_FarmWatchdog_RestartRecoveryPending := true
    Logger.Warn("FarmWatchdog: RestartGame 已停止但当前场景不是 IN_ROOM (" scene
        "), 10秒后执行恢复重启循环")
    SetTimer(FarmWatchdog_RestartRecoveryTimer, -10000)
}

FarmWatchdog_RestartRecoveryTimer() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_RestartRecoveryPending
    global g_RestartGame_Enabled

    g_FarmWatchdog_RestartRecoveryPending := false
    if (!g_FarmWatchdog_Enabled || g_RestartGame_Enabled)
        return

    scene := RestartGame_DetectScene("IN_ROOM", 1)
    if (scene == "IN_ROOM") {
        Logger.Info("FarmWatchdog: 已确认 IN_ROOM，结束恢复重启循环")
        return
    }

    Logger.Warn("FarmWatchdog: 恢复重启循环触发，当前场景=" scene)
    if (!FarmWatchdog_TriggerRestart(
        "RestartGame 停止后场景异常", 10, "目标=IN_ROOM, 实际=" scene)) {
        g_FarmWatchdog_RestartRecoveryPending := true
        SetTimer(FarmWatchdog_RestartRecoveryTimer, -10000)
    }
}

FarmWatchdog_GetWorkMode() {
    global g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled
    return RestartGamePolicy.DetectWorkMode(
        g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled)
}

FarmWatchdog_ResetProgress(clearSource := true) {
    global g_FarmWatchdog_LastRunCount, g_FarmWatchdog_StuckCount
    global g_FarmWatchdog_CurrentSource
    g_FarmWatchdog_LastRunCount := -1
    g_FarmWatchdog_StuckCount := 0
    if (clearSource)
        g_FarmWatchdog_CurrentSource := FarmWatchdogPolicy.NoneSource
}

FarmWatchdog_GetMonitorSnapshot() {
    global g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled
    global g_AutoFarm_RunCount, g_AutoFarmMulti_RunCount, g_AutoMatch_RunCount
    global g_FarmWatchdog_FarmStallDuration, g_FarmWatchdog_MatchStallDuration

    source := FarmWatchdogPolicy.ResolveSource(
        g_AutoFarm_Enabled, g_AutoFarmMulti_Enabled, g_AutoMatch_Enabled)
    if (source == FarmWatchdogPolicy.NoneSource)
        return {source: source, count: -1, duration: 0}

    if (source == FarmWatchdogPolicy.AutoFarmSource)
        count := g_AutoFarm_RunCount
    else if (source == FarmWatchdogPolicy.AutoFarmMultiSource)
        count := g_AutoFarmMulti_RunCount
    else
        count := g_AutoMatch_RunCount

    return {
        source: source,
        count: count,
        duration: FarmWatchdogPolicy.DurationForSource(
            source, g_FarmWatchdog_FarmStallDuration, g_FarmWatchdog_MatchStallDuration)
    }
}

FarmWatchdog_TriggerRestart(triggerType, threshold, detail := "") {
    global g_FarmWatchdog_RestartCount
    if (!ConfigManager.IsModuleSupported("RestartGame")) {
        Logger.Error("FarmWatchdog: 当前服务端不支持 RestartGame, 无法重启建房")
        return false
    }
    workMode := FarmWatchdog_GetWorkMode()
    detailText := detail == "" ? "" : " | " detail
    Logger.Warn("FarmWatchdog: 触发类型=" triggerType
        " | 阈值=" threshold "s" detailText
        " | 重启模式=" RestartGamePolicy.WorkModeLabel(workMode))
    if (RestartGame_Start(workMode)) {
        g_FarmWatchdog_RestartCount++
        return true
    }
    return false
}

FarmWatchdog_Init() {
    global g_FarmWatchdog_FarmStallDuration, g_FarmWatchdog_MatchStallDuration
    global g_FarmWatchdog_NoGameDuration

    ; 旧 Watch_Duration 只作为刷图阈值的兼容回退。
    legacyFarmDuration := ConfigManager.Read("FarmWatchdog", "Watch_Duration", 180)
    g_FarmWatchdog_FarmStallDuration := FarmWatchdogPolicy.NormalizeDuration(
        ConfigManager.Read("FarmWatchdog", "Farm_Stall_Duration", legacyFarmDuration), 180)
    g_FarmWatchdog_MatchStallDuration := FarmWatchdogPolicy.NormalizeDuration(
        ConfigManager.Read("FarmWatchdog", "Match_Stall_Duration", 1200), 1200)
    g_FarmWatchdog_NoGameDuration := FarmWatchdogPolicy.NormalizeDuration(
        ConfigManager.Read("FarmWatchdog", "NoGame_Duration", 60), 60)
    Logger.Info("FarmWatchdog 初始化完成 (刷图停滞=" g_FarmWatchdog_FarmStallDuration
        "s, 刷场次停滞=" g_FarmWatchdog_MatchStallDuration
        "s, 游戏缺失=" g_FarmWatchdog_NoGameDuration "s)")
}

FarmWatchdog_Start() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_NoGameCount
    global g_FarmWatchdog_RestartCount
    global g_FarmWatchdog_LastRestartStopGeneration, g_RestartGame_StopGeneration
    g_FarmWatchdog_Enabled := true
    g_FarmWatchdog_NoGameCount := 0
    g_FarmWatchdog_RestartCount := 0
    g_FarmWatchdog_LastRestartStopGeneration := g_RestartGame_StopGeneration
    FarmWatchdog_CancelRestartRecovery()
    FarmWatchdog_ResetProgress()
    Logger.Info("FarmWatchdog: 已启动")
}

FarmWatchdog_Stop() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_NoGameCount
    g_FarmWatchdog_Enabled := false
    FarmWatchdog_CancelRestartRecovery()
    g_FarmWatchdog_NoGameCount := 0
    FarmWatchdog_ResetProgress()
    Logger.Info("FarmWatchdog: 已停止")
}

FarmWatchdog_Cleanup() {
    FarmWatchdog_Stop()
}

FarmWatchdog_Tick() {
    global g_FarmWatchdog_Enabled, g_FarmWatchdog_NoGameDuration
    global g_FarmWatchdog_NoGameCount, g_FarmWatchdog_LastRunCount
    global g_FarmWatchdog_StuckCount, g_FarmWatchdog_CurrentSource
    global g_RestartGame_Enabled

    if (!g_FarmWatchdog_Enabled)
        return
    if (g_RestartGame_Enabled) {
        FarmWatchdog_CancelRestartRecovery()
        g_FarmWatchdog_NoGameCount := 0
        FarmWatchdog_ResetProgress()
        return
    }

    FarmWatchdog_CheckRestartStop()

    ; 检测1：无论自动模块是否运行，游戏进程缺失都使用独立阈值。
    if (!GameUtils.IsGameRunning()) {
        g_FarmWatchdog_NoGameCount++
        FarmWatchdog_ResetProgress()
        if (FarmWatchdogPolicy.IsThresholdReached(
            g_FarmWatchdog_NoGameCount, g_FarmWatchdog_NoGameDuration)) {
            g_FarmWatchdog_NoGameCount := 0
            FarmWatchdog_TriggerRestart("游戏进程缺失", g_FarmWatchdog_NoGameDuration,
                "当前进程=" ConfigManager.GameExe)
        }
        return
    }
    g_FarmWatchdog_NoGameCount := 0

    ; 检测2：按实际监控源选择刷图或刷场次阈值。
    snapshot := FarmWatchdog_GetMonitorSnapshot()
    if (snapshot.source == FarmWatchdogPolicy.NoneSource) {
        FarmWatchdog_ResetProgress()
        return
    }

    if (snapshot.source != g_FarmWatchdog_CurrentSource) {
        oldLabel := FarmWatchdogPolicy.SourceLabel(g_FarmWatchdog_CurrentSource)
        newLabel := FarmWatchdogPolicy.SourceLabel(snapshot.source)
        Logger.Info("FarmWatchdog: 监控源切换 " oldLabel " → " newLabel
            "，重置停滞计时 (阈值=" snapshot.duration "s)")
        g_FarmWatchdog_CurrentSource := snapshot.source
        g_FarmWatchdog_LastRunCount := snapshot.count
        g_FarmWatchdog_StuckCount := 0
        return
    }

    if (snapshot.count != g_FarmWatchdog_LastRunCount) {
        g_FarmWatchdog_LastRunCount := snapshot.count
        g_FarmWatchdog_StuckCount := 0
        return
    }

    g_FarmWatchdog_StuckCount++
    if (FarmWatchdogPolicy.IsThresholdReached(
        g_FarmWatchdog_StuckCount, snapshot.duration)) {
        g_FarmWatchdog_StuckCount := 0
        countLabel := FarmWatchdogPolicy.CountLabel(snapshot.source)
        FarmWatchdog_TriggerRestart(
            FarmWatchdogPolicy.SourceLabel(snapshot.source) "停滞",
            snapshot.duration,
            "当前" countLabel "=" snapshot.count)
    }
}
