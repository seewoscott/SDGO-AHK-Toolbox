; ======================================================================
; SDGO工具脚本 — AutoHotkey v2 游戏工具箱
; SDGO UNION 1.4.3 (SD高达私服)
; 架构: Hub-Spoke, 通过 GUI 控制面板管理所有自动化模块
; ======================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; --- 常量定义 ---
global APP_NAME := "SDGO工具脚本"
global APP_VERSION := "2.2.3"
global SCRIPT_DIR := A_ScriptDir
global g_DesktopW := 0
global g_DesktopH := 0
global g_ResolutionProfile := ""

; --- 加载库 ---
#Include "Lib\ConfigManager.ahk"
#Include "Lib\Logger.ahk"
#Include "Lib\AutoUpdater.ahk"
#Include "Lib\ScreenCapture.ahk"
#Include "Lib\TargetLockDetector.ahk"
#Include "Lib\CombatTargetDetector.ahk"
#Include "Lib\RoomSelfDetector.ahk"
#Include "Lib\AutoMatchPolicy.ahk"
#Include "Lib\RestartGamePolicy.ahk"
#Include "Lib\FarmWatchdogPolicy.ahk"
#Include "Lib\GameUtils.ahk"
#Include "Lib\OverlayManager.ahk"

; --- 加载模块 ---
#Include "Modules\AutoFarm.ahk"
#Include "Modules\RestartGame.ahk"
#Include "Modules\AutoFarmMulti.ahk"
#Include "Modules\FarmWatchdog.ahk"
#Include "Modules\AutoMatch.ahk"

; --- GUI 相关全局变量 ---
global g_Gui := 0
global g_Tab := 0
global g_LogEdit := 0
global g_StatusBar := 0
global g_GameStatus := "未检测"

; 模块状态控件句柄
global g_Ctrl_AutoFarm := 0
global g_Ctrl_RestartGame := 0
global g_Ctrl_AutoFarmMulti := 0
global g_Ctrl_AutoFarmMulti_RunCount := 0
global g_Ctrl_FarmWatchdog := 0
global g_Ctrl_AutoMatch := 0
global g_Ctrl_AutoMatch_RunCount := 0
global g_Ctrl_GameStatus := 0
global g_Ctrl_AutoFarm_RunCount := 0
global g_Ctrl_LogLevel := 0
global g_Ctrl_ServerProfile := 0

; 模块控件映射 (key=模块名, value=控件数组, 用于按服显隐)
global g_AllModuleControls := Map()
global g_AllSettingsControls := Map()

; 全局控制热键修饰符
global g_HotkeyMod := ""

