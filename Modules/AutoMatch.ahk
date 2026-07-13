; AutoMatch.ahk - room identity, ready/start handling and dual-weapon combat loop.

class AutoMatchLockSweep {
    static InitialDelayMs := 30
    static IntervalMs := 50
    static StepCount := 20
    static DeltaX := 2
    static SettleMs := 30
}

class AutoMatchPolicy {
    static RoomConfirmFrames := 3
    static LockLossFrames := 3
    static PrimaryShotOffsets := [0, 3000, 6000]

    static ShouldStopOutput(outputStart, now, durationSeconds) {
        return outputStart > 0 && now - outputStart >= durationSeconds * 1000
    }

    static IsPrimaryShotDue(shotCount, elapsedMs) {
        return shotCount < this.PrimaryShotOffsets.Length
            && elapsedMs >= this.PrimaryShotOffsets[shotCount + 1]
    }

    static ShouldFallbackFromLock(failureCount) {
        return failureCount >= this.LockLossFrames
    }
}

global g_AutoMatch_Enabled := false
global g_AutoMatch_RunCount := 0
global g_AutoMatch_State := "WAIT_START"
global g_AutoMatch_StateStart := 0
global g_AutoMatch_MaxRuns := 0
global g_AutoMatch_SearchCache := {LastX: -1, LastY: -1, MissCount: 0}
global g_AutoMatch_CombatCache := {LastX: -1, LastY: -1, MissCount: 0}

global g_AutoMatch_CombatSub := ""
global g_AutoMatch_CombatStart := 0
global g_AutoMatch_OutputStart := 0
global g_AutoMatch_PrimaryShotCount := 0
global g_AutoMatch_PrimaryStart := 0
global g_AutoMatch_LockFailureCount := 0
global g_AutoMatch_AttackStopped := false

global g_AutoMatch_ReadyTimeout := 5
global g_AutoMatch_PrimaryWeaponKey := "1"
global g_AutoMatch_LockWeaponKey := "2"
global g_AutoMatch_AttackDuration := 60
global g_AutoMatch_ResultColor := 0x25B3D1

global g_AutoMatch_RoomPendingKey := ""
global g_AutoMatch_RoomPendingCount := 0
global g_AutoMatch_RoomStableKey := ""
global g_AutoMatch_RoomStableSlot := 0
global g_AutoMatch_RoomStableState := "UNKNOWN"
global g_AutoMatch_RoomAmbiguousCount := 0
global g_AutoMatch_LastRoomAction := 0
global g_AutoMatch_LastRoomWarn := 0
global g_AutoMatch_LastDetectionWarn := 0

global g_AutoMatch_SweepActive := false
global g_AutoMatch_SweepStep := 0
global g_AutoMatch_SweepX := 0
global g_AutoMatch_SweepY := 0
global g_AutoMatch_SweepCompletedAt := 0

AutoMatch_Init() {
    global g_AutoMatch_MaxRuns, g_AutoMatch_ReadyTimeout
    global g_AutoMatch_PrimaryWeaponKey, g_AutoMatch_LockWeaponKey
    global g_AutoMatch_AttackDuration, g_AutoMatch_ResultColor

    g_AutoMatch_MaxRuns := ConfigManager.Read("AutoMatch", "MaxRuns", 0)
    g_AutoMatch_ReadyTimeout := ConfigManager.Read("AutoMatch", "ReadyTimeout", 5)
    g_AutoMatch_PrimaryWeaponKey := String(ConfigManager.Read("AutoMatch", "PrimaryWeaponKey", "1"))
    g_AutoMatch_LockWeaponKey := String(ConfigManager.Read("AutoMatch", "LockWeaponKey", "2"))
    g_AutoMatch_AttackDuration := ConfigManager.Read("AutoMatch", "AttackDuration", 60)
    g_AutoMatch_ResultColor := ConfigManager.Read("AutoMatch", "ResultColor", 0x25B3D1)

    Logger.Info("AutoMatch(刷场次) 模块初始化完成 | MaxRuns=" g_AutoMatch_MaxRuns)
}

