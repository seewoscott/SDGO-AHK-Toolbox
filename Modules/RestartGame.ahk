; RestartGame.ahk — 重启游戏 & 创建任务房间模块
; 状态机: 杀进程 → 启动 → 等待稳定 → 登录 → 导航菜单 → 创建房间 → 等待(循环)

global g_RestartGame_Enabled := false
global g_RestartGame_State := "IDLE"
global g_RestartGame_StateStartTime := 0
global g_RestartGame_LoopCount := 0
global g_RestartGame_MaxLoops := 0
global g_RestartGame_RetryCount := 0
global g_RestartGame_MaxRetries := 3
global g_RestartGame_Mode := "once"
global g_RestartGame_LoopDelay := 30000
global g_RestartGame_GamePath := ConfigManager.GamePath
global g_RestartGame_GameDir := ConfigManager.GameDir

global RESTART_STATE := Map(
    "IDLE", 0, "KILLING_PROCESS", 1, "LAUNCHING_GAME", 2,
    "WAITING_STABILIZE", 3, "LOGGING_IN", 4,
    "ROOM_CREATION", 5, "WAITING_IN_ROOM", 6,
    "TEARDOWN_TO_LOBBY", 7, "ERROR", 99
)
global RESTART_TIMEOUTS := Map()
global g_Nav_Coords := Map()

; 计时辅助
global g_PhaseStart := 0
RestartGame_PhaseStart(name) {
    global g_PhaseStart
    g_PhaseStart := A_TickCount
    Logger.Info("[开始] " name)
}
RestartGame_PhaseEnd(name) {
    elapsed := Round((A_TickCount - g_PhaseStart) / 1000, 1)
    Logger.Info("[完成] " name " — 耗时 " elapsed "s")
}

RestartGame_Init() {
    global g_RestartGame_Mode, g_RestartGame_MaxLoops, g_RestartGame_LoopDelay
    global g_RestartGame_MaxRetries, g_RestartGame_GamePath, g_RestartGame_GameDir
    global g_RestartGame_LoopCount, g_RestartGame_RetryCount, g_RestartGame_State
    global RESTART_TIMEOUTS, g_Nav_Coords
    static S := "RestartGame"

    g_RestartGame_Mode := ConfigManager.Read(S, "Mode", "once")
    g_RestartGame_MaxLoops := ConfigManager.Read(S, "MaxLoops", 0)
    g_RestartGame_LoopDelay := ConfigManager.Read(S, "LoopDelay", 30) * 1000
    g_RestartGame_MaxRetries := ConfigManager.Read(S, "MaxRetries", 3)
    g_RestartGame_GamePath := ConfigManager.GamePath
    g_RestartGame_GameDir := ConfigManager.GameDir

    RESTART_TIMEOUTS["KILLING_PROCESS"] := ConfigManager.Read(S, "Timeout_KillProcess", 15) * 1000
    RESTART_TIMEOUTS["LAUNCHING_GAME"] := ConfigManager.Read(S, "Timeout_LaunchGame", 60) * 1000
    RESTART_TIMEOUTS["WAITING_STABILIZE"] := ConfigManager.Read(S, "Timeout_Stabilize", 15) * 1000
    RESTART_TIMEOUTS["LOGGING_IN"] := ConfigManager.Read(S, "Timeout_Login", 60) * 1000

    g_Nav_Coords["StabilizeWait"] := ConfigManager.Read(S, "StabilizeWaitTime", 10000)
    g_RestartGame_LoopCount := 0
    g_RestartGame_RetryCount := 0
    g_RestartGame_State := "IDLE"

    Logger.Info("RestartGame 初始化完成 (模式=" g_RestartGame_Mode ")")
}

RestartGame_Start() {
    global g_RestartGame_Enabled, g_RestartGame_LoopCount, g_RestartGame_RetryCount, g_RestartGame_Mode
    global g_RoomCreation_Step, g_RoomCreation_Retries, g_UnknownCount
    g_RestartGame_Enabled := true
    g_RestartGame_LoopCount := 0
    g_RestartGame_RetryCount := 0
    g_RoomCreation_Step := 0
    g_RoomCreation_Retries := 0
    g_UnknownCount := 0
    RestartGame_PhaseStart("杀进程+启动+登录+建房")
    RestartGame_Transition("KILLING_PROCESS")
    return true
}

RestartGame_Stop() {
    global g_RestartGame_Enabled, g_RestartGame_State, g_RestartGame_LoopCount
    g_RestartGame_Enabled := false
    g_RestartGame_State := "IDLE"
    Logger.Info("RestartGame: 已停止")
}

RestartGame_Cleanup() {
    RestartGame_Stop()
}

