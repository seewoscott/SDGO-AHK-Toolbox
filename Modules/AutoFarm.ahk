; AutoFarm.ahk — 自动刷图模块 (AHK v2)
; 状态机: 等开始 → 按F5 → 等加载 → 战斗输出 → 结算 → 循环

global g_AutoFarm_Enabled := false
global g_AutoFarm_RunCount := 0
global g_AutoFarm_State := "WAIT_START"
global g_AutoFarm_StateStart := 0
global g_AutoFarm_CombatStart := 0
global g_AutoFarm_LastFoundX := -1
global g_AutoFarm_LastFoundY := -1
global g_AutoFarm_CacheMissCount := 0

AutoFarm_Init() {
    Logger.Info("AutoFarm 模块初始化完成")
}

AutoFarm_Start() {
    global g_AutoFarm_Enabled, g_AutoFarm_RunCount, g_AutoFarm_State, g_AutoFarm_StateStart
    global g_AutoFarm_LastFoundX, g_AutoFarm_LastFoundY, g_AutoFarm_CacheMissCount
    g_AutoFarm_Enabled := true
    g_AutoFarm_RunCount := 0
    g_AutoFarm_State := "WAIT_START"
    g_AutoFarm_StateStart := A_TickCount
    g_AutoFarm_LastFoundX := -1, g_AutoFarm_LastFoundY := -1, g_AutoFarm_CacheMissCount := 0
    Logger.Info("AutoFarm: 已启动")
    return true
}

AutoFarm_Stop() {
    global g_AutoFarm_Enabled
    g_AutoFarm_Enabled := false
    GameUtils.ActivateGame()
    SendInput("{LCtrl up}")
    Logger.Info("AutoFarm: 已停止 (共 " g_AutoFarm_RunCount " 局)")
}

AutoFarm_Cleanup() {
    AutoFarm_Stop()
}

; 重启建房前只重置状态机，保留启用状态和已完成局数。
AutoFarm_PrepareForRestart() {
    global g_AutoFarm_State, g_AutoFarm_StateStart, g_AutoFarm_CombatStart
    global g_AutoFarm_LastFoundX, g_AutoFarm_LastFoundY, g_AutoFarm_CacheMissCount
    g_AutoFarm_State := "WAIT_START"
    g_AutoFarm_StateStart := A_TickCount
    g_AutoFarm_CombatStart := 0
    g_AutoFarm_LastFoundX := -1
    g_AutoFarm_LastFoundY := -1
    g_AutoFarm_CacheMissCount := 0
}

; 智能搜索: 优先搜索上次命中位置附近(±60px), 未命中再搜全区域
AutoFarm_SmartSearch(&fx, &fy, imgPath, x1, y1, x2, y2, cacheSize := 60) {
    global g_AutoFarm_LastFoundX, g_AutoFarm_LastFoundY, g_AutoFarm_CacheMissCount
    if (g_AutoFarm_LastFoundX >= 0 && g_AutoFarm_CacheMissCount < 2) {
        cx1 := Max(x1, g_AutoFarm_LastFoundX - cacheSize)
        cy1 := Max(y1, g_AutoFarm_LastFoundY - cacheSize)
        cx2 := Min(x2, g_AutoFarm_LastFoundX + cacheSize)
        cy2 := Min(y2, g_AutoFarm_LastFoundY + cacheSize)
        if (ImageSearch(&fx, &fy, cx1, cy1, cx2, cy2, imgPath)) {
            g_AutoFarm_LastFoundX := fx, g_AutoFarm_LastFoundY := fy
            g_AutoFarm_CacheMissCount := 0
            return true
        }
        g_AutoFarm_CacheMissCount++
        Logger.Debug("[单人] 搜索缓存未命中(第" g_AutoFarm_CacheMissCount "次), 回退全区域搜索")
    }
    if (ImageSearch(&fx, &fy, x1, y1, x2, y2, imgPath)) {
        g_AutoFarm_LastFoundX := fx, g_AutoFarm_LastFoundY := fy
        g_AutoFarm_CacheMissCount := 0
        return true
    }
    return false
}