AutoMatch_Start() {
    global g_AutoMatch_Enabled, g_AutoMatch_RunCount, g_AutoMatch_State, g_AutoMatch_StateStart
    global g_AutoMatch_MaxRuns
    g_AutoMatch_Enabled := true
    g_AutoMatch_RunCount := 0
    g_AutoMatch_State := "WAIT_START"
    g_AutoMatch_StateStart := A_TickCount
    AutoMatch_ResetRoomIdentity()
    AutoMatch_ResetCombat()
    Logger.Info("AutoMatch: 已启动 | MaxRuns=" g_AutoMatch_MaxRuns)
    return true
}

AutoMatch_Stop() {
    global g_AutoMatch_Enabled, g_AutoMatch_RunCount
    g_AutoMatch_Enabled := false
    AutoMatch_StopSweep()
    SendInput("{LButton up}{RButton up}")
    Logger.Info("AutoMatch: 已停止 (共 " g_AutoMatch_RunCount " 场)")
}

AutoMatch_Cleanup() {
    AutoMatch_Stop()
}

AutoMatch_ResetRoomIdentity() {
    global g_AutoMatch_RoomPendingKey, g_AutoMatch_RoomPendingCount
    global g_AutoMatch_RoomStableKey, g_AutoMatch_RoomStableSlot, g_AutoMatch_RoomStableState
    global g_AutoMatch_RoomAmbiguousCount, g_AutoMatch_LastRoomAction
    global g_AutoMatch_SearchCache, g_AutoMatch_CombatCache
    g_AutoMatch_RoomPendingKey := ""
    g_AutoMatch_RoomPendingCount := 0
    g_AutoMatch_RoomStableKey := ""
    g_AutoMatch_RoomStableSlot := 0
    g_AutoMatch_RoomStableState := "UNKNOWN"
    g_AutoMatch_RoomAmbiguousCount := 0
    g_AutoMatch_LastRoomAction := 0
    g_AutoMatch_SearchCache.LastX := -1, g_AutoMatch_SearchCache.LastY := -1
    g_AutoMatch_SearchCache.MissCount := 0
    g_AutoMatch_CombatCache.LastX := -1, g_AutoMatch_CombatCache.LastY := -1
    g_AutoMatch_CombatCache.MissCount := 0
}

AutoMatch_ResetCombat() {
    global g_AutoMatch_CombatSub, g_AutoMatch_CombatStart, g_AutoMatch_OutputStart
    global g_AutoMatch_PrimaryShotCount, g_AutoMatch_PrimaryStart
    global g_AutoMatch_LockFailureCount, g_AutoMatch_AttackStopped
    AutoMatch_StopSweep()
    g_AutoMatch_CombatSub := ""
    g_AutoMatch_CombatStart := 0
    g_AutoMatch_OutputStart := 0
    g_AutoMatch_PrimaryShotCount := 0
    g_AutoMatch_PrimaryStart := 0
    g_AutoMatch_LockFailureCount := 0
    g_AutoMatch_AttackStopped := false
}

