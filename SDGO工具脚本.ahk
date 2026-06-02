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
global APP_VERSION := "1.0.0"
global SCRIPT_DIR := A_ScriptDir
global g_DesktopW := 0
global g_DesktopH := 0
global g_ResolutionProfile := ""

; --- 加载库 ---
#Include "Lib\ConfigManager.ahk"
#Include "Lib\Logger.ahk"
#Include "Lib\GameUtils.ahk"

; --- 加载模块 ---
; (以下 4 个模块暂禁, 仅保留 RestartGame)
; #Include "Modules\AntiAFK.ahk"
#Include "Modules\AutoFarm.ahk"
; #Include "Modules\ComboMacros.ahk"
; #Include "Modules\DailyRewards.ahk"
#Include "Modules\RestartGame.ahk"
#Include "Modules\AutoFarmMulti.ahk"
#Include "Modules\FarmWatchdog.ahk"

; --- 暂禁模块桩定义 ---
; 这些桩允许主脚本在未加载模块时编译通过, 所有调用均为空操作
global g_AntiAFK_Enabled := false
global g_AntiAFK_Reconnecting := false
global g_AntiAFK_HeartbeatInterval := 300000
global g_ComboMacros_Enabled := false
global g_DailyRewards_Enabled := false
global g_DailyRewards_Running := false

AntiAFK_Init() => 0
AntiAFK_Start() => 0
AntiAFK_Stop() => 0
AntiAFK_Tick() => 0
AntiAFK_Cleanup() => 0
ComboMacros_Init() => 0
ComboMacros_Start() => 0
ComboMacros_Stop() => 0
ComboMacros_Tick() => 0
ComboMacros_Cleanup() => 0
ComboMacros_PlayMacro(slot) => 0
ComboMacros_StartRecording(slot) => 0
DailyRewards_Init() => 0
DailyRewards_Start() => 0
DailyRewards_Stop() => 0
DailyRewards_Tick() => 0
DailyRewards_Cleanup() => 0

; --- GUI 相关全局变量 ---
global g_Gui := 0
global g_Tab := 0
global g_LogEdit := 0
global g_StatusBar := 0
global g_GameStatus := "未检测"

; 模块状态控件句柄
global g_Ctrl_AntiAFK := 0
global g_Ctrl_AutoFarm := 0
global g_Ctrl_ComboMacros := 0
global g_Ctrl_DailyRewards := 0
global g_Ctrl_RestartGame := 0
global g_Ctrl_AutoFarmMulti := 0
global g_Ctrl_AutoFarmMulti_RunCount := 0
global g_Ctrl_FarmWatchdog := 0
global g_Ctrl_GameStatus := 0
global g_Ctrl_AutoFarm_RunCount := 0
global g_Ctrl_LogLevel := 0

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

    ; 注册退出/错误处理
    OnExit(ExitHandler, 1)
    OnError(ErrorHandler, 1)

    ; 读取热键修饰符
    g_HotkeyMod := ConfigManager.Read("General", "HotkeyModifier", "^!")

    ; 初始化 GameUtils
    if (GameUtils.Init()) {
        Logger.Info("游戏窗口已检测到 (hWnd=" GameUtils.g_hWnd ")")
    } else {
        Logger.Warn("未检测到游戏窗口 (gonline.exe)")
    }

    ; 初始化所有模块
    AntiAFK_Init()
    AutoFarm_Init()
    ComboMacros_Init()
    DailyRewards_Init()
    RestartGame_Init()
    FarmWatchdog_Init()
    AutoFarmMulti_Init()

    ; 注册全局热键
    RegisterGlobalHotkeys()
    ; 注册游戏内热键 (暂禁, 无 ComboMacros 模块)
    ; RegisterGameHotkeys()

    ; 构建并显示 GUI
    BuildGui()

    ; 设置托盘图标
    SetupTray()

    Logger.Info("初始化完成, GUI 已启动")
}

