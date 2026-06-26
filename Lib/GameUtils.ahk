; GameUtils.ahk — 游戏窗口检测与输入注入工具
; SDGO UNION 1.4.3 (d3d9 窗口模式 1024x768)

class GameUtils {
    static g_hWnd := 0
    static g_InputMode := "control"
    static g_WinW := 1024
    static g_WinH := 768
    static s_LastActiveTick := 0  ; SmartSearch 激活缓存

    ; 初始化: 检测游戏窗口并设置输入模式
    static Init() {
        this.g_InputMode := ConfigManager.Read("Game", "InputMode", "control")
        this.g_WinW := ConfigManager.Read("Game", "WindowWidth", 1024)
        this.g_WinH := ConfigManager.Read("Game", "WindowHeight", 768)
        this.RefreshWindow()
        return this.g_hWnd != 0
    }

    ; 刷新游戏窗口句柄
    static RefreshWindow() {
        this.g_hWnd := WinExist("ahk_exe " ConfigManager.GameExe)
        return this.g_hWnd != 0
    }

    ; 游戏是否在运行 (Tick级缓存, 避免同Tick内重复查询)
    static s_LastRunningTick := 0
    static s_LastRunningResult := false
    static IsGameRunning() {
        if (A_TickCount == this.s_LastRunningTick)
            return this.s_LastRunningResult
        this.s_LastRunningTick := A_TickCount
        this.s_LastRunningResult := WinExist("ahk_exe " ConfigManager.GameExe) != 0
        return this.s_LastRunningResult
    }

    ; 游戏窗口是否激活(前景)
    static IsGameActive() {
        return WinActive("ahk_exe " ConfigManager.GameExe) != 0
    }

    ; 获取窗口位置和大小 (Tick级缓存)
    static s_LastRectTick := 0
    static s_LastRectResult := false
    static GetWindowRect() {
        if (A_TickCount == this.s_LastRectTick)
            return this.s_LastRectResult
        this.s_LastRectTick := A_TickCount
        if (!this.RefreshWindow())
            return (this.s_LastRectResult := false)
        WinGetPos(&x, &y, &w, &h, "ahk_id " this.g_hWnd)
        this.s_LastRectResult := {x: x, y: y, w: w, h: h}
        return this.s_LastRectResult
    }

    ; 激活游戏窗口到前景
    static ActivateGame() {
        if (!this.RefreshWindow())
            return false
        WinActivate("ahk_id " this.g_hWnd)
        WinWaitActive("ahk_id " this.g_hWnd, , 2)
        return WinActive("ahk_id " this.g_hWnd) != 0
    }

    ; 发送单个按键到游戏 (后台安全方式)
    static SendGameKey(key, delay := 0) {
        if (!this.IsGameRunning())
            return false
        if (this.g_InputMode == "control")
            ControlSend(key, , "ahk_exe " ConfigManager.GameExe)
        else {
            this.ActivateGame()
            Send(key)
        }
        if (delay > 0)
            Sleep(delay)
        return true
    }

    ; 发送一次按键 (按下+释放)
    static SendGameKeyOnce(key, delay := 0) {
        return this.SendGameKey("{" key "}", delay)
    }

    ; 后台鼠标点击 (窗口相对坐标)
    static GameClick(x, y, button := "Left", clicks := 1) {
        if (!this.IsGameRunning())
            return false
        ControlClick("x" x " y" y, "ahk_exe " ConfigManager.GameExe, , button, clicks)
        return true
    }

    ; 获取指定坐标像素颜色 (需要窗口在前景, D3D9兼容性有限)
    static GetPixelColor(x, y) {
        if (!this.IsGameRunning())
            return ""
        this.ActivateGame()
        Sleep(100)
        color := PixelGetColor(x, y)
        return color
    }

    ; 在指定区域内搜索颜色 (需要窗口在前景)
    static PixelSearch(x1, y1, x2, y2, color, variation := 10) {
        if (!this.IsGameRunning())
            return false
        this.ActivateGame()
        Sleep(100)
        result := PixelSearch(&px, &py, x1, y1, x2, y2, color, variation)
        if (result)
            return {x: px, y: py}
        return false
    }

    ; 图像搜索 (D3D9兼容性最差, 作为最后手段)
    static ImageSearch(imagePath, x1 := 0, y1 := 0, x2 := "", y2 := "", variation := 30) {
        if (!this.IsGameRunning())
            return false
        if (x2 == "")
            x2 := this.g_WinW
        if (y2 == "")
            y2 := this.g_WinH
        this.ActivateGame()
        Sleep(200)
        result := ImageSearch(&ix, &iy, x1, y1, x2, y2, "*" variation " " imagePath)
        if (result)
            return {x: ix, y: iy}
        return false
    }

