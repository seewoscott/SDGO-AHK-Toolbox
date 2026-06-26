; AutoFarmMulti.ahk — 自动刷图模块-多人模式 (AHK v2)
; 状态机: 等开始 → 按F5 → 等加载 → 开场连击+等待 → 战斗输出 → 结算 → 循环

global g_AutoFarmMulti_Enabled := false
global g_AutoFarmMulti_RunCount := 0
global g_AutoFarmMulti_State := "WAIT_START"
global g_AutoFarmMulti_StateStart := 0
global g_AutoFarmMulti_CombatStart := 0
global g_AutoFarmMulti_LoadRetries := 0
global g_AutoFarmMulti_LastFoundX := -1
global g_AutoFarmMulti_LastFoundY := -1
global g_AutoFarmMulti_CacheMissCount := 0

AutoFarmMulti_Init() {
    Logger.Info("AutoFarmMulti(多人) 模块初始化完成")
}

AutoFarmMulti_Start() {
    global g_AutoFarmMulti_Enabled, g_AutoFarmMulti_RunCount, g_AutoFarmMulti_State, g_AutoFarmMulti_StateStart
    global g_AutoFarmMulti_LastFoundX, g_AutoFarmMulti_LastFoundY, g_AutoFarmMulti_CacheMissCount
    g_AutoFarmMulti_Enabled := true
    g_AutoFarmMulti_RunCount := 0
    g_AutoFarmMulti_State := "WAIT_START"
    g_AutoFarmMulti_StateStart := A_TickCount
    g_AutoFarmMulti_LastFoundX := -1, g_AutoFarmMulti_LastFoundY := -1, g_AutoFarmMulti_CacheMissCount := 0
    Logger.Info("AutoFarmMulti: 已启动")
    return true
}

AutoFarmMulti_Stop() {
    global g_AutoFarmMulti_Enabled
    g_AutoFarmMulti_Enabled := false
    GameUtils.ActivateGame()
    SendInput("{LCtrl up}")
    Logger.Info("AutoFarmMulti: 已停止 (共 " g_AutoFarmMulti_RunCount " 局)")
}

AutoFarmMulti_Cleanup() {
    AutoFarmMulti_Stop()
}

; 智能搜索: 优先搜索上次命中位置附近(±60px), 未命中再搜全区域
AutoFarmMulti_SmartSearch(&fx, &fy, imgPath, x1, y1, x2, y2, cacheSize := 60) {
    global g_AutoFarmMulti_LastFoundX, g_AutoFarmMulti_LastFoundY, g_AutoFarmMulti_CacheMissCount
    if (g_AutoFarmMulti_LastFoundX >= 0 && g_AutoFarmMulti_CacheMissCount < 2) {
        cx1 := Max(x1, g_AutoFarmMulti_LastFoundX - cacheSize)
        cy1 := Max(y1, g_AutoFarmMulti_LastFoundY - cacheSize)
        cx2 := Min(x2, g_AutoFarmMulti_LastFoundX + cacheSize)
        cy2 := Min(y2, g_AutoFarmMulti_LastFoundY + cacheSize)
        if (ImageSearch(&fx, &fy, cx1, cy1, cx2, cy2, imgPath)) {
            g_AutoFarmMulti_LastFoundX := fx, g_AutoFarmMulti_LastFoundY := fy
            g_AutoFarmMulti_CacheMissCount := 0
            return true
        }
        g_AutoFarmMulti_CacheMissCount++
        Logger.Debug("[多人] 搜索缓存未命中(第" g_AutoFarmMulti_CacheMissCount "次), 回退全区域搜索")
    }
    if (ImageSearch(&fx, &fy, x1, y1, x2, y2, imgPath)) {
        g_AutoFarmMulti_LastFoundX := fx, g_AutoFarmMulti_LastFoundY := fy
        g_AutoFarmMulti_CacheMissCount := 0
        return true
    }
    return false
}

