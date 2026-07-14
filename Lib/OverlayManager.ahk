; OverlayManager.ahk — 检测目标透明叠加面板 (AHK v2)
; 参考: GameUiMonitorAHK overlay/overlay.ahk

class OverlayManager {
    ; --- 配置 (从 INI 读取) ---
    static s_Enabled := false
    static s_Opacity := 80
    static s_UpdateInterval := 3
    static s_PositionInterval := 15
    static s_FontSize := 9

    ; --- 运行时状态 ---
    static s_Initialized := false
    static s_Gui := 0
    static s_TextCtrl := 0
    static s_Visible := false
    static s_TickCounter := 0
    static s_W := 340
    static s_H := 420

    ; --- 缓存检测结果 ---
    static s_LastRoomResult := 0
    static s_LastCombatResult := 0
    static s_HasRoom := false
    static s_HasCombat := false
    static s_LastAutoMatchState := ""
    static s_LastAutoMatchSub := ""
    static s_LastAutoMatchRuns := 0

    ; --- 初始化: 读取 INI 配置 ---
    static Init() {
        this.s_Enabled := ConfigManager.Read("Overlay", "Enabled", 0) != 0
        this.s_Opacity := ConfigManager.Read("Overlay", "Opacity", 80)
        this.s_UpdateInterval := Max(1, ConfigManager.Read("Overlay", "UpdateInterval", 3))
        this.s_PositionInterval := Max(1, ConfigManager.Read("Overlay", "PositionInterval", 15))
        this.s_FontSize := ConfigManager.Read("Overlay", "FontSize", 9)
        this.s_Initialized := true
        Logger.Debug("OverlayManager: 初始化完成, Enabled=" this.s_Enabled)
    }

    ; --- 每 Tick 调用 (由 GuiTick 驱动) ---
    static Tick() {
        if (!this.s_Initialized || !this.s_Enabled)
            return this.Hide()
        if (!GameUtils.IsGameRunning())
            return this.Hide()

        this.s_TickCounter++

        ; 惰性创建 GUI
        if (!this.s_Gui)
            this.CreateOverlay()

        ; AutoMatch 运行时复用其检测快照，避免同一 Tick 重复截图。
        ; 手动打开覆盖层且 AutoMatch 未运行时，才独立执行诊断检测。
        if (Mod(this.s_TickCounter, this.s_UpdateInterval) == 0) {
            if (g_AutoMatch_Enabled)
                this.RefreshFromAutoMatch()
            else
                this.RefreshDiagnostics()
        }

        ; 从全局变量快照 AutoMatch 状态 (0 开销)
        this.s_LastAutoMatchState := g_AutoMatch_State
        this.s_LastAutoMatchSub := g_AutoMatch_CombatSub
        this.s_LastAutoMatchRuns := g_AutoMatch_RunCount

        ; 更新文本并显示
        this.s_TextCtrl.Value := this.BuildOverlayText()

        if (!this.s_Visible)
            this.Show()
        if (Mod(this.s_TickCounter, this.s_PositionInterval) == 0)
            this.Reposition()
    }

    static RefreshFromAutoMatch() {
        state := g_AutoMatch_State
        if (state == "WAIT_START" || state == "WAIT_LOAD") {
            if (IsObject(g_AutoMatch_LastRoomDetection))
                this.s_LastRoomResult := g_AutoMatch_LastRoomDetection
            this.s_HasRoom := IsObject(this.s_LastRoomResult)
                && this.s_LastRoomResult.status == "OK"
            this.s_HasCombat := false
        } else if (state == "COMBAT") {
            if (IsObject(g_AutoMatch_LastCombatDetection))
                this.s_LastCombatResult := g_AutoMatch_LastCombatDetection
            this.s_HasCombat := IsObject(this.s_LastCombatResult)
                && this.s_LastCombatResult.error == ""
            this.s_HasRoom := false
        } else {
            this.s_HasRoom := false
            this.s_HasCombat := false
        }
    }

    static RefreshDiagnostics() {
        clientRect := GameUtils.GetClientRect()
        if (!clientRect) {
            this.s_HasRoom := false
            this.s_HasCombat := false
            return
        }
        this.s_LastRoomResult := RoomSelfDetector.Detect(clientRect)
        this.s_HasRoom := (this.s_LastRoomResult.status == "OK")
        this.s_LastCombatResult := CombatTargetDetector.Detect(clientRect)
        this.s_HasCombat := (this.s_LastCombatResult.error == "")
    }

    ; --- 创建透明 GUI (惰性) ---
    static CreateOverlay() {
        opts := "-Caption +ToolWindow +Border -DPIScale +AlwaysOnTop +E0x20"
        g := Gui(opts, "SDGO_Toolbox_Overlay")
        g.BackColor := "101010"
        g.MarginX := 6
        g.MarginY := 4
        g.SetFont("s" this.s_FontSize " cFFFFFF", "Microsoft YaHei UI")
        txt := g.Add("Text", "x6 y4 w" (this.s_W - 12) " h" (this.s_H - 8)
            . " BackgroundTrans vOverlayText", "Overlay 初始化中...")
        this.s_Gui := g
        this.s_TextCtrl := txt
        Logger.Debug("OverlayManager: 窗口已创建")
    }

