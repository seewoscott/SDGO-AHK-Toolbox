; AutoMatch.ahk — 新服刷场次模块 (AHK v2)
; 状态机: 等开始 → Ready检测 → 按F5 → 等加载 → 旋转索敌 → 锁敌攻击 → 结算 → 循环
; 使用 GameUtils.SmartSearch (共享) + GameUtils.SendGameKey (遵循输入模式)

global g_AutoMatch_Enabled := false
global g_AutoMatch_RunCount := 0
global g_AutoMatch_State := "WAIT_START"
global g_AutoMatch_StateStart := 0
global g_AutoMatch_CombatStart := 0
global g_AutoMatch_MaxRuns := 0
; SmartSearch 缓存对象
global g_AutoMatch_SearchCache := {LastX: -1, LastY: -1, MissCount: 0}
; 战斗子状态
global g_AutoMatch_CombatSub := ""   ; SEEK / ADVANCE / ATTACK
global g_AutoMatch_SeekStep := 0
global g_AutoMatch_SeekRounds := 0
; 配置项
global g_AutoMatch_ReadyPixelX, g_AutoMatch_ReadyPixelY, g_AutoMatch_ReadyPixelColor
global g_AutoMatch_ReadyTimeout, g_AutoMatch_SeekSteps, g_AutoMatch_SeekMouseDelta
global g_AutoMatch_SeekMaxRounds, g_AutoMatch_LockColor, g_AutoMatch_AttackDuration
global g_AutoMatch_ResultColor, g_AutoMatch_AttackStopped := false

AutoMatch_Init() {
    global g_AutoMatch_MaxRuns
    global g_AutoMatch_ReadyPixelX, g_AutoMatch_ReadyPixelY, g_AutoMatch_ReadyPixelColor
    global g_AutoMatch_ReadyTimeout, g_AutoMatch_SeekSteps, g_AutoMatch_SeekMouseDelta
    global g_AutoMatch_SeekMaxRounds, g_AutoMatch_LockColor, g_AutoMatch_AttackDuration
    global g_AutoMatch_ResultColor, g_AutoMatch_AttackStopped

    g_AutoMatch_MaxRuns := ConfigManager.Read("AutoMatch", "MaxRuns", 0)
    g_AutoMatch_ReadyPixelX := ConfigManager.Read("AutoMatch", "ReadyPixelX", 683)
    g_AutoMatch_ReadyPixelY := ConfigManager.Read("AutoMatch", "ReadyPixelY", 493)
    g_AutoMatch_ReadyPixelColor := ConfigManager.Read("AutoMatch", "ReadyPixelColor", 0xFFFFFF)
    g_AutoMatch_ReadyTimeout := ConfigManager.Read("AutoMatch", "ReadyTimeout", 15)
    g_AutoMatch_SeekSteps := ConfigManager.Read("AutoMatch", "SeekSteps", 18)
    g_AutoMatch_SeekMouseDelta := ConfigManager.Read("AutoMatch", "SeekMouseDelta", 50)
    g_AutoMatch_SeekMaxRounds := ConfigManager.Read("AutoMatch", "SeekMaxRounds", 4)
    g_AutoMatch_LockColor := ConfigManager.Read("AutoMatch", "LockColor", 0x73B279)
    g_AutoMatch_AttackDuration := ConfigManager.Read("AutoMatch", "AttackDuration", 60)
    g_AutoMatch_ResultColor := ConfigManager.Read("AutoMatch", "ResultColor", 0x25B3D1)

    Logger.Info("AutoMatch(刷场次) 模块初始化完成 | MaxRuns=" g_AutoMatch_MaxRuns)
}

AutoMatch_Start() {
    global g_AutoMatch_Enabled, g_AutoMatch_RunCount, g_AutoMatch_State, g_AutoMatch_StateStart
    global g_AutoMatch_SearchCache, g_AutoMatch_CombatSub, g_AutoMatch_SeekStep, g_AutoMatch_SeekRounds
    global g_AutoMatch_AttackStopped, g_AutoMatch_CombatStart
    g_AutoMatch_Enabled := true
    g_AutoMatch_AttackStopped := false
    g_AutoMatch_RunCount := 0
    g_AutoMatch_State := "WAIT_START"
    g_AutoMatch_StateStart := A_TickCount
    g_AutoMatch_CombatSub := ""
    g_AutoMatch_SeekStep := 0
    g_AutoMatch_SeekRounds := 0
    g_AutoMatch_SearchCache.LastX := -1, g_AutoMatch_SearchCache.LastY := -1
    g_AutoMatch_SearchCache.MissCount := 0
    Logger.Info("AutoMatch: 已启动 | MaxRuns=" g_AutoMatch_MaxRuns)
    return true
}

