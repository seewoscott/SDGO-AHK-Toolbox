; DailyRewards.ahk — 每日奖励自动领奖模块
; 菜单导航 + 像素/图片检测按钮

global g_DailyRewards_Enabled := false
global g_DailyRewards_Running := false
global g_DailyRewards_Timer := 0

DailyRewards_Init() {
    Logger.Info("DailyRewards 模块初始化完成")
}

DailyRewards_Start() {
    if (!GameUtils.IsGameRunning()) {
        Logger.Warn("DailyRewards: 游戏未运行")
        return false
    }
    g_DailyRewards_Enabled := true
    DailyRewards_Execute()
    Logger.Info("DailyRewards: 已启动")
    return true
}

DailyRewards_Stop() {
    g_DailyRewards_Enabled := false
    g_DailyRewards_Running := false
    if (g_DailyRewards_Timer)
        SetTimer(g_DailyRewards_Timer, 0)
    Logger.Info("DailyRewards: 已停止")
}

DailyRewards_Tick() {
    ; 占位, 实际领奖是一次性操作
}

DailyRewards_Cleanup() {
    DailyRewards_Stop()
    Logger.Info("DailyRewards: 已清理")
}

; 执行领奖流程
DailyRewards_Execute() {
    if (g_DailyRewards_Running)
        return
    g_DailyRewards_Running := true
    Logger.Info("DailyRewards: 开始领奖流程")

    if (!GameUtils.ActivateGame()) {
        Logger.Error("DailyRewards: 无法激活游戏窗口")
        g_DailyRewards_Running := false
        return
    }
    Sleep(1000)

    ; 步骤1: 打开奖励菜单
    rewardX := ConfigManager.Read("DailyRewards", "Menu_Reward_X", 900)
    rewardY := ConfigManager.Read("DailyRewards", "Menu_Reward_Y", 50)
    GameUtils.GameClick(rewardX, rewardY)
    Sleep(2000)

    ; 步骤2: 检测并点击领取按钮
    detectionMode := ConfigManager.Read("DailyRewards", "DetectionMode", "pixel")

    if (detectionMode == "pixel") {
        DailyRewards_FindByPixel()
    } else if (detectionMode == "image") {
        DailyRewards_FindByImage()
    }

    ; 步骤3: 确认对话框
    Sleep(1000)
    GameUtils.SendGameKeyOnce("Enter", 500)
    Sleep(2000)

    ; 步骤4: 关闭菜单, 返回游戏
    Loop 3 {
        GameUtils.SendGameKeyOnce("Escape", 500)
    }

    Logger.Info("DailyRewards: 领奖流程完成")
    g_DailyRewards_Running := false
    g_DailyRewards_Enabled := false  ; 一次性操作, 完成后自动停止
}

; 像素颜色检测方式
DailyRewards_FindByPixel() {
    btnColor := ConfigManager.Read("DailyRewards", "ButtonColor", "0xFFDD00")
    area := ConfigManager.Read("DailyRewards", "ButtonArea", "400,300,600,500")
    ; 解析区域坐标
    areaParts := StrSplit(area, ",")
    if (areaParts.Length < 4) {
        Logger.Error("DailyRewards: ButtonArea 配置无效")
        return false
    }
    x1 := Integer(areaParts[1]), y1 := Integer(areaParts[2])
    x2 := Integer(areaParts[3]), y2 := Integer(areaParts[4])

    result := GameUtils.PixelSearch(x1, y1, x2, y2, btnColor, 20)
    if (result) {
        Logger.Info("DailyRewards: 像素检测找到按钮 (" result.x ", " result.y ")")
        GameUtils.GameClick(result.x, result.y)
        return true
    } else {
        Logger.Warn("DailyRewards: 像素检测未找到按钮")
        ; 使用备用坐标
        GameUtils.GameClick(512, 400)
        return false
    }
}

; 图像检测方式
DailyRewards_FindByImage() {
    imagePath := A_ScriptDir "\Data\Images\reward_button.png"
    if (!FileExist(imagePath)) {
        Logger.Warn("DailyRewards: 参考图片不存在 (" imagePath "), 回退到像素检测")
        return DailyRewards_FindByPixel()
    }
    result := GameUtils.ImageSearch(imagePath, 0, 0, , , 30)
    if (result) {
        Logger.Info("DailyRewards: 图像检测找到按钮 (" result.x ", " result.y ")")
        GameUtils.GameClick(result.x, result.y)
        return true
    } else {
        Logger.Warn("DailyRewards: 图像检测未找到按钮")
        return DailyRewards_FindByPixel()
    }
}