AutoMatch_Tick() {
    global g_AutoMatch_Enabled, g_AutoMatch_State, g_AutoMatch_StateStart
    global g_AutoMatch_CombatSub
    global g_AutoMatch_OutputStart, g_AutoMatch_AttackDuration, g_AutoMatch_AttackStopped
    static s_GameMissingWarned := false
    static s_WindowMissingWarned := false

    if (!g_AutoMatch_Enabled)
        return
    if (!GameUtils.IsGameRunning()) {
        if (!s_GameMissingWarned) {
            Logger.Warn("[刷场次] 游戏进程未检测到, 等待中...")
            s_GameMissingWarned := true
        }
        AutoMatch_StopSweep()
        SendInput("{LButton up}{RButton up}")
        if (g_AutoMatch_State == "COMBAT" && g_AutoMatch_CombatSub == "LOCK_SWEEP")
            AutoMatch_SetCombatSub("SELECT_W2")
        return
    }
    s_GameMissingWarned := false

    windowRect := GameUtils.GetWindowRect()
    clientRect := GameUtils.GetClientRect()
    if (!windowRect || !clientRect) {
        if (!s_WindowMissingWarned) {
            Logger.Warn("[刷场次] 游戏窗口或客户区未获取到, 等待中...")
            s_WindowMissingWarned := true
        }
        return
    }
    s_WindowMissingWarned := false

    switch g_AutoMatch_State {
    case "WAIT_START":
        AutoMatch_TickRoom(windowRect, clientRect)

    case "WAIT_LOAD":
        if (AutoMatch_FindCombatUi(windowRect))
            AutoMatch_EnterCombat()

    case "COMBAT":
        if (!g_AutoMatch_AttackStopped && AutoMatchPolicy.ShouldStopOutput(
            g_AutoMatch_OutputStart, A_TickCount, g_AutoMatch_AttackDuration)) {
            Logger.Warn("[刷场次] 战斗输出达到" g_AutoMatch_AttackDuration "秒, 停止攻击并等待结算")
            AutoMatch_StopSweep()
            SendInput("{LButton up}{RButton up}")
            g_AutoMatch_AttackStopped := true
            AutoMatch_SetCombatSub("WAIT_RESULT")
        }
        if (g_AutoMatch_CombatSub == "WAIT_RESULT") {
            if (AutoMatch_CheckResult(clientRect))
                AutoMatch_EnterResult()
            return
        }
        AutoMatch_TickCombat(clientRect)

    case "RESULT":
        AutoMatch_TickResult()
    }
}

AutoMatch_TickRoom(windowRect, clientRect) {
    global g_AutoMatch_SearchCache, g_AutoMatch_LastRoomAction, g_AutoMatch_ReadyTimeout
    global g_AutoMatch_RoomStableSlot, g_AutoMatch_RoomStableState

    if (AutoMatch_FindCombatUi(windowRect)) {
        AutoMatch_EnterCombat()
        return
    }

    gx := windowRect.x, gy := windowRect.y, gw := windowRect.w, gh := windowRect.h
    startFound := GameUtils.SmartSearch(&fx, &fy,
        "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\start_btn.png"),
        gx + gw/2, gy + gh/2, gx + gw, gy + gh, g_AutoMatch_SearchCache)
    if (!startFound)
        return

    result := RoomSelfDetector.Detect(clientRect)
    if (!AutoMatch_UpdateRoomIdentity(result)) {
        if (result.status != "OK")
            AutoMatch_LogRoomProblem(result)
        return
    }

    interval := Max(1, g_AutoMatch_ReadyTimeout) * 1000
    if (g_AutoMatch_RoomStableState == "READY") {
        Logger.Info("[刷场次] 本人槽位" g_AutoMatch_RoomStableSlot "已 Ready, 等待加载")
        AutoMatch_SetState("WAIT_LOAD")
        return
    }

    if (A_TickCount - g_AutoMatch_LastRoomAction < interval && g_AutoMatch_LastRoomAction > 0)
        return

    GameUtils.ActivateGame()
    if (g_AutoMatch_RoomStableState == "NOT_READY") {
        Logger.Info("[刷场次] 本人槽位" g_AutoMatch_RoomStableSlot "未 Ready, 按 F5")
        SendInput("{F5}")
        g_AutoMatch_LastRoomAction := A_TickCount
    } else if (g_AutoMatch_RoomStableState == "MASTER") {
        Logger.Info("[刷场次] 本人是房主, 顺序发送 F5 → Enter")
        SendInput("{F5}")
        Sleep(100)
        SendInput("{Enter}")
        g_AutoMatch_LastRoomAction := A_TickCount
    }
}