; --- 初始化 ---
Init() {
    global g_HotkeyMod
    logLevel := ConfigManager.Read("Logging", "LogLevel", "INFO")
    maxFiles := ConfigManager.Read("Logging", "MaxLogFiles", 10)
    Logger.Init(logLevel, maxFiles)

    ; 检测当前桌面分辨率
    global g_DesktopW, g_DesktopH, g_ResolutionProfile
    MonitorGet(, &MonLeft, &MonTop, &MonRight, &MonBottom)
    g_DesktopW := MonRight - MonLeft
    g_DesktopH := MonBottom - MonTop
    g_ResolutionProfile := g_DesktopW "x" g_DesktopH
    Logger.Info("桌面分辨率: " g_ResolutionProfile)

    Logger.Info(APP_NAME " v" APP_VERSION " 启动")

    ; 自动提权: taskkill /F 需要管理员权限
    if (!A_IsAdmin) {
        Logger.Warn("未以管理员身份运行, 正在尝试提权...")
        try {
            Run("*RunAs " A_ScriptFullPath, A_ScriptDir)
            ExitApp(0)
        } catch as e {
            Logger.Error("提权失败: " e.Message)
            MsgBox("请右键 启动.bat → 以管理员身份运行", "需要管理员权限", 48)
            ExitApp(1)
        }
    }

    ; 已编译客户端启动时检查局域网发布目录；开发时运行源码不会触发更新。
    AutoUpdater.CheckAndApply(APP_VERSION)
    ; 挂机工具常驻运行: 定期检查新版本并自动热更新 (间隔见 [Updater] CheckIntervalMinutes)。
    AutoUpdater.StartPeriodicCheck(APP_VERSION)

    ; 注册退出/错误处理
    OnExit(ExitHandler, 1)
    OnError(ErrorHandler, 1)

    ; 读取热键修饰符
    g_HotkeyMod := ConfigManager.Read("General", "HotkeyModifier", "^!")

    ; 加载服务端配置 (必须在 GameUtils.Init() 之前)
    ConfigManager.LoadServerConfig()

    ; 初始化 GameUtils
    if (GameUtils.Init()) {
        Logger.Info("游戏窗口已检测到 (hWnd=" GameUtils.g_hWnd ")")
    } else {
        Logger.Warn("未检测到游戏窗口 (" ConfigManager.GameExe ")")
    }

    ; 初始化所有模块
    AutoFarm_Init()
    RestartGame_Init()
    FarmWatchdog_Init()
    AutoFarmMulti_Init()
    AutoMatch_Init()

    ; 注册全局热键
    RegisterGlobalHotkeys()

    ; 构建并显示 GUI
    BuildGui()

    ; 初始化覆盖层
    OverlayManager.Init()

    ; 设置托盘图标
    SetupTray()

    Logger.Info("初始化完成, GUI 已启动")
}


; --- 注册全局控制热键 ---
RegisterGlobalHotkeys() {
    mod := g_HotkeyMod  ; 默认 ^! (Ctrl+Alt)

    ; F5~F9: 模块开关 ($前缀 = 仅物理按键, SendInput模拟的不会触发)
    Hotkey("$F5", (*) => ToggleModule("RestartGame"), "On")
    Hotkey("$F6", (*) => ToggleModule("FarmWatchdog"), "On")
    Hotkey("$F7", (*) => ToggleModule("AutoFarm"), "On")
    Hotkey("$F8", (*) => ToggleModule("AutoFarmMulti"), "On")
    Hotkey("$F9", (*) => ToggleModule("AutoMatch"), "On")
    ; 自动化/远程控制备用入口；保留物理 F9 的 $ 防回触发语义。
    Hotkey(mod "F9", (*) => ToggleModule("AutoMatch"), "On")

    ; F12: 坐标捕获
    Hotkey("$F12", (*) => CaptureCoords(), "On")

    ; Ctrl+Alt+R: 重载脚本
    Hotkey(mod "R", (*) => Reload(), "On")

    ; 紧急停止 (Esc)
    stopKey := ConfigManager.Read("General", "EmergencyStop", "Esc")
    Hotkey(mod . stopKey, (*) => EmergencyStop(), "On")

    ; 覆盖层开关 (F10)
    try Hotkey("$F10", (*) => OverlayManager.Toggle(), "On")
}

; --- 坐标捕获 (F12) ---
CaptureCoords() {
    CoordMode "Mouse", "Client"
    MouseGetPos(&cx, &cy, &hwnd, &ctrl)
    CoordMode "Mouse", "Screen"
    MouseGetPos(&sx, &sy)

    color := PixelGetColor(sx, sy)
    WinGetPos( , , &ww, &wh, hwnd)
    title := WinGetTitle(hwnd)
    proc := WinGetProcessName(hwnd)

    A_Clipboard := cx ", " cy " | " color
    Logger.Info("坐标捕获: " title " | " proc
        " | Client=(" cx ", " cy ") | Color=" color " | WinSize=" ww "x" wh)
    ToolTip("已复制: " cx ", " cy "`n颜色: " color "`n" title, , , 3)
    SetTimer(() => ToolTip(, , , 3), -4000)
}

