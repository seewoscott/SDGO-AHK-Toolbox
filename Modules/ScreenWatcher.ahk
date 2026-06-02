; ScreenWatcher.ahk — 画面监控模块 (ImageSearch)
; 搜索参考截图, 持续出现 N 秒后自动触发 RestartGame

global g_ScreenWatcher_Enabled := false
global g_ScreenWatcher_Duration := 5
global g_ScreenWatcher_MatchCount := 0
global g_ScreenWatcher_NoGameCount := 0
global g_ScreenWatcher_ImagePath := A_ScriptDir "\Data\Images\watch.png"

ScreenWatcher_Init() {
    global g_ScreenWatcher_Duration, g_ScreenWatcher_MatchCount
    g_ScreenWatcher_Duration := ConfigManager.Read("ScreenWatcher", "Watch_Duration", 5)
    g_ScreenWatcher_MatchCount := 0
    Logger.Info("ScreenWatcher 初始化完成 (持续=" g_ScreenWatcher_Duration "s)")
}

ScreenWatcher_Start() {
    global g_ScreenWatcher_Enabled, g_ScreenWatcher_MatchCount
    g_ScreenWatcher_Enabled := true
    g_ScreenWatcher_MatchCount := 0
        Logger.Info("ScreenWatcher: 已启动")
}

ScreenWatcher_Stop() {
    global g_ScreenWatcher_Enabled
    g_ScreenWatcher_Enabled := false
    Logger.Info("ScreenWatcher: 已停止")
}

ScreenWatcher_Cleanup() {
    ScreenWatcher_Stop()
    Logger.Info("ScreenWatcher: 已清理")
}

ScreenWatcher_Tick() {
    global g_ScreenWatcher_Enabled, g_ScreenWatcher_MatchCount
    global g_ScreenWatcher_Duration, g_ScreenWatcher_ImagePath
    global g_RestartGame_Enabled

    global g_ScreenWatcher_NoGameCount

    if (!g_ScreenWatcher_Enabled)
        return

    ; 游戏未运行检测
    if (!GameUtils.IsGameRunning()) {
        g_ScreenWatcher_NoGameCount++
        g_ScreenWatcher_MatchCount := 0
        if (g_ScreenWatcher_NoGameCount >= g_ScreenWatcher_Duration) {
            if (!g_RestartGame_Enabled) {
                Logger.Info("ScreenWatcher: 游戏未运行 " g_ScreenWatcher_Duration "s, 触发重启建房!")
                g_ScreenWatcher_NoGameCount := 0
                ToggleModule("RestartGame")
            }
        }
        return
    }
    g_ScreenWatcher_NoGameCount := 0
    if (!FileExist(g_ScreenWatcher_ImagePath))
        return

    WinGetPos(&wx, &wy, &ww, &wh, "ahk_exe gonline.exe")
    found := ImageSearch(&px, &py, wx, wy, wx + ww, wy + wh, "*120 " g_ScreenWatcher_ImagePath)
    if (found) {
        g_ScreenWatcher_MatchCount++
        Logger.Debug("[ScreenWatcher] 检测到 ✓ (" g_ScreenWatcher_MatchCount "/" g_ScreenWatcher_Duration "s)")
        if (g_ScreenWatcher_MatchCount >= g_ScreenWatcher_Duration) {
            if (g_RestartGame_Enabled) {
                Logger.Debug("[ScreenWatcher] RestartGame 运行中, 跳过触发")
                g_ScreenWatcher_MatchCount := 0
            } else {
                Logger.Info("ScreenWatcher: 触发重启建房!")
                g_ScreenWatcher_MatchCount := 0
                ToggleModule("RestartGame")
            }
        }
    } else {
        if (g_ScreenWatcher_MatchCount > 0)
            Logger.Debug("[ScreenWatcher] 丢失 (" g_ScreenWatcher_MatchCount "s)")
        g_ScreenWatcher_MatchCount := 0
    }
}