AutoMatch_Stop() {
    global g_AutoMatch_Enabled
    g_AutoMatch_Enabled := false
    GameUtils.ActivateGame()
    SendInput("{RButton up}")    ; 释放可能按住的右键
    Logger.Info("AutoMatch: 已停止 (共 " g_AutoMatch_RunCount " 场)")
}

AutoMatch_Cleanup() {
    AutoMatch_Stop()
}

AutoMatch_Tick() {
    global g_AutoMatch_Enabled, g_AutoMatch_State, g_AutoMatch_StateStart
    global g_AutoMatch_RunCount, g_AutoMatch_CombatStart, g_AutoMatch_MaxRuns
    global g_AutoMatch_SearchCache, g_AutoMatch_CombatSub
    global g_AutoMatch_SeekStep, g_AutoMatch_SeekRounds
    global g_AutoMatch_ReadyPixelX, g_AutoMatch_ReadyPixelY, g_AutoMatch_ReadyPixelColor
    global g_AutoMatch_ReadyTimeout, g_AutoMatch_SeekSteps, g_AutoMatch_SeekMouseDelta
    global g_AutoMatch_SeekMaxRounds, g_AutoMatch_LockColor, g_AutoMatch_AttackDuration
    global g_AutoMatch_ResultColor, g_AutoMatch_AttackStopped
    static s_PrevState := ""
    static s_PrevCombatSub := ""

    if (!g_AutoMatch_Enabled || !GameUtils.IsGameRunning())
        return

    rect := GameUtils.GetWindowRect()
    if (!rect)
        return
    gx := rect.x, gy := rect.y, gw := rect.w, gh := rect.h

    switch g_AutoMatch_State {
    case "WAIT_START":
        ; 搜右下区域: start_btn.png
        static s_LoggedStartPath := false
        static s_ReadyWaitStart := 0
        static s_StartBtnFound := false

        if (!s_LoggedStartPath) {
            Logger.Debug("[刷场次] WAIT_START 搜索路径: " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\start_btn.png"))
            s_LoggedStartPath := true
        }

        if (!s_StartBtnFound) {
            if (!GameUtils.SmartSearch(&fx, &fy,
                "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\start_btn.png"),
                gx + gw/2, gy + gh/2, gx + gw, gy + gh,
                g_AutoMatch_SearchCache))
                return
            Logger.Debug("[刷场次] 检测到开始按钮, 先按F5, 等待Ready(像素 " g_AutoMatch_ReadyPixelX "," g_AutoMatch_ReadyPixelY " ≠ 0x" Format("{:06X}", g_AutoMatch_ReadyPixelColor) ")")
            Sleep(300)
            GameUtils.ActivateGame()
            Sleep(200)
            SendInput("{F5 down}")
            Sleep(200)
            SendInput("{F5 up}")
            s_StartBtnFound := true
            s_ReadyWaitStart := A_TickCount
        }

        ; F5 Ready 检测: 等待特定像素颜色变化, 变化后进入 WAIT_LOAD
        GameUtils.ActivateGame()
        Sleep(50)
        readyColor := PixelGetColor(g_AutoMatch_ReadyPixelX, g_AutoMatch_ReadyPixelY)
        if (readyColor != g_AutoMatch_ReadyPixelColor) {
            Logger.Debug("[刷场次] Ready! (像素颜色=0x" Format("{:06X}", readyColor) "), 进入加载")
            Sleep(2500)
            g_AutoMatch_State := "WAIT_LOAD"
            g_AutoMatch_StateStart := A_TickCount
            s_StartBtnFound := false
            s_ReadyWaitStart := 0
        } else if (A_TickCount - s_ReadyWaitStart > 10000) {
            Logger.Warn("[刷场次] Ready超时10s, 仍然进入加载")
            g_AutoMatch_State := "WAIT_LOAD"
            g_AutoMatch_StateStart := A_TickCount
            s_StartBtnFound := false
            s_ReadyWaitStart := 0
        }

    case "WAIT_LOAD":
        ; 搜右上区域: combat_ui.png (和 AutoFarm 一致)
        static s_LoggedLoadPath := false
        if (!s_LoggedLoadPath) {
            Logger.Debug("[刷场次] WAIT_LOAD 搜索路径: " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\combat_ui.png"))
            s_LoggedLoadPath := true
        }
        if (GameUtils.SmartSearch(&fx, &fy,
            "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\combat_ui.png"),
            gx + gw*3/4, gy, gx + gw, gy + gh/4,
            g_AutoMatch_SearchCache)) {
            Logger.Debug("[刷场次] 检测到战斗UI, 开始索敌")
            Sleep(800)
            g_AutoMatch_State := "COMBAT"
            g_AutoMatch_CombatSub := "SEEK"
            g_AutoMatch_SeekStep := 0
            g_AutoMatch_SeekRounds := 0
            g_AutoMatch_CombatStart := A_TickCount
            g_AutoMatch_StateStart := A_TickCount
        }

    case "COMBAT":
        ; === 战斗状态机 (子状态: SEEK / ADVANCE / ATTACK) ===

        ; SEEK/ADVANCE 总兜底: 180s未锁到则强制结算
        if (g_AutoMatch_CombatSub != "ATTACK" && A_TickCount - g_AutoMatch_CombatStart > 180000) {
            Logger.Warn("[刷场次] 索敌超时180s, 强制结算")
            g_AutoMatch_CombatSub := ""
            g_AutoMatch_State := "RESULT"
            g_AutoMatch_StateStart := A_TickCount
            return
        }
        switch g_AutoMatch_CombatSub {
        case "SEEK":
            ; 旋转索敌: 按住右键 + 鼠标右移拖动旋转视角
            CoordMode("Mouse", "Screen")
            SendInput("{RButton down}")
            Sleep(30)
            MouseGetPos(&sx, &sy)
            Loop 20 {
                if (!g_AutoMatch_Enabled || !GameUtils.IsGameRunning())
                    return
                sx += 2
                MouseMove(sx, sy, 0)
                Sleep(100)
            }
            SendInput("{RButton up}")
            Sleep(30)

            ; 旋转结束后搜一次九宫格中心的锁定框颜色
            cx1 := gw/3, cy1 := gh/3, cx2 := gw*2/3, cy2 := gh*2/3
            if (PixelSearch(&px, &py, cx1, cy1, cx2, cy2, g_AutoMatch_LockColor, 15)) {
                Logger.Debug("[刷场次] 锁定敌机! (颜色 0x" Format("{:06X}", g_AutoMatch_LockColor) " 命中 @" px "," py ")")
                SendInput("{RButton down}")
                Sleep(50)
                g_AutoMatch_CombatSub := "ATTACK"
                g_AutoMatch_CombatStart := A_TickCount
                g_AutoMatch_StateStart := A_TickCount
                return
            }

            ; 每 tick 计数, 满一圈进 ADVANCE
            g_AutoMatch_SeekStep++
            if (g_AutoMatch_SeekStep >= g_AutoMatch_SeekSteps) {
                Logger.Debug("[刷场次] 旋转满一圈(" g_AutoMatch_SeekSteps "步), 未锁到")
                g_AutoMatch_CombatSub := "ADVANCE"
                g_AutoMatch_StateStart := A_TickCount
            }

        case "ADVANCE":
            ; 前进1.5s后重新索敌
            Logger.Debug("[刷场次] 前进搜索...")
            GameUtils.ActivateGame()
            SendInput("{w down}")
            Sleep(1500)
            SendInput("{w up}")
            Sleep(300)
            g_AutoMatch_SeekStep := 0
            g_AutoMatch_SeekRounds++
            if (g_AutoMatch_SeekRounds >= g_AutoMatch_SeekMaxRounds) {
                Logger.Debug("[刷场次] 索敌" g_AutoMatch_SeekRounds "轮未果, 兜底进入攻击")
                SendInput("{RButton down}")      ; 按住右键
                Sleep(50)
                g_AutoMatch_CombatSub := "ATTACK"
                g_AutoMatch_CombatStart := A_TickCount
                g_AutoMatch_StateStart := A_TickCount
            } else {
                g_AutoMatch_CombatSub := "SEEK"
            }

        case "ATTACK":
            ; 前景锁敌攻击: SendInput("{RButton down}") 按住右键锁敌 + J键攻击
            attackElapsed := (A_TickCount - g_AutoMatch_StateStart) / 1000

            ; 兜底检查: 120s超时 → 释放右键, 停止攻击, 继续搜结算色
            if (A_TickCount - g_AutoMatch_CombatStart > 60000 && !g_AutoMatch_AttackStopped) {
                Logger.Warn("[刷场次] 战斗超时120s, 释放右键停止攻击, 继续等待结算")
                SendInput("{RButton up}")
                g_AutoMatch_AttackStopped := true
            }

            ; 攻击: J键 (超时后跳过)
            if (!g_AutoMatch_AttackStopped) {
                Loop 3 {
                    if (!g_AutoMatch_Enabled || !GameUtils.IsGameRunning())
                        return
                    SendInput("{J down}")
                    Sleep(30)
                    SendInput("{J up}")
                    Sleep(100)
                }
            }

            ; 前 AttackDuration 秒只攻击, 之后搜九宫格中心区 0x25B3D1 (结算色)
            if (attackElapsed >= g_AutoMatch_AttackDuration) {
                cx1 := gw/3, cy1 := gh/3, cx2 := gw*2/3, cy2 := gh*2/3
                if (PixelSearch(&px, &py, cx1, cy1, cx2, cy2, g_AutoMatch_ResultColor, 20)) {
                    Logger.Debug("[刷场次] 检测到结算标志 (颜色 0x" Format("{:06X}", g_AutoMatch_ResultColor) " @" px "," py "), 进入结算")
                    if (!g_AutoMatch_AttackStopped)
                        SendInput("{RButton up}")
                    g_AutoMatch_CombatSub := ""
                    g_AutoMatch_State := "RESULT"
                    g_AutoMatch_StateStart := A_TickCount
                    g_AutoMatch_AttackStopped := false
                    return
                }
            }

        }

    case "RESULT":
        Logger.Debug("[刷场次] 结算清理...")
        Sleep(1500)
        g_AutoMatch_RunCount++
        Logger.Info("[刷场次] 第 " g_AutoMatch_RunCount " 场完成, 返回大厅")
        ; MaxRuns 检查: 达到上限自动停止
        if (g_AutoMatch_MaxRuns > 0 && g_AutoMatch_RunCount >= g_AutoMatch_MaxRuns) {
            Logger.Info("[刷场次] 已达 MaxRuns=" g_AutoMatch_MaxRuns ", 自动停止")
            AutoMatch_Stop()
            return
        }
        Sleep(10000)
        g_AutoMatch_State := "WAIT_START"
        g_AutoMatch_StateStart := A_TickCount
    }

    ; 状态切换时重置搜索缓存
    if (g_AutoMatch_State != s_PrevState) {
        Logger.Debug("[刷场次] 状态 " (s_PrevState ? s_PrevState : "启动") "→" g_AutoMatch_State
            (g_AutoMatch_CombatSub ? ":" g_AutoMatch_CombatSub : "") ", 缓存重置")
        g_AutoMatch_SearchCache.LastX := -1, g_AutoMatch_SearchCache.LastY := -1
        g_AutoMatch_SearchCache.MissCount := 0
        s_PrevState := g_AutoMatch_State
        s_PrevCombatSub := ""
    }
    ; 战斗子状态切换日志
    if (g_AutoMatch_State == "COMBAT" && g_AutoMatch_CombatSub != s_PrevCombatSub) {
        Logger.Debug("[刷场次] 战斗子状态: " (s_PrevCombatSub ? s_PrevCombatSub : "入口") "→" g_AutoMatch_CombatSub)
        s_PrevCombatSub := g_AutoMatch_CombatSub
    }
}