; 根据当前服务端更新各模块控件显隐 (INI 驱动)
UpdateModuleVisibility() {
    global g_AllModuleControls, g_AllSettingsControls
    for moduleName, controls in g_AllModuleControls {
        visible := ConfigManager.IsModuleSupported(moduleName)
        for ctrl in controls
            try ctrl.Visible := visible
    }
    for moduleName, controls in g_AllSettingsControls {
        visible := ConfigManager.IsModuleSupported(moduleName)
        for ctrl in controls
            try ctrl.Visible := visible
    }
}

; --- 切换模块 ---
ToggleModule(module) {
    switch module {
    case "AutoFarm":
        if (!ConfigManager.IsModuleSupported("AutoFarm")) {
            ToolTip("AutoFarm 不支持当前服", , , 3)
            SetTimer(() => ToolTip(, , , 3), -2000)
            return
        }
        if (g_AutoFarm_Enabled)
            AutoFarm_Stop()
        else
            AutoFarm_Start()
        UpdateGuiStatus()
    case "RestartGame":
        if (!ConfigManager.IsModuleSupported("RestartGame")) {
            ToolTip("RestartGame 不支持当前服", , , 3)
            SetTimer(() => ToolTip(, , , 3), -2000)
            return
        }
        if (g_RestartGame_Enabled)
            RestartGame_Stop()
        else
            RestartGame_Start()
        UpdateGuiStatus()
    case "FarmWatchdog":
        if (!ConfigManager.IsModuleSupported("FarmWatchdog")) {
            ToolTip("FarmWatchdog 不支持当前服", , , 3)
            SetTimer(() => ToolTip(, , , 3), -2000)
            return
        }
        if (g_FarmWatchdog_Enabled)
            FarmWatchdog_Stop()
        else
            FarmWatchdog_Start()
        UpdateGuiStatus()
    case "AutoFarmMulti":
        if (!ConfigManager.IsModuleSupported("AutoFarmMulti")) {
            ToolTip("AutoFarmMulti 不支持当前服", , , 3)
            SetTimer(() => ToolTip(, , , 3), -2000)
            return
        }
        if (g_AutoFarmMulti_Enabled)
            AutoFarmMulti_Stop()
        else
            AutoFarmMulti_Start()
        UpdateGuiStatus()
    case "AutoMatch":
        if (g_AutoMatch_Enabled)
            AutoMatch_Stop()
        else
            AutoMatch_Start()
        UpdateGuiStatus()
    }
}

; --- 紧急停止 ---
EmergencyStop() {
    Logger.Warn("紧急停止!")
    AutoFarm_Stop()
    RestartGame_Stop()
    FarmWatchdog_Stop()
    AutoFarmMulti_Stop()
    AutoMatch_Stop()
    UpdateGuiStatus()
    ToolTip("⚠ 紧急停止 - 所有模块已停止", , , 2)
    SetTimer(() => ToolTip(, , , 2), -3000)
}