AutoMatch_UpdateRoomIdentity(result) {
    global g_AutoMatch_RoomPendingKey, g_AutoMatch_RoomPendingCount
    global g_AutoMatch_RoomStableKey, g_AutoMatch_RoomStableSlot, g_AutoMatch_RoomStableState
    global g_AutoMatch_RoomAmbiguousCount

    if (result.status != "OK") {
        g_AutoMatch_RoomPendingKey := ""
        g_AutoMatch_RoomPendingCount := 0
        g_AutoMatch_RoomAmbiguousCount++
        if (g_AutoMatch_RoomAmbiguousCount >= AutoMatchPolicy.RoomConfirmFrames) {
            g_AutoMatch_RoomStableKey := ""
            g_AutoMatch_RoomStableSlot := 0
            g_AutoMatch_RoomStableState := "UNKNOWN"
        }
        return false
    }

    g_AutoMatch_RoomAmbiguousCount := 0
    candidateKey := result.self_slot_index ":" result.self_state
    if (candidateKey == g_AutoMatch_RoomStableKey)
        return true
    if (candidateKey != g_AutoMatch_RoomPendingKey) {
        g_AutoMatch_RoomPendingKey := candidateKey
        g_AutoMatch_RoomPendingCount := 1
        return false
    }
    g_AutoMatch_RoomPendingCount++
    if (g_AutoMatch_RoomPendingCount < AutoMatchPolicy.RoomConfirmFrames)
        return false

    g_AutoMatch_RoomStableKey := candidateKey
    g_AutoMatch_RoomStableSlot := result.self_slot_index
    g_AutoMatch_RoomStableState := result.self_state
    g_AutoMatch_RoomPendingKey := ""
    g_AutoMatch_RoomPendingCount := 0
    Logger.Info("[刷场次] 本人槽位确认: " g_AutoMatch_RoomStableSlot
        " | 状态=" g_AutoMatch_RoomStableState)
    return true
}

AutoMatch_LogRoomProblem(result) {
    global g_AutoMatch_LastRoomWarn
    if (g_AutoMatch_LastRoomWarn > 0 && A_TickCount - g_AutoMatch_LastRoomWarn < 10000)
        return
    logged := false
    if (result.status == "ERROR") {
        Logger.Warn("[刷场次] 房间本人检测失败, 暂不发送按键: " result.error)
        logged := true
    } else if (result.status == "UNKNOWN") {
        Logger.Warn("[刷场次] 暂无法确认本人槽位, 暂不发送按键")
        logged := true
    }
    if (logged)
        g_AutoMatch_LastRoomWarn := A_TickCount
}

AutoMatch_FindCombatUi(windowRect) {
    global g_AutoMatch_CombatCache
    gx := windowRect.x, gy := windowRect.y, gw := windowRect.w, gh := windowRect.h
    return GameUtils.SmartSearch(&fx, &fy,
        "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\combat_ui.png"),
        gx + gw*3/4, gy, gx + gw, gy + gh/4, g_AutoMatch_CombatCache)
}

AutoMatch_EnterCombat() {
    global g_AutoMatch_State, g_AutoMatch_StateStart, g_AutoMatch_CombatStart
    AutoMatch_ResetCombat()
    g_AutoMatch_State := "COMBAT"
    g_AutoMatch_StateStart := A_TickCount
    g_AutoMatch_CombatStart := A_TickCount
    AutoMatch_SetCombatSub("SELECT_W2")
    Logger.Info("[刷场次] 检测到战斗 UI, 进入双武器循环")
}

AutoMatch_TickCombat(clientRect) {
    global g_AutoMatch_CombatSub, g_AutoMatch_SweepCompletedAt
    global g_AutoMatch_PrimaryShotCount, g_AutoMatch_PrimaryStart
    global g_AutoMatch_LockFailureCount

    switch g_AutoMatch_CombatSub {
    case "SELECT_W2":
        AutoMatch_BeginLockSweep()

    case "LOCK_SWEEP":
        return

    case "CHECK_TARGET":
        if (A_TickCount - g_AutoMatch_SweepCompletedAt < AutoMatchLockSweep.SettleMs)
            return
        result := CombatTargetDetector.Detect(clientRect)
        if (AutoMatch_IsDetectionError(result))
            return
        if (result.lock_state == "LOCKED" && result.target_presence == "PRESENT") {
            Logger.Info("[刷场次] 武器二已锁定目标, 进入持续攻击")
            SendInput("{RButton down}")
            g_AutoMatch_LockFailureCount := 0
            AutoMatch_SetCombatSub("LOCKED_ATTACK")
        } else {
            Logger.Debug("[刷场次] 武器二未锁定或无目标, 切武器一")
            AutoMatch_BeginPrimaryAttack()
        }

    case "PRIMARY_ATTACK":
        elapsed := A_TickCount - g_AutoMatch_PrimaryStart
        if (AutoMatchPolicy.IsPrimaryShotDue(g_AutoMatch_PrimaryShotCount, elapsed))
            AutoMatch_FirePrimaryShot()
        if (g_AutoMatch_PrimaryShotCount >= AutoMatchPolicy.PrimaryShotOffsets.Length)
            AutoMatch_BeginLockSweep()

    case "LOCKED_ATTACK":
        result := CombatTargetDetector.Detect(clientRect)
        if (AutoMatch_IsDetectionError(result))
            return
        if (result.lock_state == "LOCKED" && result.target_presence == "PRESENT") {
            g_AutoMatch_LockFailureCount := 0
            AutoMatch_ClickLeft()
        } else {
            g_AutoMatch_LockFailureCount++
            Logger.Debug("[刷场次] 锁定/目标复检失败 " g_AutoMatch_LockFailureCount
                "/" AutoMatchPolicy.LockLossFrames)
            if (AutoMatchPolicy.ShouldFallbackFromLock(g_AutoMatch_LockFailureCount)) {
                SendInput("{RButton up}")
                AutoMatch_BeginPrimaryAttack()
            }
        }
    }
}