    ; 智能图像搜索 — 优先搜索上次命中位置附近(±cacheSize), 减少全区域搜索量
    ; cacheObj 需包含 {LastX, LastY, MissCount} 三个字段, 由调用者声明维护
    ; 前 2 次未命中搜索 ±cacheSize 近邻区域, 超过后回退全区域搜索
    static SmartSearch(&outX, &outY, imagePath, x1, y1, x2, y2, cacheObj, cacheSize := 60) {
        ; Tick级激活缓存: 同Tick内已激活过则跳过 (ImageSearch需要窗口在前景渲染)
        if (A_TickCount != this.s_LastActiveTick || !WinActive("ahk_id " this.g_hWnd)) {
            this.ActivateGame()
            Sleep(50)
            this.s_LastActiveTick := A_TickCount
        }
        if (cacheObj.LastX >= 0 && cacheObj.MissCount < 2) {
            cx1 := Max(x1, cacheObj.LastX - cacheSize)
            cy1 := Max(y1, cacheObj.LastY - cacheSize)
            cx2 := Min(x2, cacheObj.LastX + cacheSize)
            cy2 := Min(y2, cacheObj.LastY + cacheSize)
            if (ImageSearch(&outX, &outY, cx1, cy1, cx2, cy2, imagePath)) {
                cacheObj.LastX := outX, cacheObj.LastY := outY
                cacheObj.MissCount := 0
                return true
            }
            cacheObj.MissCount++
        }
        if (ImageSearch(&outX, &outY, x1, y1, x2, y2, imagePath)) {
            cacheObj.LastX := outX, cacheObj.LastY := outY
            cacheObj.MissCount := 0
            return true
        }
        return false
    }

    ; 4-tier 图像路径回退: 服务端+分辨率 → 服务端 → 全局+分辨率 → 全局
    ;   Tier 1: Data\Images\<ServerDisplayName>_<name>_<WxH>.png
    ;   Tier 2: Data\Images\<ServerDisplayName>_<name>.png
    ;   Tier 3: Data\Images\<name>_<WxH>.png
    ;   Tier 4: Data\Images\<name>.png (原始路径)
    static ResolveImagePath(baseName) {
        global g_ResolutionProfile
        SplitPath(baseName, &name, &dir)
        nameNoExt := StrReplace(name, ".png", "")

        if (ConfigManager.ServerDisplayName != "") {
            tier1 := dir "\" ConfigManager.ServerDisplayName "_" nameNoExt "_" g_ResolutionProfile ".png"
            if (FileExist(tier1))
                return tier1
        }

        if (ConfigManager.ServerDisplayName != "") {
            tier2 := dir "\" ConfigManager.ServerDisplayName "_" nameNoExt ".png"
            if (FileExist(tier2))
                return tier2
        }

        tier3 := dir "\" nameNoExt "_" g_ResolutionProfile ".png"
        if (FileExist(tier3))
            return tier3

        return baseName
    }

    ; 检测日志文件中是否包含特定模式 (断线检测等)
    static CheckLogFile(pattern, gameDir := "") {
        if (gameDir == "")
            gameDir := ConfigManager.GameDir
        logDir := ConfigManager.LogDir != "" ? ConfigManager.LogDir : gameDir "\zoG_log"
        if (!DirExist(logDir))
            return false
        latestFile := ""
        latestTime := 0
        Loop Files, logDir "\*.txt" {
            if (A_LoopFileTimeModified > latestTime) {
                latestTime := A_LoopFileTimeModified
                latestFile := A_LoopFilePath
            }
        }
        if (latestFile == "")
            return false
        content := FileRead(latestFile)
        if (InStr(content, pattern))
            return true
        return false
    }

    ; 等待条件成立, 超时返回 false
    static WaitFor(conditionFunc, timeoutMs := 5000, checkIntervalMs := 200) {
        start := A_TickCount
        while (A_TickCount - start < timeoutMs) {
            if (conditionFunc.Call())
                return true
            Sleep(checkIntervalMs)
        }
        return false
    }