; --- 构建 GUI ---
BuildGui() {
    global g_Gui, g_Tab, g_LogEdit, g_StatusBar, g_Ctrl_RestartGame, g_Ctrl_LogLevel, g_HotkeyMod
    global g_Ctrl_AutoFarm, g_Ctrl_AutoFarm_RunCount, g_Ctrl_ServerProfile
    global g_Ctrl_AutoFarmMulti, g_Ctrl_AutoFarmMulti_RunCount
    global g_Ctrl_FarmWatchdog, g_Ctrl_FarmWatchdog_RestartCount
    global g_Ctrl_AutoMatch, g_Ctrl_AutoMatch_RunCount, g_AutoMatch_MaxRuns
    global g_FarmWatchdog_FarmStallDuration, g_FarmWatchdog_MatchStallDuration
    global g_AllModuleControls, g_AllSettingsControls

    g_Gui := Gui("+Resize +MinSize500x400 +MaximizeBox", APP_NAME " v" APP_VERSION " — " ConfigManager.ServerDisplayName)
    g_Gui.OnEvent("Close", GuiClose)
    g_Gui.OnEvent("Size", GuiSize)
    g_Gui.SetFont("s9", "Segoe UI")

    ; 顶部游戏状态栏
    g_Gui.Add("Text", "w500 h30 vGameStatusBar Center 0x200",
        FormatGameStatusText())

    ; 主选项卡
    g_Tab := g_Gui.Add("Tab3", "x10 y+m w480 h320 vMainTab", [
        "功能模块",
        "设置",
        "日志"
    ])
    g_Tab.OnEvent("Change", TabChange)

    ; ===== 选项卡1: 功能模块 =====
    g_Tab.UseTab(1)
    g_Gui.SetFont("s10 bold")
    g_Gui.Add("Text", "x20 y+10 w460 h30", "模块控制")
    g_Gui.SetFont("s9 norm")

    ; 模块1: RestartGame (F5)
    gb3 := g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "重启建房 (RestartGame)  [F5]")
    desc3 := g_Gui.Add("Text", "xp+20 yp+25 w280", "重启游戏 → 按刷图/场次进入对应频道并建房")
    btnRestart := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnRestart", "启动")
    btnRestart.OnEvent("Click", (*) => ToggleModule("RestartGame"))
    g_Ctrl_RestartGame := btnRestart
    g_AllModuleControls["RestartGame"] := [gb3, desc3, btnRestart]

    ; 模块2: FarmWatchdog (F6)
    gb4 := g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "看门狗 (FarmWatchdog)  [F6]")
    desc4 := g_Gui.Add("Text", "xp+20 yp+25 w240", "刷图/场次停滞或游戏缺失 → 重启建房")
    restartCountW := g_Gui.Add("Text", "x300 yp-5 w70 vTxtRestartCountW", "重启: 0")
    g_Ctrl_FarmWatchdog_RestartCount := restartCountW
    btnWatch := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnWatch", "启动")
    btnWatch.OnEvent("Click", (*) => ToggleModule("FarmWatchdog"))
    g_Ctrl_FarmWatchdog := btnWatch
    g_AllModuleControls["FarmWatchdog"] := [gb4, desc4, restartCountW, btnWatch]

    ; 模块3: AutoFarm (F7)
    gb1 := g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "自动刷图-单人 (AutoFarm)  [F7]")
    desc1 := g_Gui.Add("Text", "xp+20 yp+25 w200", "检测开始→F5→战斗→结算→循环")
    runCount := g_Gui.Add("Text", "x300 yp-5 w70 vTxtRunCount", "局数: 0")
    g_Ctrl_AutoFarm_RunCount := runCount
    btnAutoFarm := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAutoFarm", "启动")
    btnAutoFarm.OnEvent("Click", (*) => ToggleModule("AutoFarm"))
    g_Ctrl_AutoFarm := btnAutoFarm
    g_AllModuleControls["AutoFarm"] := [gb1, desc1, runCount, btnAutoFarm]

    ; 模块4: AutoFarmMulti (F8)
    gb2 := g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "自动刷图-多人 (AutoFarmMulti)  [F8]")
    desc2 := g_Gui.Add("Text", "xp+20 yp+25 w200", "检测开始→F5→战斗→结算→循环")
    runCountM := g_Gui.Add("Text", "x300 yp w70 vTxtRunCountM", "局数: 0")
    g_Ctrl_AutoFarmMulti_RunCount := runCountM
    btnAutoFarmM := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAutoFarmM", "启动")
    btnAutoFarmM.OnEvent("Click", (*) => ToggleModule("AutoFarmMulti"))
    g_Ctrl_AutoFarmMulti := btnAutoFarmM
    g_AllModuleControls["AutoFarmMulti"] := [gb2, desc2, runCountM, btnAutoFarmM]

    ; 模块5: AutoMatch (F9)
    gb5 := g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "刷场次 (AutoMatch)  [F9]")
    desc5 := g_Gui.Add("Text", "xp+20 yp+25 w200", "自动识别房主/成员 → 战斗 → 结算 → 循环")
    runCountAM := g_Gui.Add("Text", "x300 yp w70 vTxtRunCountAM", "场次: 0")
    g_Ctrl_AutoMatch_RunCount := runCountAM
    btnAutoMatch := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAutoMatch", "启动")
    btnAutoMatch.OnEvent("Click", (*) => ToggleModule("AutoMatch"))
    g_Ctrl_AutoMatch := btnAutoMatch
    g_AllModuleControls["AutoMatch"] := [gb5, desc5, runCountAM, btnAutoMatch]
    btnStop := g_Gui.Add("Button", "x20 y+20 w100 h35 vBtnStop", "紧急停止 (Esc)")
    btnStop.OnEvent("Click", (*) => EmergencyStop())
    btnStop.SetFont("s10 bold", "Segoe UI")

    btnReload := g_Gui.Add("Button", "x130 yp w100 h35 vBtnReload", "重新启动")
    btnReload.OnEvent("Click", (*) => Reload())
    btnReload.SetFont("s10 bold", "Segoe UI")

    ; 底部热键说明（模块热键已显示在各标题中）
    g_Gui.SetFont("s8")
    g_Gui.Add("Text", "x250 yp+5 w240 h30", "全局: Ctrl+Alt+R=重载  Ctrl+Alt+Esc=停止  F10=覆盖层  F12=坐标")

    ; ===== 选项卡2: 设置 =====
    g_Tab.UseTab(2)
    g_Gui.SetFont("s10 bold")
    g_Gui.Add("Text", "x20 y+10 w460 h30", "通用设置")
    g_Gui.SetFont("s9 norm")

    ; 日志级别
    g_Gui.Add("Text", "x40 y+10 w120", "日志级别:")
    ddlLog := g_Gui.Add("DropDownList", "x+10 w80 vDdlLogLevel Choose" GetLogLevelIndex(), ["DEBUG", "INFO", "WARN", "ERROR"])
    ddlLog.OnEvent("Change", (*) => SaveSettings())
    g_Ctrl_LogLevel := ddlLog

    ; 服务端配置
    g_Gui.Add("Text", "x40 y+10 w120", "服务端配置:")
    serverProfiles := ConfigManager.GetServerProfiles()
    ddlServer := g_Gui.Add("DropDownList", "x+10 w140 vDdlServerProfile", serverProfiles)
    ddlServer.OnEvent("Change", (*) => OnServerProfileChange())
    g_Ctrl_ServerProfile := ddlServer
    ; 设置当前选中项
    for i, profile in serverProfiles {
        if (profile == ConfigManager.ServerDisplayName) {
            ddlServer.Choose(i)
            break
        }
    }

    wdFarmText := g_Gui.Add("Text", "x40 y+10 w150", "刷图停滞阈值(秒):")
    editWDFarm := g_Gui.Add("Edit", "x+10 w70 Number vEditFarmStallDuration", g_FarmWatchdog_FarmStallDuration)
    spinWDFarm := g_Gui.Add("UpDown", "Range1-86400", g_FarmWatchdog_FarmStallDuration)
    editWDFarm.OnEvent("Change", (*) => SaveSettings())
    wdMatchText := g_Gui.Add("Text", "x40 y+8 w150", "刷场次停滞阈值(秒):")
    editWDMatch := g_Gui.Add("Edit", "x+10 w70 Number vEditMatchStallDuration", g_FarmWatchdog_MatchStallDuration)
    spinWDMatch := g_Gui.Add("UpDown", "Range1-86400", g_FarmWatchdog_MatchStallDuration)
    editWDMatch.OnEvent("Change", (*) => SaveSettings())
    g_AllSettingsControls["FarmWatchdog"] := [
        wdFarmText, editWDFarm, spinWDFarm, wdMatchText, editWDMatch, spinWDMatch]

    ; ===== 更新 =====
    g_Gui.SetFont("s10 bold")
    g_Gui.Add("Text", "x20 y+20 w460 h30", "更新")
    g_Gui.SetFont("s9 norm")
    g_Gui.Add("Text", "x40 y+10 w200", "当前版本: v" APP_VERSION)
    btnCheckUpdate := g_Gui.Add("Button", "x+20 yp-3 w120 h28 vBtnCheckUpdate", "检查更新")
    btnCheckUpdate.OnEvent("Click", (*) => AutoUpdater.CheckNow(APP_VERSION))

    ; ===== 选项卡3: 日志 =====
    g_Tab.UseTab(3)
    g_LogEdit := g_Gui.Add("Edit", "x20 y+10 w460 h300 vLogEdit ReadOnly")
    g_LogEdit.SetFont("s8", "Consolas")

    ; 返回功能模块选项卡作为默认
    g_Tab.Choose(1)

    ; 状态栏
    g_StatusBar := g_Gui.Add("StatusBar", , "就绪")

    ; 定时器: GUI 状态更新 + 模块 tick
    SetTimer(GuiTick, 1000)

    ; 根据服务端初始显隐旧服模块
    UpdateModuleVisibility()

    g_Gui.Show("w520 h550")
    UpdateGuiStatus()
}