    ; --- 构建显示文本 ---
    static BuildOverlayText() {
        parts := []

        ; ===== 游戏信息 =====
        windowRect := GameUtils.GetWindowRect()
        if (windowRect) {
            parts.Push("── 游戏 ──")
            parts.Push("窗口: " windowRect.w "x" windowRect.h
                . " | " GameUtils.g_InputMode)
        } else {
            parts.Push("游戏: 未检测到")
        }

        ; ===== 房间槽位 =====
        if (this.s_HasRoom && this.s_LastRoomResult && this.s_LastRoomResult.slots.Length > 0) {
            parts.Push("── 房间槽位 ──")
            slots := this.s_LastRoomResult.slots
            zhMap := Map("EMPTY", "空", "MASTER", "房主",
                         "READY", "准备", "NOT_READY", "未就绪")
            Loop 6 {
                ls := slots[A_Index]
                rs := slots[A_Index + 6]
                lt := this.FormatSlotLine(ls, zhMap)
                rt := this.FormatSlotLine(rs, zhMap)
                parts.Push(lt "    " rt)
            }
            sr := this.s_LastRoomResult
            if (sr.self_slot_index > 0) {
                stateZh := zhMap.Get(sr.self_state, sr.self_state)
                parts.Push("本人: 槽位" sr.self_slot_index " " stateZh
                    . " (分:" Round(sr.margin, 1) ")")
            } else {
                parts.Push("本人: 待确认")
            }
        }

        ; ===== 战斗检测 =====
        if (this.s_HasCombat && this.s_LastCombatResult) {
            parts.Push("── 战斗检测 ──")
            cr := this.s_LastCombatResult
            lockText := cr.lock_state == "LOCKED" ? "已锁定" : (cr.lock_state == "UNLOCKED" ? "未锁定" : cr.lock_state)
            targetText := cr.target_presence == "PRESENT" ? "有" : (cr.target_presence == "ABSENT" ? "无" : cr.target_presence)
            parts.Push("锁定: " lockText " | 目标: " targetText " (" cr.target_count ")")
        }

        ; ===== AutoMatch 状态 =====
        if (g_AutoMatch_Enabled) {
            parts.Push("── 刷场次 ──")
            state := this.s_LastAutoMatchState
            sub := this.s_LastAutoMatchSub
            if (sub != "")
                state .= " → " sub
            parts.Push("状态: " state)
            parts.Push("场次: " this.s_LastAutoMatchRuns)
        }

        ; ===== 时间戳 =====
        parts.Push("")
        parts.Push("更新: " FormatTime(A_Now, "HH:mm:ss"))
        parts.Push("[" this.s_TickCounter "]")

        return this.JoinArr(parts, "`n")
    }

    static FormatSlotLine(slot, zhMap) {
        state := zhMap.Get(slot.state, slot.state)
        marker := slot.self_border_eligible ? " ★" : ""
        return Format("{:02}", slot.index) " " state marker
    }

    ; --- 模块驱动显示/隐藏（自动联动） ---
    static AutoShow() {
        if (!this.s_Initialized)
            return
        if (!this.s_Enabled) {
            this.s_Enabled := true
            this.Tick()
        }
    }

    static AutoHide() {
        if (!this.s_Initialized)
            return
        if (!g_AutoMatch_Enabled) {
            this.s_Enabled := false
            this.Hide()
        }
    }

    ; --- 显示 / 隐藏 / 切换 ---
    static Show() {
        if (!this.s_Gui)
            return
        this.Reposition()
        this.s_Gui.Show("NA")
        WinSetTransparent(Round(255 * this.s_Opacity / 100), "ahk_id " this.s_Gui.Hwnd)
        this.s_Visible := true
    }

    static Hide() {
        try if (this.s_Gui)
            this.s_Gui.Hide()
        this.s_Visible := false
    }

    static Toggle() {
        if (!this.s_Initialized)
            return
        if (this.s_Visible) {
            this.s_Enabled := false
            this.Hide()
        } else {
            this.s_Enabled := true
            this.Tick()
        }
    }

    static Reposition() {
        workArea := this.GetWorkArea()
        if (!workArea)
            return
        gap := 8
        x := workArea.left + gap
        y := workArea.bottom - gap - this.s_H
        this.s_Gui.Show("x" Round(x) " y" Round(y) " w" this.s_W " h" this.s_H " NA")
    }

    static GetWorkArea() {
        try {
            MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
            return {left: l, top: t, right: r, bottom: b}
        }
        return false
    }

    static Cleanup() {
        this.Hide()
        this.s_Gui := 0
        this.s_TextCtrl := 0
        this.s_Initialized := false
    }

    ; --- 工具方法 ---
    static JoinArr(arr, sep) {
        result := ""
        for i, v in arr {
            if (i > 1)
                result .= sep
            result .= v
        }
        return result
    }

    static Clamp(val, minimum, maximum) {
        return Min(maximum, Max(minimum, val))
    }
}