; === 状态机核心 ===

RestartGame_Tick() {
    global g_RestartGame_Enabled, g_AntiAFK_Reconnecting
    if (!g_RestartGame_Enabled || g_AntiAFK_Reconnecting)
        return
    RestartGame_CheckTimeout()
    RestartGame_ProcessState()
}

RestartGame_Transition(newState) {
    global g_RestartGame_State, g_RestartGame_StateStartTime
    g_RestartGame_State := newState
    g_RestartGame_StateStartTime := A_TickCount
}

RestartGame_CheckTimeout() {
    global RESTART_TIMEOUTS, g_RestartGame_State, g_RestartGame_StateStartTime
    if (!RESTART_TIMEOUTS.Has(g_RestartGame_State))
        return
    elapsed := A_TickCount - g_RestartGame_StateStartTime
    if (elapsed > RESTART_TIMEOUTS[g_RestartGame_State]) {
        Logger.Error("RestartGame: 超时 " g_RestartGame_State " (" Round(elapsed/1000) "s)")
        RestartGame_Transition("ERROR")
    }
}

RestartGame_ProcessState() {
    global g_RestartGame_State
    switch g_RestartGame_State {
    case "KILLING_PROCESS":   RestartGame_DoKillProcess()
    case "LAUNCHING_GAME":    RestartGame_DoLaunchGame()
    case "WAITING_STABILIZE": RestartGame_DoWaitStabilize()
    case "LOGGING_IN":        RestartGame_DoLogin()
    case "ROOM_CREATION":     RestartGame_DoRoomCreation()
    case "WAITING_IN_ROOM":   RestartGame_DoWaitInRoom()
    case "TEARDOWN_TO_LOBBY": RestartGame_DoTeardownToLobby()
    case "ERROR":             RestartGame_DoErrorRecovery()
    }
}

; === KILLING_PROCESS ===
RestartGame_DoKillProcess() {
    exeName := ConfigManager.GameExe
    tier := ""
    if (WinExist("ahk_exe " exeName)) {
        WinKill("ahk_exe " exeName)
        Sleep(2000)
        tier := "WinKill"
    }
    if (ProcessExist(exeName)) {
        RunWait("taskkill /F /IM " exeName, , "Hide")
        Sleep(3000)
        tier := "taskkill /F"
    }
    if (ProcessExist(exeName)) {
        RunWait("taskkill /F /T /IM " exeName, , "Hide")
        Sleep(5000)
        tier := "taskkill /F /T"
    }
    if (ProcessExist(exeName)) {
        Logger.Error("RestartGame: 杀进程失败")
        RestartGame_Transition("ERROR")
        return
    }
    Logger.Debug("[杀进程] " tier " 成功")
    Sleep(3000)
    RestartGame_Transition("LAUNCHING_GAME")
}

; === LAUNCHING_GAME ===
RestartGame_DoLaunchGame() {
    global g_RestartGame_GamePath, g_RestartGame_GameDir
    if (!FileExist(g_RestartGame_GamePath)) {
        Logger.Error("RestartGame: 启动器不存在")
        RestartGame_Transition("ERROR")
        return
    }
    try {
        Run(g_RestartGame_GamePath, g_RestartGame_GameDir, , &pid)
    } catch as e {
        Logger.Error("RestartGame: 启动失败 " e.Message)
        RestartGame_Transition("ERROR")
        return
    }

    Sleep(ConfigManager.Read("RestartGame", "Launcher_WaitTime", 5) * 1000)

    ; 点击進入游戲
    btnX := ConfigManager.ReadCoord("RestartGame", "Launcher_Button_X", 2126)
    btnY := ConfigManager.ReadCoord("RestartGame", "Launcher_Button_Y", 997)
    hLauncher := WinExist("ahk_exe " ConfigManager.LauncherExe)
    if (hLauncher) {
        WinActivate(hLauncher)
        WinWaitActive(hLauncher, , 3)
        Sleep(500)
        CoordMode "Mouse", "Client"
        Loop 3 {
            Click(btnX, btnY)
            Sleep(800)
        }
    }
    Sleep(2000)

    exeName := ConfigManager.GameExe
    if (!GameUtils.WaitFor(ObjBindMethod(GameUtils, "IsGameRunning"), 60000, 1000)) {
        Logger.Error("RestartGame: 等待 gonline.exe 超时")
        RestartGame_Transition("ERROR")
        return
    }
    GameUtils.RefreshWindow()
    Logger.Info("[启动] SDGO_Launcher PID=" pid)
    RestartGame_Transition("WAITING_STABILIZE")
}