; --- 注册全局控制热键 ---
RegisterGlobalHotkeys() {
    mod := g_HotkeyMod  ; 默认 ^! (Ctrl+Alt)

    ; Ctrl+Alt+F1~F4: 模块开关
    ; (F1-F4 模块暂禁, 仅保留 F5 RestartGame)
    ; Hotkey(mod "F1", (*) => ToggleModule("AntiAFK"), "On")
    Hotkey(mod "F2", (*) => ToggleModule("AutoFarm"), "On")
    ; Hotkey(mod "F3", (*) => ToggleModule("ComboMacros"), "On")
    ; Hotkey(mod "F4", (*) => ToggleModule("DailyRewards"), "On")
    Hotkey(mod "F5", (*) => ToggleModule("RestartGame"), "On")
    Hotkey(mod "F6", (*) => ToggleModule("FarmWatchdog"), "On")
    Hotkey(mod "F7", (*) => ToggleModule("AutoFarmMulti"), "On")

    ; F12: 坐标捕获
    Hotkey("F12", (*) => CaptureCoords(), "On")

    ; Ctrl+Alt+R: 重载脚本
    Hotkey(mod "R", (*) => Reload(), "On")

    ; 紧急停止 (Esc)
    stopKey := ConfigManager.Read("General", "EmergencyStop", "Esc")
    Hotkey(mod . stopKey, (*) => EmergencyStop(), "On")
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

; --- 注册游戏内热键 (仅游戏窗口激活时) ---
RegisterGameHotkeys() {
    ; F1~F8: 连招宏播放 (使用 .Bind() 避免闭包变量捕获问题)
    loop 8 {
        HotIfWinActive("ahk_exe gonline.exe")
        Hotkey("F" A_Index, ComboMacros_PlayMacro.Bind(A_Index), "On")
        HotIfWinActive()  ; 重置条件
    }

    ; Ctrl+Alt+F1~F8: 连招宏录制
    loop 8 {
        HotIfWinActive("ahk_exe gonline.exe")
        Hotkey(g_HotkeyMod "F" A_Index, ComboMacros_StartRecording.Bind(A_Index), "On")
        HotIfWinActive()
    }
}

; --- 切换模块 ---
ToggleModule(module) {
    switch module {
    case "AntiAFK":
        if (g_AntiAFK_Enabled)
            AntiAFK_Stop()
        else
            AntiAFK_Start()
        UpdateGuiStatus()
    case "AutoFarm":
        if (g_AutoFarm_Enabled)
            AutoFarm_Stop()
        else
            AutoFarm_Start()
        UpdateGuiStatus()
    case "ComboMacros":
        if (g_ComboMacros_Enabled)
            ComboMacros_Stop()
        else
            ComboMacros_Start()
        UpdateGuiStatus()
    case "DailyRewards":
        if (g_DailyRewards_Enabled)
            DailyRewards_Stop()
        else
            DailyRewards_Start()
        UpdateGuiStatus()
    case "RestartGame":
        if (g_RestartGame_Enabled)
            RestartGame_Stop()
        else
            RestartGame_Start()
        UpdateGuiStatus()
    case "FarmWatchdog":
        if (g_FarmWatchdog_Enabled)
            FarmWatchdog_Stop()
        else
            FarmWatchdog_Start()
        UpdateGuiStatus()
    case "AutoFarmMulti":
        if (g_AutoFarmMulti_Enabled)
            AutoFarmMulti_Stop()
        else
            AutoFarmMulti_Start()
        UpdateGuiStatus()
    }
}

; --- 紧急停止 ---
EmergencyStop() {
    Logger.Warn("紧急停止!")
    AntiAFK_Stop()
    AutoFarm_Stop()
    ComboMacros_Stop()
    DailyRewards_Stop()
    RestartGame_Stop()
    FarmWatchdog_Stop()
    AutoFarmMulti_Stop()
    UpdateGuiStatus()
    ToolTip("⚠ 紧急停止 - 所有模块已停止", , , 2)
    SetTimer(() => ToolTip(, , , 2), -3000)
}

; --- 构建 GUI ---
BuildGui() {
    global g_Gui, g_Tab, g_LogEdit, g_StatusBar, g_Ctrl_RestartGame, g_Ctrl_LogLevel, g_HotkeyMod
    global g_Ctrl_AutoFarm, g_Ctrl_AutoFarm_RunCount
    global g_Ctrl_AutoFarmMulti, g_Ctrl_AutoFarmMulti_RunCount
    global g_Ctrl_FarmWatchdog, g_Ctrl_FarmWatchdog_RestartCount

    g_Gui := Gui("+Resize +MinSize500x400 +MaximizeBox", APP_NAME " v" APP_VERSION)
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

    ; (以下 4 个模块暂禁, 仅保留 RestartGame)
    ; 模块1: AntiAFK
    ; g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "防掉线 (AntiAFK)")
    ; g_Gui.Add("Text", "xp+20 yp+25 w120", "心跳间隔防踢 + 断线重登")
    ; btnAntiAFK := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAntiAFK", "启动")
    ; btnAntiAFK.OnEvent("Click", (*) => ToggleModule("AntiAFK"))
    ; g_Ctrl_AntiAFK := btnAntiAFK
    ;
    ; 模块2: AutoFarm (单人)
    g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "自动刷图-单人 (AutoFarm)")
    g_Gui.Add("Text", "xp+20 yp+25 w200", "检测开始→F5→战斗→结算→循环")
    runCount := g_Gui.Add("Text", "x300 yp-5 w70 vTxtRunCount", "局数: 0")
    g_Ctrl_AutoFarm_RunCount := runCount
    btnAutoFarm := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAutoFarm", "启动")
    btnAutoFarm.OnEvent("Click", (*) => ToggleModule("AutoFarm"))
    g_Ctrl_AutoFarm := btnAutoFarm

    ; 模块2b: AutoFarmMulti (多人)
    g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "自动刷图-多人 (AutoFarmMulti)")
    g_Gui.Add("Text", "xp+20 yp+25 w200", "检测开始→F5→战斗→结算→循环")
    runCountM := g_Gui.Add("Text", "x300 yp w70 vTxtRunCountM", "局数: 0")
    g_Ctrl_AutoFarmMulti_RunCount := runCountM
    btnAutoFarmM := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnAutoFarmM", "启动")
    btnAutoFarmM.OnEvent("Click", (*) => ToggleModule("AutoFarmMulti"))
    g_Ctrl_AutoFarmMulti := btnAutoFarmM
    ;
    ; 模块3: ComboMacros
    ; g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "连招宏 (ComboMacros)")
    ; g_Gui.Add("Text", "xp+20 yp+25 w250", "F1~F8 播放, Ctrl+Alt+F1~F8 录制")
    ; btnCombo := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnCombo", "启动")
    ; btnCombo.OnEvent("Click", (*) => ToggleModule("ComboMacros"))
    ; g_Ctrl_ComboMacros := btnCombo
    ;
    ; 模块4: DailyRewards
    ; g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "自动领奖 (DailyRewards)")
    ; g_Gui.Add("Text", "xp+20 yp+25 w250", "菜单导航 + 按钮检测, 一次性执行")
    ; btnDaily := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnDaily", "执行")
    ; btnDaily.OnEvent("Click", (*) => ToggleModule("DailyRewards"))
    ; g_Ctrl_DailyRewards := btnDaily

    ; 模块5: RestartGame
    g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "重启建房 (RestartGame)")
    g_Gui.Add("Text", "xp+20 yp+25 w250", "重启游戏 → 登录 → 创建任务房间")
    btnRestart := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnRestart", "启动")
    btnRestart.OnEvent("Click", (*) => ToggleModule("RestartGame"))
    g_Ctrl_RestartGame := btnRestart

    ; 模块6: FarmWatchdog
    g_Gui.Add("GroupBox", "x20 y+10 w460 h70", "看门狗 (FarmWatchdog)")
    g_Gui.Add("Text", "xp+20 yp+25 w200", "刷图停滞/游戏缺失 → 触发重启建房")
    restartCountW := g_Gui.Add("Text", "x300 yp-5 w70 vTxtRestartCountW", "重启: 0")
    g_Ctrl_FarmWatchdog_RestartCount := restartCountW
    btnWatch := g_Gui.Add("Button", "x380 yp-5 w80 h28 vBtnWatch", "启动")
    btnWatch.OnEvent("Click", (*) => ToggleModule("FarmWatchdog"))
    g_Ctrl_FarmWatchdog := btnWatch

    ; 紧急停止按钮
    btnStop := g_Gui.Add("Button", "x20 y+20 w100 h35 vBtnStop", "紧急停止 (Esc)")
    btnStop.OnEvent("Click", (*) => EmergencyStop())
    btnStop.SetFont("s10 bold", "Segoe UI")

    ; 底部热键说明
    g_Gui.SetFont("s8")
    g_Gui.Add("Text", "x140 yp+5 w340 h30", "快捷键: " g_HotkeyMod "F5=建房 F6=监控 | F12=坐标 | " g_HotkeyMod "R=重载 | " g_HotkeyMod "Esc=停止")

    ; ===== 选项卡2: 设置 =====
    g_Tab.UseTab(2)
    g_Gui.SetFont("s10 bold")
    g_Gui.Add("Text", "x20 y+10 w460 h30", "通用设置")
    g_Gui.SetFont("s9 norm")

    ; (心跳间隔设置暂禁, AntiAFK 模块未加载)
    ; g_Gui.Add("Text", "x40 y+15 w120", "心跳间隔 (秒):")
    ; editInterval := g_Gui.Add("Edit", "x+10 w80 vEditHeartbeat", g_AntiAFK_HeartbeatInterval // 1000)
    ; editInterval.OnEvent("Change", (*) => SaveSettings())

    ; (最大刷图次数设置暂禁, AutoFarm 模块未加载)
    ; g_Gui.Add("Text", "x40 y+10 w120", "最大刷图次数:")
    ; editMaxRuns := g_Gui.Add("Edit", "x+10 w80 vEditMaxRuns", g_AutoFarm_MaxRuns)
    ; editMaxRuns.OnEvent("Change", (*) => SaveSettings())

    ; 按键延迟范围
    g_Gui.Add("Text", "x40 y+10 w120", "按键延迟 (ms):")
    g_Gui.Add("Text", "x+5 w30", "最小")
    editKeyMin := g_Gui.Add("Edit", "x+5 w50 vEditKeyMin", GameUtils.g_KeyDelayMin)
    editKeyMin.OnEvent("Change", (*) => SaveSettings())
    g_Gui.Add("Text", "x+10 w30", "最大")
    editKeyMax := g_Gui.Add("Edit", "x+5 w50 vEditKeyMax", GameUtils.g_KeyDelayMax)
    editKeyMax.OnEvent("Change", (*) => SaveSettings())

    ; 日志级别
    g_Gui.Add("Text", "x40 y+10 w120", "日志级别:")
    ddlLog := g_Gui.Add("DropDownList", "x+10 w80 vDdlLogLevel Choose" GetLogLevelIndex(), ["DEBUG", "INFO", "WARN", "ERROR"])
    ddlLog.OnEvent("Change", (*) => SaveSettings())
    g_Ctrl_LogLevel := ddlLog

    ; 输入模式
    g_Gui.Add("Text", "x40 y+10 w120", "输入模式:")
    ddlInput := g_Gui.Add("DropDownList", "x+10 w120 vDdlInputMode Choose" (GameUtils.g_InputMode == "control" ? 1 : 2), ["ControlSend(后台)", "Send(前台)"])
    ddlInput.OnEvent("Change", (*) => SaveSettings())

    ; 看门狗设置 (刷图停滞/游戏缺失检测)
    g_Gui.Add("Text", "x40 y+10 w120", "触发持续(秒):")
    editWD := g_Gui.Add("Edit", "x+10 w50 vEditWatchDuration", g_FarmWatchdog_Duration)
    editWD.OnEvent("Change", (*) => SaveSettings())

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
    return "⏸ 游戏未运行 | 等待 gonline.exe..."
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
    global g_Gui, g_AntiAFK_HeartbeatInterval, g_AutoFarm_MaxRuns
    global g_FarmWatchdog_Duration

    saved := g_Gui.Submit(0)

    ; 保存心跳间隔
    if (saved.HasProp("EditHeartbeat") && saved.EditHeartbeat != "") {
        ConfigManager.Write("AntiAFK", "HeartbeatInterval", saved.EditHeartbeat)
        g_AntiAFK_HeartbeatInterval := Integer(saved.EditHeartbeat) * 1000
    }

    ; 保存最大刷图次数
    if (saved.HasProp("EditMaxRuns") && saved.EditMaxRuns != "") {
        ConfigManager.Write("AutoFarm", "MaxRuns", saved.EditMaxRuns)
        g_AutoFarm_MaxRuns := Integer(saved.EditMaxRuns)
    }

    ; 保存按键延迟
    if (saved.HasProp("EditKeyMin") && saved.EditKeyMin != "") {
        ConfigManager.Write("Game", "KeyDelayMin", saved.EditKeyMin)
        GameUtils.g_KeyDelayMin := Integer(saved.EditKeyMin)
    }
    if (saved.HasProp("EditKeyMax") && saved.EditKeyMax != "") {
        ConfigManager.Write("Game", "KeyDelayMax", saved.EditKeyMax)
        GameUtils.g_KeyDelayMax := Integer(saved.EditKeyMax)
    }

    ; 保存日志级别
    if (saved.HasProp("DdlLogLevel") && saved.DdlLogLevel != "") {
        ConfigManager.Write("Logging", "LogLevel", saved.DdlLogLevel)
        Logger.g_LogLevel := saved.DdlLogLevel
    }

    ; 保存输入模式
    if (saved.HasProp("DdlInputMode") && saved.DdlInputMode != "") {
        mode := InStr(saved.DdlInputMode, "Control") ? "control" : "setforeground"
        ConfigManager.Write("Game", "InputMode", mode)
        GameUtils.g_InputMode := mode
    }

    ; 保存看门狗持续秒数
    if (saved.HasProp("EditWatchDuration") && saved.EditWatchDuration != "") {
        ConfigManager.Write("FarmWatchdog", "Watch_Duration", saved.EditWatchDuration)
        g_FarmWatchdog_Duration := Integer(saved.EditWatchDuration)
    }
}