AutoFarm_Tick() {
    global g_AutoFarm_Enabled, g_AutoFarm_State, g_AutoFarm_StateStart, g_RestartGame_Enabled
    global g_AutoFarm_RunCount, g_AutoFarm_CombatStart
    global g_AutoFarm_LastFoundX, g_AutoFarm_LastFoundY, g_AutoFarm_CacheMissCount
    static s_PrevState := ""

    if (!g_AutoFarm_Enabled || g_RestartGame_Enabled || !GameUtils.IsGameRunning())
        return

    rect := GameUtils.GetWindowRect()
    if (!rect)
        return
    gx := rect.x, gy := rect.y, gw := rect.w, gh := rect.h

    switch g_AutoFarm_State {
    case "WAIT_START":
        ; 搜右下区域: start_btn.png
        if (AutoFarm_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\start_btn.png"), gx + gw/2, gy + gh/2, gx + gw, gy + gh)) {
            Logger.Debug("[单人] 检测到开始按钮, 按F5")
            Sleep(500)
            GameUtils.ActivateGame()
            Sleep(300)
            SendInput("{F5 down}")
            Sleep(200)
            SendInput("{F5 up}")
            Sleep(2500)
            g_AutoFarm_State := "WAIT_LOAD"
            g_AutoFarm_StateStart := A_TickCount
        }

    case "WAIT_LOAD":
        ; 搜右上区域: combat_ui.png
        if (AutoFarm_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\combat_ui.png"), gx + gw*3/4, gy, gx + gw, gy + gh/4)) {
            Logger.Debug("[单人] 检测到战斗UI, 开始输出")
            Sleep(800)
            g_AutoFarm_State := "COMBAT"
            g_AutoFarm_CombatStart := A_TickCount
            g_AutoFarm_StateStart := A_TickCount
        } else if (A_TickCount - g_AutoFarm_StateStart > 30000) {
            Logger.Warn("[单人] 加载超时, 按Enter+F5重试")
            GameUtils.ActivateGame()
            SendInput("{Enter down}")
            Sleep(200)
            SendInput("{Enter up}")
            Sleep(500)
            g_AutoFarm_State := "WAIT_START"
            g_AutoFarm_StateStart := A_TickCount
        }

    case "COMBAT":
        ; 搜左上区域: end.png
        if (AutoFarm_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\end.png"), 0, 0, A_ScreenWidth/4, A_ScreenHeight/4)) {
            Logger.Debug("[单人] 检测到结束标志, 进入结算")
            Sleep(300)
            g_AutoFarm_State := "RESULT"
            g_AutoFarm_StateStart := A_TickCount
            return
        }
        ; 攻击输出
        SendInput("{LCtrl down}")
        Sleep(50)
        SendInput("{LCtrl up}")
        if (Mod(A_Index, 4) == 0) {
            SendInput("{w down}")
            Sleep(50)
            SendInput("{w up}")
        }
        if (A_TickCount - g_AutoFarm_CombatStart > 60000) {
            Logger.Warn("[单人] 战斗超时60s, 强制结算")
            g_AutoFarm_State := "RESULT"
            g_AutoFarm_StateStart := A_TickCount
        }

    case "RESULT":
        Logger.Debug("[单人] 结算清理...")
        Sleep(1500)
        GameUtils.ActivateGame()
        Loop 15 {
            if (!g_AutoFarm_Enabled || !GameUtils.IsGameRunning())
                return
            SendInput("{Enter down}")
            Sleep(100)
            SendInput("{Enter up}")
            Sleep(400)
        }
        g_AutoFarm_RunCount++
        Logger.Info("[单人] 第 " g_AutoFarm_RunCount " 局完成, 返回大厅")
        Sleep(10000)
        g_AutoFarm_State := "WAIT_START"
        g_AutoFarm_StateStart := A_TickCount
    }
    ; 状态切换时重置搜索缓存
    if (g_AutoFarm_State != s_PrevState) {
        Logger.Debug("[单人] 状态 " (s_PrevState ? s_PrevState : "启动") "→" g_AutoFarm_State ", 缓存重置")
        g_AutoFarm_LastFoundX := -1, g_AutoFarm_LastFoundY := -1, g_AutoFarm_CacheMissCount := 0
        s_PrevState := g_AutoFarm_State
    }
}