AutoFarmMulti_Tick() {
    global g_AutoFarmMulti_Enabled, g_AutoFarmMulti_State, g_AutoFarmMulti_StateStart
    global g_AutoFarmMulti_RunCount, g_AutoFarmMulti_CombatStart, g_AutoFarmMulti_LoadRetries
    global g_AutoFarmMulti_LastFoundX, g_AutoFarmMulti_LastFoundY, g_AutoFarmMulti_CacheMissCount
    static s_PrevState := ""

    if (!g_AutoFarmMulti_Enabled || !GameUtils.IsGameRunning())
        return

    rect := GameUtils.GetWindowRect()
    if (!rect)
        return
    gx := rect.x, gy := rect.y, gw := rect.w, gh := rect.h

    switch g_AutoFarmMulti_State {
    case "WAIT_START":
        if (AutoFarmMulti_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\start_btn.png"), gx + gw/2, gy + gh/2, gx + gw, gy + gh)) {
            Logger.Debug("[多人] 检测到开始按钮, 按F5")
            Sleep(500)
            GameUtils.ActivateGame()
            Sleep(300)
            SendInput("{F5 down}")
            Sleep(200)
            SendInput("{F5 up}")
            Sleep(2500)
            g_AutoFarmMulti_State := "WAIT_LOAD"
            g_AutoFarmMulti_StateStart := A_TickCount
        }

    case "WAIT_LOAD":
        if (AutoFarmMulti_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\combat_ui.png"), gx + gw*3/4, gy, gx + gw, gy + gh/4)) {
            g_AutoFarmMulti_LoadRetries := 0
            Logger.Debug("[多人] 检测到战斗UI, 开场连击")
            Sleep(800)
            GameUtils.ActivateGame()
            Loop 4 {
                Send("{LCtrl down}")
                Sleep(50)
                Send("{LCtrl up}")
                Sleep(100)
            }
            Sleep(10000)
            g_AutoFarmMulti_State := "COMBAT"
            g_AutoFarmMulti_CombatStart := A_TickCount
            g_AutoFarmMulti_StateStart := A_TickCount
        } else if (A_TickCount - g_AutoFarmMulti_StateStart > 30000) {
            g_AutoFarmMulti_LoadRetries++
            Logger.Warn("[多人] 加载超时, 按Enter取消弹窗 (第 " g_AutoFarmMulti_LoadRetries " 次)")
            GameUtils.ActivateGame()
            Sleep(300)
            SendInput("{Enter down}")
            Sleep(200)
            SendInput("{Enter up}")
            Sleep(500)
            g_AutoFarmMulti_State := "WAIT_START"
            g_AutoFarmMulti_StateStart := A_TickCount
        }

    case "COMBAT":
        ; 每 Tick 内做一次攻击循环 (匹配原版 ~1.2s 间隔)
        Loop {
            ; 检测结束标志
            if (AutoFarmMulti_SmartSearch(&fx, &fy, "*90 " GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\end.png"), 0, 0, A_ScreenWidth/4, A_ScreenHeight/4)) {
                Logger.Debug("[多人] 检测到结束标志, 进入结算")
                Sleep(300)
                g_AutoFarmMulti_State := "RESULT"
                g_AutoFarmMulti_StateStart := A_TickCount
                return
            }
            ; 攻击
            Send("{LCtrl down}")
            Sleep(50)
            Send("{LCtrl up}")
            ; 微移防发呆
            if (Mod(A_Index, 4) == 0) {
                Send("{w down}")
                Sleep(50)
                Send("{w up}")
            }
            ; 超时防护
            if (A_TickCount - g_AutoFarmMulti_CombatStart > 60000) {
                Logger.Warn("[多人] 战斗超时60s, 强制结算")
                g_AutoFarmMulti_State := "RESULT"
                g_AutoFarmMulti_StateStart := A_TickCount
                return
            }
            if (!g_AutoFarmMulti_Enabled || !GameUtils.IsGameRunning())
                return
            Sleep(900)
        }

    case "RESULT":
        Logger.Debug("[多人] 结算清理...")
        Sleep(1500)
        GameUtils.ActivateGame()
        Loop 25 {
            if (!g_AutoFarmMulti_Enabled || !GameUtils.IsGameRunning())
                return
            SendInput("{Enter down}")
            Sleep(100)
            SendInput("{Enter up}")
            Sleep(400)
        }
        g_AutoFarmMulti_RunCount++
        Logger.Info("[多人] 第 " g_AutoFarmMulti_RunCount " 局完成, 返回大厅")
        Sleep(10000)
        g_AutoFarmMulti_State := "WAIT_START"
        g_AutoFarmMulti_StateStart := A_TickCount
    }
    ; 状态切换时重置搜索缓存
    if (g_AutoFarmMulti_State != s_PrevState) {
        Logger.Debug("[多人] 状态 " (s_PrevState ? s_PrevState : "启动") "→" g_AutoFarmMulti_State ", 缓存重置")
        g_AutoFarmMulti_LastFoundX := -1, g_AutoFarmMulti_LastFoundY := -1, g_AutoFarmMulti_CacheMissCount := 0
        s_PrevState := g_AutoFarmMulti_State
    }
}