; --- GUI 定时器: 刷新状态 ---
GuiTick() {
    global g_Gui, g_Ctrl_AutoFarm_RunCount, g_AutoFarm_RunCount
    global g_Ctrl_AutoFarmMulti_RunCount, g_AutoFarmMulti_RunCount
    global g_Ctrl_FarmWatchdog_RestartCount, g_FarmWatchdog_RestartCount

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

    ; 调用各模块 Tick
    AntiAFK_Tick()
    AutoFarm_Tick()
    ComboMacros_Tick()
    DailyRewards_Tick()
    RestartGame_Tick()
    FarmWatchdog_Tick()
    AutoFarmMulti_Tick()

    UpdateGuiStatus()
}

; --- 更新 GUI 上的模块状态文本 ---
UpdateGuiStatus() {
    ; AntiAFK
    if (g_Ctrl_AntiAFK) {
        g_Ctrl_AntiAFK.Text := g_AntiAFK_Enabled ? "停止" : "启动"
        g_Ctrl_AntiAFK.Redraw()
    }
    ; AutoFarm
    if (g_Ctrl_AutoFarm) {
        g_Ctrl_AutoFarm.Text := g_AutoFarm_Enabled ? "停止" : "启动"
        g_Ctrl_AutoFarm.Redraw()
    }
    ; ComboMacros
    if (g_Ctrl_ComboMacros) {
        g_Ctrl_ComboMacros.Text := g_ComboMacros_Enabled ? "停止" : "启动"
        g_Ctrl_ComboMacros.Redraw()
    }
    ; DailyRewards
    if (g_Ctrl_DailyRewards) {
        g_Ctrl_DailyRewards.Text := g_DailyRewards_Running ? "执行中..." : "执行"
        g_Ctrl_DailyRewards.Redraw()
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
    ; 状态栏
    if (g_StatusBar) {
        parts := []
        if (g_AntiAFK_Enabled)
            parts.Push("防掉线:ON")
        if (g_AutoFarm_Enabled)
            parts.Push("刷图:ON")
        if (g_ComboMacros_Enabled)
            parts.Push("连招:ON")
        if (g_DailyRewards_Enabled)
            parts.Push("领奖:ON")
        if (g_RestartGame_Enabled)
            parts.Push("重启建房:ON")
        if (g_AutoFarmMulti_Enabled)
            parts.Push("刷图多人:ON")
        if (g_FarmWatchdog_Enabled)
            parts.Push("看门狗:ON")
        if (parts.Length == 0)
            parts.Push("空闲")
        g_StatusBar.SetText(JoinArr(parts, " | "))
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
    ; (防掉线/自动刷图暂禁)
    ; tray.Add("防掉线: " (g_AntiAFK_Enabled ? "停止" : "启动"), (*) => ToggleModule("AntiAFK"))
    tray.Add("自动刷图: " (g_AutoFarm_Enabled ? "停止" : "启动"), (*) => ToggleModule("AutoFarm"))
    tray.Add("重启建房: " (g_RestartGame_Enabled ? "停止" : "启动"), (*) => ToggleModule("RestartGame"))
    tray.Add()
    tray.Add("退出", (*) => ExitApp(0))
}

; --- 全局清理 ---
CleanupAll() {
    Logger.Info("正在清理所有模块...")
    AntiAFK_Cleanup()
    AutoFarm_Cleanup()
    ComboMacros_Cleanup()
    DailyRewards_Cleanup()
    RestartGame_Cleanup()
    FarmWatchdog_Cleanup()
    AutoFarmMulti_Cleanup()
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