AutoMatch_BeginLockSweep() {
    global g_AutoMatch_LockWeaponKey
    global g_AutoMatch_SweepActive, g_AutoMatch_SweepStep
    global g_AutoMatch_SweepX, g_AutoMatch_SweepY, g_AutoMatch_SweepCompletedAt

    AutoMatch_StopSweep()
    GameUtils.ActivateGame()
    SendInput("{" g_AutoMatch_LockWeaponKey "}")
    CoordMode("Mouse", "Screen")
    SendInput("{RButton down}")
    Sleep(AutoMatchLockSweep.InitialDelayMs)
    MouseGetPos(&sx, &sy)
    g_AutoMatch_SweepX := sx
    g_AutoMatch_SweepY := sy
    g_AutoMatch_SweepStep := 0
    g_AutoMatch_SweepCompletedAt := 0
    g_AutoMatch_SweepActive := true
    AutoMatch_SetCombatSub("LOCK_SWEEP")
    SetTimer(AutoMatch_LockSweepTimer, AutoMatchLockSweep.IntervalMs)
}

AutoMatch_LockSweepTimer() {
    global g_AutoMatch_Enabled, g_AutoMatch_State, g_AutoMatch_CombatSub
    global g_AutoMatch_SweepActive, g_AutoMatch_SweepStep
    global g_AutoMatch_SweepX, g_AutoMatch_SweepY, g_AutoMatch_SweepCompletedAt

    if (!g_AutoMatch_Enabled || g_AutoMatch_State != "COMBAT"
        || g_AutoMatch_CombatSub != "LOCK_SWEEP" || !GameUtils.IsGameRunning()) {
        shouldRestart := g_AutoMatch_Enabled && g_AutoMatch_State == "COMBAT"
            && g_AutoMatch_CombatSub == "LOCK_SWEEP"
        AutoMatch_StopSweep()
        if (shouldRestart)
            AutoMatch_SetCombatSub("SELECT_W2")
        return
    }

    CoordMode("Mouse", "Screen")
    g_AutoMatch_SweepX += AutoMatchLockSweep.DeltaX
    MouseMove(g_AutoMatch_SweepX, g_AutoMatch_SweepY, 0)
    g_AutoMatch_SweepStep++
    if (g_AutoMatch_SweepStep >= AutoMatchLockSweep.StepCount) {
        SetTimer(AutoMatch_LockSweepTimer, 0)
        g_AutoMatch_SweepActive := false
        SendInput("{RButton up}")
        g_AutoMatch_SweepCompletedAt := A_TickCount
        AutoMatch_SetCombatSub("CHECK_TARGET")
    }
}

AutoMatch_StopSweep() {
    global g_AutoMatch_SweepActive
    SetTimer(AutoMatch_LockSweepTimer, 0)
    if (g_AutoMatch_SweepActive)
        SendInput("{RButton up}")
    g_AutoMatch_SweepActive := false
}