; --- 格式化游戏状态文本 ---
FormatGameStatusText() {
    if (GameUtils.IsGameRunning()) {
        rect := GameUtils.GetWindowRect()
        if (rect)
            return "🎮 游戏运行中 | 大小: " rect.w "x" rect.h " | 输入: " GameUtils.g_InputMode
        return "🎮 游戏运行中 | 输入: " GameUtils.g_InputMode
    }
    return "⏸ 游戏未运行 | 等待 " ConfigManager.GameExe "..."
}

; --- 获取日志级别下拉框索引 ---
GetLogLevelIndex() {
    switch Logger.g_LogLevel {
    case "DEBUG": return 1
    case "INFO":  return 2
    case "WARN":  return 3
    case "ERROR": return 4
    default:      return 2
    }
}

; --- 保存设置 ---
SaveSettings() {
    global g_Gui, g_AutoFarm_MaxRuns
    global g_FarmWatchdog_FarmStallDuration, g_FarmWatchdog_MatchStallDuration

    saved := g_Gui.Submit(0)

    ; 保存日志级别
    if (saved.HasProp("DdlLogLevel") && saved.DdlLogLevel != "") {
        ConfigManager.Write("Logging", "LogLevel", saved.DdlLogLevel)
        Logger.g_LogLevel := saved.DdlLogLevel
    }

    ; Number 编辑框限制非数字输入；空值编辑中不保存，0 等非正整数也不生效。
    if (saved.HasProp("EditFarmStallDuration")
        && RegExMatch(saved.EditFarmStallDuration, "^[1-9]\d*$")) {
        g_FarmWatchdog_FarmStallDuration := Integer(saved.EditFarmStallDuration)
        ConfigManager.Write("FarmWatchdog", "Farm_Stall_Duration", g_FarmWatchdog_FarmStallDuration)
    }
    if (saved.HasProp("EditMatchStallDuration")
        && RegExMatch(saved.EditMatchStallDuration, "^[1-9]\d*$")) {
        g_FarmWatchdog_MatchStallDuration := Integer(saved.EditMatchStallDuration)
        ConfigManager.Write("FarmWatchdog", "Match_Stall_Duration", g_FarmWatchdog_MatchStallDuration)
    }
}