; === WAITING_STABILIZE ===
RestartGame_DoWaitStabilize() {
    global g_Nav_Coords, g_RestartGame_StateStartTime
    stabilizeWait := g_Nav_Coords.Get("StabilizeWait", 10000)
    if (A_TickCount - g_RestartGame_StateStartTime >= stabilizeWait)
        RestartGame_Transition("LOGGING_IN")
}

; === LOGGING_IN ===
RestartGame_DoLogin() {
    if (!GameUtils.DoLogin()) {
        Logger.Error("RestartGame: 登录失败")
        RestartGame_Transition("ERROR")
        return
    }
    Sleep(5000)
    RestartGame_Transition("ROOM_CREATION")
}

; === 视觉状态机: 建房 (ImageSearch 整图比对) ===
global ROOM_IMAGES := Map(
    "LOBBY",       A_ScriptDir "\Data\Images\lobby.png",
    "CREATE_ROOM", A_ScriptDir "\Data\Images\create_room.png",
    "IN_ROOM",     A_ScriptDir "\Data\Images\in_room.png"
)
global g_RoomCreation_Step := 0
global g_RoomCreation_Retries := 0
global g_StepTimer := 0
global g_UnknownCount := 0

RestartGame_DetectScene(target := "", retries := 1) {
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_exe " ConfigManager.GameExe)
    if (wx == "" || ww == 0) {
        Logger.Info("[检测] WinGetPos 失败, wx=" wx " ww=" ww)
        return "UNKNOWN"
    }
    Loop retries {
        for state, imgPath in ROOM_IMAGES {
            ; 如果指定了 target, 只搜这一张
            if (target != "" && state != target)
                continue
            resolvedPath := GameUtils.ResolveImagePath(imgPath)
            if (!FileExist(resolvedPath))
                continue
            if (ImageSearch(&px, &py, wx, wy, wx + ww, wy + wh, "*120 " resolvedPath)) {
                if (retries > 1 && A_Index > 1)
                    Logger.Debug("[检测] " state " ✓ (第" A_Index "次)")
                return state
            }
        }
        if (retries > 1) {
            Logger.Debug("[检测] " target " 失败 (第" A_Index "/" retries "次)")
            Sleep(500)
        }
    }
    return "UNKNOWN"
}

RestartGame_StepLog(step, action, scene, retry, elapsed := "") {
    extra := retry > 0 ? " (重试" retry "/3)" : ""
    timeStr := elapsed != "" ? " — 耗时 " Round(elapsed/1000, 1) "s" : ""
    Logger.Debug("[Step" step "-" action "] 视觉: " scene . extra . timeStr)
}