    ; 执行标准登录流程
    ; 使用 ControlSend 后台输入, 不要求窗口激活 (D3D9 游戏兼容)
    ; 返回 true/false
    static DoLogin() {
        hGame := "ahk_exe " ConfigManager.GameExe
        phaseStart := A_TickCount

        if (!this.IsGameRunning())
            return false

        passX := ConfigManager.ReadCoord("Login", "Login_PasswordX", 400)
        passY := ConfigManager.ReadCoord("Login", "Login_PasswordY", 330)
        confirmX := ConfigManager.ReadCoord("Login", "Login_ConfirmX", 512)
        confirmY := ConfigManager.ReadCoord("Login", "Login_ConfirmY", 400)
        chanTaskX := ConfigManager.ReadCoord("Login", "Channel_TaskMode_X", 512)
        chanTaskY := ConfigManager.ReadCoord("Login", "Channel_TaskMode_Y", 400)
        chanSelX := ConfigManager.ReadCoord("Login", "Channel_Select_X", 512)
        chanSelY := ConfigManager.ReadCoord("Login", "Channel_Select_Y", 400)

        this.ActivateGame()
        Sleep(2000)
        CoordMode "Mouse", "Client"

        ; 密码框
        WinActivate("ahk_exe " ConfigManager.GameExe)
        Sleep(500)
        MouseMove(passX, passY)
        Sleep(500), Click(), Sleep(2000)
        SendInput(ConfigManager.LoginPassword)
        Sleep(3000)
        ; 确认登录
        Logger.Debug("[登录] 点击登入按钮 (" confirmX "," confirmY ")")
        WinActivate("ahk_exe " ConfigManager.GameExe)
        Sleep(500)
        MouseMove(confirmX, confirmY)
        Sleep(500)
        Send "{LButton Down}"
        Sleep(200)
        Send "{LButton Up}"
        Sleep(500)

        ; 验证: 进入频道选择画面 (像素检测)
        Loop 3 {
            Sleep(8000)
            chanDetectX := ConfigManager.ReadCoord("Login", "Channel_DetectPixel_X", 400)
            chanDetectY := ConfigManager.ReadCoord("Login", "Channel_DetectPixel_Y", 350)
            found := PixelSearch(&px, &py, chanDetectX-15, chanDetectY-15, chanDetectX+15, chanDetectY+15, ConfigManager.LoginChannelColor, 40)
            if (found) {
                Logger.Debug("[登录] 检测: 频道选择画面 ✓")
                break
            }
            Logger.Debug("[登录] 检测: 等待频道选择画面 (" A_Index "/3)")
            if (A_Index == 3) {
                Logger.Error("[登录] 未进入频道选择画面")
                return false
            }
        }

        ; 频道-任务模式
        Logger.Info("[频道] 选择任务模式 (" chanTaskX "," chanTaskY ")")
        WinActivate("ahk_exe " ConfigManager.GameExe)
        Sleep(500)
        CoordMode "Mouse", "Client"
        MouseMove(chanTaskX, chanTaskY)
        Sleep(500)
        Loop 5 {
            Send "{LButton Down}"
            Sleep(200)
            Send "{LButton Up}"
            Sleep(800)
        }
        ControlClick("x" chanTaskX " y" chanTaskY, "ahk_exe " ConfigManager.GameExe)

        ; 验证: 进入频道列表
        imgCL := GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\channel_list.png")
        WinGetPos(&gx, &gy, &gw, &gh, "ahk_exe " ConfigManager.GameExe)
        Loop 3 {
            Sleep(3000)
            if (ImageSearch(&px, &py, gx, gy, gx + gw, gy + gh, "*120 " imgCL)) {
                Logger.Debug("[频道] 检测: 频道列表 ✓")
                break
            }
            Logger.Debug("[频道] 检测: 等待频道列表 (" A_Index "/3)")
            if (A_Index == 3) {
                Logger.Error("[频道] 未进入频道列表")
                return false
            }
        }

        ; 频道-初级频道1
        Logger.Info("[频道] 选择初级频道1 (" chanSelX "," chanSelY ")")
        WinActivate("ahk_exe " ConfigManager.GameExe)
        Sleep(500)
        CoordMode "Mouse", "Client"
        MouseMove(chanSelX, chanSelY)
        Sleep(500)
        Loop 5 {
            Send "{LButton Down}"
            Sleep(200)
            Send "{LButton Up}"
            Sleep(800)
        }
        ControlClick("x" chanSelX " y" chanSelY, "ahk_exe " ConfigManager.GameExe)

        ; 验证: 进入大厅
        imgLobby := GameUtils.ResolveImagePath(A_ScriptDir "\Data\Images\lobby.png")
        WinGetPos(&gx, &gy, &gw, &gh, "ahk_exe " ConfigManager.GameExe)
        Loop 3 {
            Sleep(3000)
            if (ImageSearch(&px, &py, gx, gy, gx + gw, gy + gh, "*120 " imgLobby)) {
                Logger.Debug("[频道] 检测: 大厅 ✓")
                break
            }
            Logger.Debug("[频道] 检测: 等待大厅 (" A_Index "/3)")
            if (A_Index == 3) {
                Logger.Error("[频道] 未进入大厅")
                return false
            }
        }
        Sleep(3000)

        elapsed := Round((A_TickCount - phaseStart) / 1000, 1)
        Logger.Info("[登录] 完成 — 耗时 " elapsed "s")
        return this.IsGameRunning()
    }
}