; 服务端配置切换回调
OnServerProfileChange() {
    global g_Gui, g_Ctrl_ServerProfile
    selected := g_Ctrl_ServerProfile.Text
    if (selected == "" || selected == ConfigManager.ServerDisplayName)
        return
    ConfigManager.Write("Game", "ServerProfile", ConfigManager.GetProfileKey(selected))
    ConfigManager.LoadServerConfig()
    g_Gui.Title := APP_NAME " v" APP_VERSION " — " ConfigManager.ServerDisplayName
    UpdateModuleVisibility()
    Logger.Info("服务端配置已切换: " ConfigManager.ServerDisplayName)
}

; --- GUI 定时器: 刷新状态 ---
GuiTick() {
    global g_Gui, g_Ctrl_AutoFarm_RunCount, g_AutoFarm_RunCount
    global g_Ctrl_AutoFarmMulti_RunCount, g_AutoFarmMulti_RunCount
    global g_Ctrl_FarmWatchdog_RestartCount, g_FarmWatchdog_RestartCount
    global g_Ctrl_AutoMatch_RunCount, g_AutoMatch_RunCount

    ; 更新游戏状态文本
    try {
        ctrl := g_Gui["GameStatusBar"]
        ctrl.Text := FormatGameStatusText()
    }

    ; 更新刷图计数
    if (g_Ctrl_AutoFarm_RunCount) {
        try g_Ctrl_AutoFarm_RunCount.Text := "局数: " g_AutoFarm_RunCount
    }
    if (g_Ctrl_AutoFarmMulti_RunCount) {
        g_Ctrl_AutoFarmMulti_RunCount.Text := "局数: " g_AutoFarmMulti_RunCount
    }

    ; 更新看门狗重启计数
    if (g_Ctrl_FarmWatchdog_RestartCount) {
        try g_Ctrl_FarmWatchdog_RestartCount.Text := "重启: " g_FarmWatchdog_RestartCount
    }

    ; 更新刷场次计数
    if (g_Ctrl_AutoMatch_RunCount) {
        try g_Ctrl_AutoMatch_RunCount.Text := "场次: " g_AutoMatch_RunCount
    }

    ; 调用各模块 Tick
    AutoFarm_Tick()
    RestartGame_Tick()
    FarmWatchdog_Tick()
    AutoFarmMulti_Tick()
    AutoMatch_Tick()

    ; 更新覆盖层
    OverlayManager.Tick()

    UpdateGuiStatus()
}