RestartGame_DoRoomCreation() {
    global g_RestartGame_LoopCount
    global g_RoomCreation_Step, g_RoomCreation_Retries, g_StepTimer, g_UnknownCount

    createBtnX := ConfigManager.ReadCoord("RestartGame", "Room_CreateBtn_X", 512)
    createBtnY := ConfigManager.ReadCoord("RestartGame", "Room_CreateBtn_Y", 500)
    nameFieldX := ConfigManager.ReadCoord("RestartGame", "Room_NameField_X", 512)
    nameFieldY := ConfigManager.ReadCoord("RestartGame", "Room_NameField_Y", 500)
    confirmBtnX := ConfigManager.ReadCoord("RestartGame", "Room_ConfirmBtn_X", 512)
    confirmBtnY := ConfigManager.ReadCoord("RestartGame", "Room_ConfirmBtn_Y", 500)

    CoordMode "Mouse", "Client"

    ; === Step 0: 等 LOBBY → 点击"建立房间" → 验证 CREATE_ROOM ===
    if (g_RoomCreation_Step == 0) {
        scene := RestartGame_DetectScene("LOBBY", 1)
        if (scene != "LOBBY") {
            g_UnknownCount++
            if (g_UnknownCount >= 5) {
                Logger.Error("[建房] 等待大厅超时, 停止")
                RestartGame_Transition("ERROR")
            }
            return
        }
        g_UnknownCount := 0
        g_RoomCreation_Retries++
        if (g_RoomCreation_Retries > 3) {
            Logger.Error("[Step0-失败] 点击建立房间 3 次未进入建房界面")
            RestartGame_Transition("ERROR")
            return
        }
        RestartGame_StepLog(0, "执行", "LOBBY ✓ 点击建立房间", g_RoomCreation_Retries)
        MouseMove(createBtnX, createBtnY)
        Sleep(500)
        Send "{LButton Down}"
        Sleep(200)
        Send "{LButton Up}"
        Sleep(3000)
        newScene := RestartGame_DetectScene("CREATE_ROOM", 3)
        if (newScene == "CREATE_ROOM") {
            RestartGame_StepLog(0, "完成", "LOBBY → CREATE_ROOM ✓", 0)
            g_RoomCreation_Step := 1
            g_RoomCreation_Retries := 0
        }
        return
    }

    ; === Step 1: 选择任务 (不扫描, 直接执行) ===
    if (g_RoomCreation_Step == 1) {
        taskSelectX := ConfigManager.ReadCoord("RestartGame", "Room_TaskSelect_X", 512)
        taskSelectY := ConfigManager.ReadCoord("RestartGame", "Room_TaskSelect_Y", 500)
        RestartGame_StepLog(1, "开始", "选择任务(连点6次)", 0)
        g_StepTimer := A_TickCount
        Loop 6 {
            Logger.Debug("[Step1] 任务点击 " A_Index "/6 (" taskSelectX "," taskSelectY ")")
            MouseMove(taskSelectX, taskSelectY)
            Sleep(500)
            Send "{LButton Down}"
            Sleep(200)
            Send "{LButton Up}"
            Sleep(1000)
        }
        RestartGame_StepLog(1, "完成", "任务已选择", 0)
        g_RoomCreation_Step := 2
        Sleep(1000)
        return
    }

    ; === Step 2: 填写房间名 (不扫描, 直接执行) ===
    if (g_RoomCreation_Step == 2) {
        RestartGame_StepLog(2, "开始", "填写房间名", 0)
        g_StepTimer := A_TickCount
        MouseMove(nameFieldX, nameFieldY)
        Sleep(300), Click(), Sleep(500)
        A_Clipboard := ConfigManager.RoomName
        SendInput("^a"), Sleep(200)
        SendInput("{Backspace}"), Sleep(200)
        SendInput("^v"), Sleep(300)
        RestartGame_StepLog(2, "完成", "房间名已填写", 0)
        g_RoomCreation_Step := 3
        g_RoomCreation_Retries := 0
        Sleep(1000)
        return
    }

    ; === Step 3: 点击确认 → 验证 IN_ROOM ===
    if (g_RoomCreation_Step == 3) {
        g_RoomCreation_Retries++
        if (g_RoomCreation_Retries > 3) {
            Logger.Error("[Step3-失败] 点击确认 3 次未进入房间")
            RestartGame_Transition("ERROR")
            return
        }
        RestartGame_StepLog(3, "执行", "点击确认", g_RoomCreation_Retries)
        g_StepTimer := A_TickCount
        Loop 5 {
            MouseMove(confirmBtnX, confirmBtnY)
            Sleep(200), Click(), Sleep(400)
        }
        ControlClick("x" confirmBtnX " y" confirmBtnY, "ahk_exe " ConfigManager.GameExe)
        Sleep(4000)
        newScene := RestartGame_DetectScene("IN_ROOM", 3)
        if (newScene == "IN_ROOM") {
            RestartGame_StepLog(3, "完成", "CREATE_ROOM → IN_ROOM ✓", 0)
            g_RoomCreation_Step := 4
            g_RoomCreation_Retries := 0
        }
        return
    }

    ; === Step 4: 完成 ===
    if (g_RoomCreation_Step == 4) {
        RestartGame_StepLog(4, "完成", "IN_ROOM ✓ 建房流程结束", 0)
        g_RestartGame_LoopCount++
        g_RoomCreation_Step := 0
        RestartGame_Transition("WAITING_IN_ROOM")
    }
}

; === WAITING_IN_ROOM ===
RestartGame_DoWaitInRoom() {
    global g_RestartGame_Mode, g_RestartGame_MaxLoops, g_RestartGame_LoopCount
    global g_RestartGame_StateStartTime, g_RestartGame_LoopDelay
    if (g_RestartGame_Mode == "once" || (g_RestartGame_MaxLoops > 0 && g_RestartGame_LoopCount >= g_RestartGame_MaxLoops)) {
        Logger.Info("[完成] 建房流程 — 共 " g_RestartGame_LoopCount " 次")
        RestartGame_Stop()
        return
    }
    if (A_TickCount - g_RestartGame_StateStartTime >= g_RestartGame_LoopDelay)
        RestartGame_Transition("TEARDOWN_TO_LOBBY")
}

; === TEARDOWN_TO_LOBBY ===
RestartGame_DoTeardownToLobby() {
    if (!GameUtils.ActivateGame()) {
        RestartGame_Transition("ERROR")
        return
    }
    Loop 5 {
        GameUtils.SendGameKeyOnce("Escape", 1000)
    }
    Sleep(3000)
    RestartGame_Transition("CREATING_ROOM")
}

; === ERROR ===
RestartGame_DoErrorRecovery() {
    Logger.Error("RestartGame: 错误, 停止")
    RestartGame_Stop()
}