AutoMatch_BeginPrimaryAttack() {
    global g_AutoMatch_PrimaryWeaponKey, g_AutoMatch_PrimaryShotCount, g_AutoMatch_PrimaryStart
    SendInput("{RButton up}")
    SendInput("{" g_AutoMatch_PrimaryWeaponKey "}")
    g_AutoMatch_PrimaryShotCount := 0
    g_AutoMatch_PrimaryStart := A_TickCount
    AutoMatch_SetCombatSub("PRIMARY_ATTACK")
    AutoMatch_FirePrimaryShot()
}

AutoMatch_FirePrimaryShot() {
    global g_AutoMatch_PrimaryShotCount
    AutoMatch_ClickLeft()
    g_AutoMatch_PrimaryShotCount++
    Logger.Debug("[刷场次] 武器一攻击 " g_AutoMatch_PrimaryShotCount
        "/" AutoMatchPolicy.PrimaryShotOffsets.Length)
}

AutoMatch_ClickLeft() {
    global g_AutoMatch_OutputStart
    if (g_AutoMatch_OutputStart == 0)
        g_AutoMatch_OutputStart := A_TickCount
    SendInput("{LButton down}")
    Sleep(30)
    SendInput("{LButton up}")
}

AutoMatch_IsDetectionError(result) {
    global g_AutoMatch_LastDetectionWarn
    if (result.error == "")
        return false
    if (g_AutoMatch_LastDetectionWarn == 0
        || A_TickCount - g_AutoMatch_LastDetectionWarn >= 10000) {
        Logger.Warn("[刷场次] 战斗目标截图/检测失败, 保持当前状态: " result.error)
        g_AutoMatch_LastDetectionWarn := A_TickCount
    }
    return true
}

AutoMatch_CheckResult(clientRect) {
    global g_AutoMatch_ResultColor
    CoordMode("Pixel", "Screen")
    x1 := clientRect.x + Round(clientRect.w / 3)
    y1 := clientRect.y + Round(clientRect.h / 3)
    x2 := clientRect.x + Round(clientRect.w * 2 / 3)
    y2 := clientRect.y + Round(clientRect.h * 2 / 3)
    if (PixelSearch(&px, &py, x1, y1, x2, y2, g_AutoMatch_ResultColor, 20)) {
        Logger.Info("[刷场次] 检测到结算颜色 @" px "," py)
        return true
    }
    return false
}

AutoMatch_EnterResult() {
    global g_AutoMatch_State, g_AutoMatch_StateStart
    AutoMatch_StopSweep()
    SendInput("{LButton up}{RButton up}")
    g_AutoMatch_State := "RESULT"
    g_AutoMatch_StateStart := A_TickCount
}

AutoMatch_TickResult() {
    global g_AutoMatch_RunCount, g_AutoMatch_MaxRuns
    Sleep(1500)
    g_AutoMatch_RunCount++
    Logger.Info("[刷场次] 第 " g_AutoMatch_RunCount " 场完成, 返回大厅")
    if (g_AutoMatch_MaxRuns > 0 && g_AutoMatch_RunCount >= g_AutoMatch_MaxRuns) {
        Logger.Info("[刷场次] 已达 MaxRuns=" g_AutoMatch_MaxRuns ", 自动停止")
        AutoMatch_Stop()
        return
    }
    Sleep(10000)
    AutoMatch_ResetRoomIdentity()
    AutoMatch_ResetCombat()
    AutoMatch_SetState("WAIT_START")
}

AutoMatch_SetState(newState) {
    global g_AutoMatch_State, g_AutoMatch_StateStart
    if (g_AutoMatch_State != newState)
        Logger.Debug("[刷场次] 状态 " g_AutoMatch_State " → " newState)
    g_AutoMatch_State := newState
    g_AutoMatch_StateStart := A_TickCount
}

AutoMatch_SetCombatSub(newSub) {
    global g_AutoMatch_CombatSub
    if (g_AutoMatch_CombatSub != newSub)
        Logger.Debug("[刷场次] 战斗子状态 " (g_AutoMatch_CombatSub ? g_AutoMatch_CombatSub : "入口")
            " → " newSub)
    g_AutoMatch_CombatSub := newSub
}