; --- 更新 GUI 上的模块状态文本 ---
UpdateGuiStatus() {
    ; AutoFarm
    if (g_Ctrl_AutoFarm) {
        g_Ctrl_AutoFarm.Text := g_AutoFarm_Enabled ? "停止" : "启动"
        g_Ctrl_AutoFarm.Redraw()
    }
    ; RestartGame
    if (g_Ctrl_RestartGame) {
        g_Ctrl_RestartGame.Text := g_RestartGame_Enabled ? "停止" : "启动"
        g_Ctrl_RestartGame.Redraw()
    }
    ; AutoFarmMulti
    if (g_Ctrl_AutoFarmMulti) {
        g_Ctrl_AutoFarmMulti.Text := g_AutoFarmMulti_Enabled ? "停止" : "启动"
        g_Ctrl_AutoFarmMulti.Redraw()
    }
    ; FarmWatchdog
    if (g_Ctrl_FarmWatchdog) {
        g_Ctrl_FarmWatchdog.Text := g_FarmWatchdog_Enabled ? "停止" : "启动"
        g_Ctrl_FarmWatchdog.Redraw()
    }
    ; AutoMatch
    if (g_Ctrl_AutoMatch) {
        g_Ctrl_AutoMatch.Text := g_AutoMatch_Enabled ? "停止" : "启动"
        g_Ctrl_AutoMatch.Redraw()
    }
    ; 状态栏
    if (g_StatusBar) {
        parts := []
        if (g_AutoFarm_Enabled)
            parts.Push("刷图:ON")
        if (g_RestartGame_Enabled)
            parts.Push("重启建房:" RestartGamePolicy.WorkModeLabel(g_RestartGame_WorkMode))
        if (g_AutoFarmMulti_Enabled)
            parts.Push("刷图多人:ON")
        if (g_FarmWatchdog_Enabled)
            parts.Push("看门狗:ON")
        if (g_AutoMatch_Enabled)
            parts.Push("刷场次:ON")
        if (parts.Length == 0)
            parts.Push("空闲")
        g_StatusBar.SetText(JoinArr(parts, " | "))
    }
    ; 服务端配置: 模块运行时禁止切换
    if (g_Ctrl_ServerProfile) {
        anyRunning := g_AutoFarm_Enabled
            || g_RestartGame_Enabled
            || g_AutoFarmMulti_Enabled || g_FarmWatchdog_Enabled
            || g_AutoMatch_Enabled
        g_Ctrl_ServerProfile.Enabled := !anyRunning
    }
}

JoinArr(arr, sep) {
    result := ""
    for i, v in arr {
        if (i > 1)
            result .= sep
        result .= v
    }
    return result
}

; --- 选项卡切换 ---
TabChange(*) {
    tabIdx := g_Tab.Value
    if (tabIdx == 3) {
        ; 切换到日志选项卡时刷新日志内容
        RefreshLogView()
    }
}

; --- 刷新日志视图 ---
RefreshLogView() {
    if (!g_LogEdit)
        return
    lines := Logger.GetLines(100)
    if (lines.Length > 0) {
        txt := ""
        for line in lines {
            if (Trim(line) != "")
                txt .= line "`r`n"
        }
        g_LogEdit.Value := txt
        ; 滚动到底部
        SendMessage(0x115, 7, 0, g_LogEdit.Hwnd)  ; WM_VSCROLL, SB_BOTTOM
    }
}

; --- GUI 尺寸变更 ---
GuiSize(guiObj, minMax, width, height) {
    if (g_Tab) {
        g_Tab.Move(, , width - 20, height - 140)
    }
    if (g_LogEdit) {
        g_LogEdit.Move(, , width - 40, height - 180)
    }
}

; --- GUI 关闭 ---
GuiClose(*) {
    Logger.Info("用户关闭 GUI, 正在退出...")
    CleanupAll()
    ExitApp(0)
}

; --- 托盘设置 ---
SetupTray() {
    TraySetIcon("shell32.dll", 18)
    A_IconTip := APP_NAME " v" APP_VERSION

    ; 托盘菜单
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("显示窗口", (*) => g_Gui.Show())
    tray.Add()
    tray.Add("自动刷图: " (g_AutoFarm_Enabled ? "停止" : "启动"), (*) => ToggleModule("AutoFarm"))
    tray.Add("重启建房: " (g_RestartGame_Enabled ? "停止" : "启动"), (*) => ToggleModule("RestartGame"))
    tray.Add("刷场次: " (g_AutoMatch_Enabled ? "停止" : "启动"), (*) => ToggleModule("AutoMatch"))
    tray.Add()
    tray.Add("退出", (*) => ExitApp(0))
}

; --- 全局清理 ---
CleanupAll() {
    Logger.Info("正在清理所有模块...")
    AutoFarm_Cleanup()
    RestartGame_Cleanup()
    FarmWatchdog_Cleanup()
    AutoFarmMulti_Cleanup()
    AutoMatch_Cleanup()
    OverlayManager.Cleanup()
    Logger.Flush()
}

; --- 退出回调 (由 OnExit 注册, 避免与内置函数同名) ---
ExitHandler(exitReason, exitCode) {
    CleanupAll()
}

; --- 错误回调 (由 OnError 注册) ---
ErrorHandler(thrown, mode) {
    msg := "未知错误"
    if (IsObject(thrown) && thrown.HasProp("Message"))
        msg := thrown.Message " (line " thrown.Line ", File: " thrown.File ")"
    else
        msg := String(thrown)
    Logger.Error("脚本错误: " msg)
    MsgBox("脚本错误:`n" msg, "SDGO工具脚本 错误", 16)
    return -1
}

; ======================================================================
; 入口点
; ======================================================================
Init()
