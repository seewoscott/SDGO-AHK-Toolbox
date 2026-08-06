# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SDGO工具脚本 — 基于 **AutoHotkey v2** 的 SD高达私服（SDGO UNION 1.4.3）游戏自动化工具箱。通过 GUI 控制面板管理多个自动化模块（刷图、建房、看门狗等），每个模块以独立的状态机运行，由主脚本每秒轮询驱动。

**要求**: AutoHotkey v2.0+，Windows，管理员权限（用于 taskkill 杀进程）。没有构建系统或 CI/CD。策略层（`Lib/*Policy.ahk`）有 `tests/` 下的单元测试；模块状态机、图像检测、键鼠输入等行为仍需手动验证。

## 架构总览

采用 **Hub-Spoke（中枢-辐条）架构**：

```
SDGO工具脚本.ahk (Hub)
  ├── #Include → Lib/ConfigManager.ahk        (INI 读写 + 分辨率适配)
  ├── #Include → Lib/Logger.ahk               (分级日志 + 文件轮转)
  ├── #Include → Lib/ScreenCapture.ahk        (GDI BitBlt 截图)
  ├── #Include → Lib/TargetLockDetector.ahk   (锁定框检测)
  ├── #Include → Lib/CombatTargetDetector.ahk (敌方标记检测)
  ├── #Include → Lib/RoomSelfDetector.ahk     (房间 12 槽状态检测)
  ├── #Include → Lib/AutoMatchPolicy.ahk      (AutoMatch 时序/策略类)
  ├── #Include → Lib/RestartGamePolicy.ahk    (重启建房工作模式纯规则)
  ├── #Include → Lib/FarmWatchdogPolicy.ahk   (看门狗监控源/阈值纯规则)
  ├── #Include → Lib/GameUtils.ahk            (游戏窗口交互中枢)
  ├── #Include → Lib/OverlayManager.ahk       (透明覆盖层)
  │
  ├── #Include → Modules/AutoFarm.ahk          (单人刷图)
  ├── #Include → Modules/AutoFarmMulti.ahk     (多人刷图)
  ├── #Include → Modules/AutoMatch.ahk         (刷场次)
  ├── #Include → Modules/RestartGame.ahk       (重启建房)
  ├── #Include → Modules/FarmWatchdog.ahk      (刷图看门狗)
  │
  └── Modules/ScreenWatcher.ahk (异常画面监控, 未被 #Include, 独立运行)
```

**包含顺序**: ConfigManager → Logger → ScreenCapture → TargetLockDetector → CombatTargetDetector → RoomSelfDetector → AutoMatchPolicy → RestartGamePolicy → FarmWatchdogPolicy → GameUtils → 各功能模块。ScreenWatcher 独立于主脚本，需要时可通过 INI 开关或单独启动。

**运行时模型**: `SetTimer(GuiTick, 1000)` 每秒调用所有已加载模块的 `_Tick()`。每个模块在 Tick 内做像素/图像检测、状态判断和键鼠操作。

## 目录结构

| 目录/文件 | 作用 |
|-----------|------|
| `SDGO工具脚本.ahk` | 主脚本 — GUI、热键、模块调度、紧急停止 |
| `Lib/ConfigManager.ahk` | 静态类，INI 读写 + 类型自动解析 + 分辨率适配坐标回退 |
| `Lib/Logger.ahk` | 静态类，分级日志（DEBUG/INFO/WARN/ERROR）、缓冲刷盘、文件轮转 |
| `Lib/ScreenCapture.ahk` | GDI BitBlt 截图 + `CountColorMatches()` 颜色计数，被三个 Detector 共享 |
| `Lib/TargetLockDetector.ahk` | 绿色锁定框检测 → `"LOCKED"/"UNLOCKED"` |
| `Lib/CombatTargetDetector.ahk` | 红色敌方标记检测 → `{presence, count}` + 锁定状态 |
| `Lib/RoomSelfDetector.ahk` | 房间 12 槽状态检测 (EMPTY/MASTER/READY/NOT_READY) + 自身槽识别 |
| `Lib/AutoMatchPolicy.ahk` | AutoMatch 子模块：策略/扫动/主攻/身份追踪类 |
| `Lib/RestartGamePolicy.ahk` | 静态类，重启建房工作模式 (FARM/MATCH) 纯规则 |
| `Lib/FarmWatchdogPolicy.ahk` | 静态类，看门狗监控源/阈值纯规则 |
| `Lib/OverlayManager.ahk` | 透明覆盖层 GUI，显示房间/战斗/AutoMatch 状态 |
| `Lib/GameUtils.ahk` | 静态类，游戏窗口交互中枢 — 窗口检测、ControlSend/Send 按键、ControlClick 鼠标、PixelSearch/ImageSearch、DoLogin() 登录流程 |
| `Modules/*.ahk` | 功能模块，统一接口（见下文） |
| `tests/*.ahk` | 策略层单元测试（见"测试"节） |
| `Data/Images/*.png` | 图像模板 — 用于 ImageSearch 检测游戏画面状态 |
| `Data/Logs/` | 日志输出目录，文件名格式 `SDGO_yyyyMMdd_HHmmss.log` |
| `Data/Settings.ini` | 用户配置文件 |

## 模块接口约定

每个模块文件定义一个命名空间（如 `AutoFarm`），通过以下全局函数与主脚本交互：

| 函数 | 约定 |
|------|------|
| `ModuleName_Init()` | 初始化：读取配置、设置全局变量、初始化状态 |
| `ModuleName_Start()` | 启动模块、设置 `g_ModuleName_Enabled := true` |
| `ModuleName_Stop()` | 停止模块、重置状态机、`g_ModuleName_Enabled := false` |
| `ModuleName_Tick()` | 每秒由主脚本调用，执行状态机逻辑。内部做早期返回检查（模块是否启用、游戏是否运行等） |
| `ModuleName_Cleanup()` | 退出时清理资源 |

### 状态机模式

每个模块内部使用字符串状态驱动，遵循以下模式：

- **状态变量**: `g_ModuleName_State` (字符串，如 `"WAIT_START"`)
- **状态计时**: `g_ModuleName_StateStart` (记录进入状态的 `A_TickCount`)，通过 `A_TickCount - g_ModuleName_StateStart` 计算超时
- **状态流转**: 在 `Tick()` 的 `switch` 中按状态处理，状态切换直接赋值 `g_ModuleName_State := "NEXT_STATE"`
- **状态常量定义**: RestartGame 定义了 `RESTART_STATE` Map（但未被 switch 使用，仅作参考），实际流转仍用字符串直接比较

典型 Tick 结构（以 RestartGame 为推荐范例）：

```ahk
RestartGame_Tick() {
    if (!g_RestartGame_Enabled)
        return
    RestartGame_CheckTimeout()      ; 统一超时检测
    RestartGame_ProcessState()      ; 委派给子方法
}
RestartGame_ProcessState() {
    switch g_RestartGame_State {
    case "KILLING_PROCESS":   RestartGame_DoKillProcess()
    case "LAUNCHING_GAME":    RestartGame_DoLaunchGame()
    case "LOGGING_IN":        RestartGame_DoLogin()
    ...
    }
}
```

Transition 辅助函数（来自 RestartGame）:

```ahk
RestartGame_Transition(newState) {
    global g_RestartGame_State, g_RestartGame_StateStartTime
    g_RestartGame_State := newState
    g_RestartGame_StateStartTime := A_TickCount
}
```

**Tick 内禁止**: `Sleep > 200ms`、阻塞性循环、`MsgBox` 或任何让 Tick 执行超过 ~500ms 的操作。超时用 `A_TickCount` 轮询而非 Sleep。AutoFarmMulti 的 COMBAT 状态有内部循环（900ms Sleep × 多次）— 这是已知的反模式，新模块不要模仿。

**模块可见性**: 每个 `[Server.*]` 节通过 `Modules=` 字段声明该服支持的模块（逗号分隔）。运行时自动显隐对应 GUI 控件，热键对不支持模块拒绝启动并提示。加新服只需在 INI 中列出模块名，不改源码。

## 游戏窗口交互 (GameUtils)

**目标进程**: `gonline.exe`，D3D9 窗口模式 1024x768。

**输入模式** (配置项 `[Game] InputMode`):
- `control`（默认）: `ControlSend` 后台发送，不需要窗口在前景
- `setforeground`: 先激活窗口再 `Send` 前台发送

**后台鼠标**: 始终使用 `ControlClick`，执行前不激活窗口。

**坐标模式**: `CoordMode` 在需要处局部设置（如 `DoLogin()` 中设置 `CoordMode "Mouse", "Client"`），没有全局 CoordMode 声明。

**窗口缓存**: `IsGameRunning()`、`IsGameActive()`、`GetWindowRect()` 使用 `A_TickCount` 做每 Tick 缓存（`s_LastRunningTick`/`s_LastRectTick`），避免每 Tick 多次 WinExist/WinGetPos。

### GameUtils 关键函数

| 函数 | 说明 |
|------|------|
| `IsGameRunning()` | 检测 `gonline.exe` 进程是否存在 |
| `GetWindowRect()` | 返回 `{x, y, w, h}` 对象或 `false` |
| `ActivateGame()` | WinActivate → WinWaitActive，用于 setforeground 模式 |
| `SendGameKey(key, delay:=0)` | 按 InputMode 选择 ControlSend 或 Send |
| `GameClick(x, y, button:="Left", clicks:=1)` | ControlClick 后台点击 |
| `PixelSearch(x1, y1, x2, y2, color, variation:=10)` | 像素颜色搜索 |
| `ImageSearch(imagePath, x1:=0, y1:=0, x2:="", y2:="", variation:=30)` | 图像模板搜索 |
| `SmartSearch(&outX, &outY, imagePath, x1, y1, x2, y2, cacheObj, cacheSize:=60)` | 带缓存/回退的智能图像搜索（★ 新模块应使用此共享版本，不要重新实现） |
| `ResolveImagePath(baseName)` | 4-tier 回退：先查 `服务器名_文件名`、`文件名_分辨率`、`文件名`，最后原路径 |
| `SendGameKeyHeld(key, holdMs, delay, forceForeground)` | 按下→保持 holdMs 毫秒→抬起；用于 D3D9 接口不支持瞬时按键的场景 |
| `CheckLogFile(pattern, gameDir)` | 在 `zoG_log` 目录的最新日志中搜索字符串 |
| `DoLogin(workMode := "FARM")` | 四阶段登录流程；FARM 模式登录后选任务，MATCH 模式切换对战模式 |
| `WaitFor(conditionFunc, timeoutMs:=5000, checkIntervalMs:=200)` | 轮询等待辅助 |

**图像搜索**: `ImageSearch()` 在 D3D9 窗口上兼容性有限，各模块通常使用 `*90~*120` 的容差变体。`PixelSearch()` 更可靠，但同样需要窗口在前景。

**Login 流程** (`DoLogin(workMode)`): 四阶段 — 输入密码 → 确认按钮 → 频道选择 (PixelSearch 0x071940) → 频道列表验证 (ImageSearch `channel_list.png`) → 选择初级频道1 → 大厅验证 (ImageSearch `lobby.png`)。workMode 决定大厅后的动作：FARM=选任务，MATCH=切换对战模式。

## 检测器工具 (Detectors)

四个底层检测组件，由 AutoMatch 和 OverlayManager 调用。共享 `ScreenCapture.ahk` 做 GDI BitBlt 截图以避免重复 D3D9 访问。

| 组件 | 功能 | 输出 |
|------|------|------|
| `ScreenCapture.ahk` | GDI BitBlt 区域截图 + `CountColorMatches()` 颜色计数 | capture 对象 / 匹配数 |
| `TargetLockDetector.ahk` | 画面中心区域绿色锁定括号检测 | `"LOCKED"` / `"UNLOCKED"` |
| `CombatTargetDetector.ahk` | 红色敌方标记检测 + 委托锁检测 | `{presence, count, lock_state}` |
| `RoomSelfDetector.ahk` | 12 槽房间列表检测 + 自己槽识别 | `{self_slot_index, slots[], status}` |

`CombatTargetDetector.Detect()` 接受可选 `sourceCapture` 参数，避免重复截图。`RoomSelfDetector` 通过每槽右侧亮青色边覆盖比例识别"自己"的槽位。

## OverlayManager (透明覆盖层)

**文件**: `Lib/OverlayManager.ahk`

在屏幕上叠加一个半透明面板，实时显示检测状态。锚定在主显示器工作区左下角。

**INI 配置** `[Overlay]`:

| 键 | 默认值 | 说明 |
|----|--------|------|
| `Enabled` | `0` | 0=关闭, 1=启动时自动开启 |
| `Opacity` | `80` | 面板透明度 (0-100) |
| `UpdateInterval` | `3` | 多少 tick 刷新一次检测 |
| `PositionInterval` | `15` | 多少 tick 重定位一次位置 |
| `FontSize` | `9` | 文本字号 |

**显示内容**:
1. 游戏窗口尺寸 + 输入模式
2. 房间 12 槽状态 (EMPTY/MASTER/READY/NOT_READY) + 自己槽
3. 战斗锁定状态 (LOCKED/UNLOCKED) + 目标存在 (PRESENT/ABSENT) + 数量
4. AutoMatch 状态 + 子状态 + 场次计数（仅 AutoMatch 启用时）
5. 时间戳 + 帧计数

**关键方法**: `Init()` → `Tick()`（每秒由 GuiTick 调用）→ `AutoShow()/AutoHide()`（模块调用控制显隐）→ `Toggle()`（F10 热键）→ `Cleanup()`

## 策略层 (Lib/*Policy.ahk)

三个 `*Policy.ahk` 文件构成 **策略层**：静态类、无状态无 I/O、只含纯决策逻辑，因此可直接被 `tests/` 单元测试（`#Include` 该文件即可，无需加载游戏模块或运行 GUI）。★ 新模块的判定规则（工作模式、阈值、优先级等）应抽成 Policy 类并配测试，不要在 Tick 内写死。

| 文件 | 职责 | 关键方法 |
|------|------|----------|
| `AutoMatchPolicy.ahk` | AutoMatch 战斗中的扫动/主攻/判定逻辑 + 2 个 Action 包装类 | 见下方类表 |
| `RestartGamePolicy.ahk` | 重启建房工作模式 FARM/MATCH 判定 | `DetectWorkMode()`（有刷图模块启用→FARM，仅 AutoMatch→MATCH）, `NormalizeWorkMode()`, `ShouldSelectTask()`（FARM 建房需选任务）, `NeedsBattleModeSwitch()`（MATCH 需切对战模式）, `WorkModeLabel()` |
| `FarmWatchdogPolicy.ahk` | 看门狗监控源与阈值判定 | `ResolveSource()`（优先级 单人刷图>多人刷图>刷场次>NONE）, `IsFarmSource()`, `DurationForSource()`, `SourceLabel()`, `CountLabel()`, `NormalizeDuration()`, `IsThresholdReached()` |

### AutoMatchPolicy.ahk 细节

定义了 4 个类 + 2 个 Action 包装类，采用 **策略模式**：Runner 类（纯状态机逻辑）委托 Action 类（I/O 操作），使逻辑可测试。

| 类 | 作用 | 关键字段/方法 |
|----|------|-------------|
| `AutoMatchLockSweep` | 扫动时序常量 | `DeltaX=2`, `StepCount=20`, `IntervalMs=50` |
| `AutoMatchPolicy` | 纯决策逻辑（无状态无 I/O） | `CombatDetectionDecision()`, `ShouldFallbackFromLock()`, `RoomActionSequence()` |
| `AutoMatchRoomIdentityTracker` | 房主身份稳定追踪 | `CreateState()`, `Update(state, result)` — 3 帧确认窗口 |
| `AutoMatchSweepRunner` | 扫动状态机 | `Begin()/Step()/Stop()` — 每步右移 DeltaX |
| `AutoMatchPrimaryRunner` | 主攻定时器 (SetTimer 驱动) | `Begin()/Step()/Stop()` — 每 3 秒一枪 |
| `AutoMatchSweepActions` | 封装扫动的 ActivateGame/SelectWeapon/鼠标操作 | — |
| `AutoMatchPrimaryActions` | 封装主攻的 Fire() + 定时器控制 | — |

**SmartSearch 缓存**: AutoMatch 使用两个独立缓存 — `g_AutoMatch_SearchCache`（`start_btn.png`）和 `g_AutoMatch_CombatCache`（`combat_ui.png`）。

## 测试 (tests/)

`tests/` 下的脚本是策略层的单元/集成测试，用 AutoHotkey64.exe 直接运行（无需构建）：

```powershell
& 'D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\farm_watchdog_policy_test.ahk
& 'D:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' tests\farm_watchdog_integration_test.ahk
```

**约定**: 退出码 0=PASS、1=FAIL；`FileAppend("...", "*")` 输出到 stdout；结尾打印 `<name>: PASS`。两种测试模式：
- **纯策略测试**（`*_policy_test.ahk`）: 直接 `#Include ..\Lib\*.ahk` 被测类，逐条断言。
- **集成测试**（`*_integration_test.ahk`）: 先定义 stub（Logger/GameUtils 空实现、RestartGamePolicy 简化版、`RestartGame_Start()` 桩），再 `#Include` 真实模块，用临时 INI（`ConfigManager.g_IniPath` 指向 `A_Temp` 下文件）驱动 `_Init()`/`_Tick()` 验证状态转换，`finally` 恢复原路径并删临时文件。

## 模块间协作

- **`ToggleModule("ModuleName")`**: 模块间触发机制。FarmWatchdog 和 ScreenWatcher 检测到异常时调用 `ToggleModule("RestartGame")` 触发自动重启建房（ToggleModule 内部会 Start 已停用的模块或 Stop 已运行的模块）
- **RunCount 共享**: FarmWatchdog 通过 `FarmWatchdogPolicy.ResolveSource()` 解析当前监控源（优先级 单人刷图 > 多人刷图 > 刷场次），读取对应模块的 RunCount 做停滞检测；**源切换时重置基准与累计值**（见集成测试）
- **RestartGame 工作模式**: `RestartGame_Start()` 启动时按 `RestartGamePolicy.DetectWorkMode()` 自动判定 FARM/MATCH（有刷图模块启用→FARM，仅 AutoMatch→MATCH），登录阶段（`DoLogin` 前）还会重检一次并可在中途切换；`ShouldSelectTask()`=FARM 建房前选任务，`NeedsBattleModeSwitch()`=MATCH 需切换对战模式
- **RestartGame 挂起看门狗**: `g_RestartGame_Enabled` 期间 FarmWatchdog 清空停滞/缺失计数并置监控源为 NONE，重启完成后再恢复
- **图像回退**: AutoMatch 通过 `GameUtils.ResolveImagePath()` 4-tier 回退自动匹配服务端专属图像（`服务器名_` 前缀）
- **SmartSearch**: ★ 只有 AutoMatch 使用 `GameUtils.SmartSearch()`。AutoFarm 和 AutoFarmMulti 有本地重复实现。**新模块应直接调用 `GameUtils.SmartSearch()`**，不要重新实现。
- **ScreenWatcher**: 未被主脚本 #Include，是独立的可选模块。检测异常画面（`watch.png`）或游戏进程消失持续 `Watch_Duration` 秒（INI `[ScreenWatcher]`，默认 5）后触发重启。可通过 INI 开关或单独启动。

## 配置文件 (Data/Settings.ini)

### 分辨率适配机制

存在 `[2880x1800]` 和 `[1920x1080]` 两个分辨率节。脚本启动时检测桌面分辨率，`ConfigManager.ReadCoord()` 优先读取匹配的分辨率节，未找到则回退到通用节。坐标需用 F12 捕获后手工填入。

### 3 层配置回退

`[Server.<Profile>]` → `[General]` → 硬编码默认值，由 `ConfigManager.ReadServer()` 实现。`ParseValue()` 自动类型解析：`\d+`→整数，`\d+\.\d+`→浮点，`"0"`/`"1"`→数字。

### 关键配置节

| 节 | 关键选项 |
|----|----------|
| `[General]` | `HotkeyModifier` (默认 `^!`=Ctrl+Alt), `EmergencyStop` (Esc), `GameExe` (gonline.exe) |
| `[Game]` | `InputMode` (control/setforeground), `WindowWidth`/`Height`, `ServerProfile` |
| `[RestartGame]` | `Mode` (once/loop), `MaxLoops` (0=无限), `LoopDelay`, `MaxRetries`, `GamePath`/`GameDir`, 导航坐标, 各阶段超时。工作模式不由 INI 配置，由启用模块自动判定 (FARM/MATCH) |
| `[AutoFarm]` | `MaxRuns` (0=无限刷图) |
| `[AutoMatch]` | `MaxRuns` (0=无限), `ReadyTimeout`, `PrimaryWeaponKey`, `LockWeaponKey`, `ResultColor` |
| `[FarmWatchdog]` | `Farm_Stall_Duration` (刷图停滞阈值秒, 默认 180), `Match_Stall_Duration` (刷场次阈值秒, 默认 1200), `NoGame_Duration` (游戏缺失秒, 默认 60)。旧 `Watch_Duration` 仅作为刷图阈值的兼容回退 |
| `[Overlay]` | `Enabled` (0/1), `Opacity` (0-100), `UpdateInterval`/`PositionInterval` (tick 数), `FontSize` |
| `[Login]` | 登录流程坐标 (`Login_PasswordX/Y`, `Login_ConfirmX/Y`, `Channel_*`) |
| `[Server.<Profile>]` | `Modules` (逗号分隔的模块清单), `GameExe`, `LauncherExe`, `GameDir`, `GamePath`, `LoginPassword`, `LoginChannelColor`, `LogDir` |
| `[Logging]` | `LogLevel` (DEBUG/INFO/WARN/ERROR), `MaxLogFiles` (轮转保留数) |

## 热键

| 热键 | 功能 | 状态 |
|------|------|------|
| `F5` | 切换 RestartGame（重启建房） | 启用 |
| `F6` | 切换 FarmWatchdog（看门狗） | 启用 |
| `F7` | 切换 AutoFarm（单人刷图） | 启用 |
| `F8` | 切换 AutoFarmMulti（多人刷图） | 启用 |
| `F9` | 切换 AutoMatch（刷场次） | 启用 |
| `F10` | 切换 OverlayManager 覆盖层显隐 | 启用 |
| `F12` | 坐标捕获 — 复制鼠标 Client 坐标+颜色到剪贴板和日志 | 启用 |
| `Ctrl+Alt+R` | 重载脚本 | 启用 |
| `Ctrl+Alt+Esc` | 紧急停止所有模块 | 启用 |

## 图像模板 (Data/Images)

| 文件 | 使用模块 | 用途 | 容差 |
|------|----------|------|------|
| `start_btn.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测开始按钮 | *90 |
| `start_btn_1920x1080.png` | AutoFarm, AutoFarmMulti, AutoMatch | 1920x1080 分辨率下的开始按钮 | *90 |
| `combat_ui.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测战斗 UI 加载完成 | *90 |
| `combat_ui_1920x1080.png` | AutoFarm, AutoFarmMulti, AutoMatch | 1920x1080 分辨率下的战斗 UI | *90 |
| `end.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测战斗结束标志 | *90 |
| `end_1920x1080.png` | AutoFarm, AutoFarmMulti, AutoMatch | 1920x1080 分辨率下的结束标志 | *90 |
| `OC梦服_combat_ui.png` | AutoMatch | 梦服战斗 UI (ServerProfile=OC_CHINA 时自动匹配) | *90 |
| `OC梦服_combat_ui_1920x1080.png` | AutoMatch | 1920x1080 分辨率下的梦服战斗 UI | *90 |
| `lobby.png` | RestartGame, GameUtils | 验证已进入大厅 | *120 |
| `lobby_1920x1080.png` | RestartGame, GameUtils | 1920x1080 分辨率下的大厅 | *120 |
| `create_room.png` | RestartGame | 验证创建房间界面 | *120 |
| `create_room_1920x1080.png` | RestartGame | 1920x1080 分辨率下的创建房间界面 | *120 |
| `in_room.png` | RestartGame | 验证已进入房间 | *120 |
| `in_room_1920x1080.png` | RestartGame | 1920x1080 分辨率下的房间内界面 | *120 |
| `channel_list.png` | GameUtils | 验证频道列表界面 | *120 |
| `channel_list_1920x1080.png` | GameUtils | 1920x1080 分辨率下的频道列表 | *120 |
| `member.png` | — | 未被代码引用，可能为预留 | — |
| `member_1920x1080.png` | — | member.png 的 1920x1080 变体 | — |

> 注意: `OC亚服_*`、`OC梦服_start_btn*`、`OC梦服_end*`、`channel_select.png`、`watch.png` 已从磁盘删除（未提交的删除；`watch.png` 仍被 ScreenWatcher.ahk 引用，`OC亚服_*` 对应模板缺失时该服 ImageSearch 会失败）。若恢复模板请同步更新本表。

## 开发指南

### 添加新模块

1. 创建 `Modules/NewModule.ahk`，遵循 5 函数接口：`NewModule_Init()` / `_Start()` / `_Stop()` / `_Tick()` / `_Cleanup()`
2. 状态机使用字符串状态 + `switch` + `A_TickCount` 超时（参考 RestartGame 的 Transition 模式）
3. 判定规则（工作模式、阈值、优先级等）抽成 `Lib/NewModulePolicy.ahk` 静态类，并在 `tests/` 加对应测试 — 不要写在 Tick 内
4. 在 `SDGO工具脚本.ahk` 中添加 `#Include "Modules\NewModule.ahk"`（及 Policy 文件），并在 `GuiTick()` 中调用 `NewModule_Tick()`
5. （可选）在 `RegisterGlobalHotkeys()` 中注册热键，在 `BuildGui()` 中添加 GUI 控件
6. 在 `Data/Settings.ini` 的对应 `[Server.*]` 节的 `Modules=` 字段中添加模块名

### 添加新图像模板

1. 游戏中按 F12 获取当前鼠标坐标和颜色（写入剪贴板 + 日志）
2. 用截图工具截取目标区域（按钮、UI 元素等），保存为 PNG
3. 放入 `Data/Images/`，按命名约定：`[服务器名_]用途[_WxH].png`
4. 在模块中调用 `GameUtils.ImageSearch()` 或 `GameUtils.SmartSearch()`，容差通常 `*90`~`*120`

### 添加新服务器

只需在 `Data/Settings.ini` 中添加 `[Server.新服名]` 节，填写 `Modules=`（逗号分隔的模块清单）及相关配置。无需修改源码。

### 代码约定

- `#Warn All, Off`（AHK v2 严格警告关闭）
- 全局变量前缀 `g_`，模块状态 `g_ModuleName_State`，启用标志 `g_ModuleName_Enabled`
- 状态名使用 `UPPER_SNAKE_CASE` 字符串
- 日志使用 `Logger.Info()`, `Logger.Warn()`, `Logger.Error()`, `Logger.Debug()`
- 版本号在 `SDGO工具脚本.ahk` 顶部 `APP_VERSION` 中硬编码

### Git 约定

- 分支命名: `fix/描述`, `feature/描述`, `chore/描述`
- 提交信息: `类型: 简短描述`（如 `fix: ReadyPixel 分辨率适配`, `chore: v2.1.1 → v2.2`）
- 版本号更新: 独立 commit `chore: X.Y.Z → X.Y.W`

### AGENTS.md 同步

仓库根目录另有 `AGENTS.md`（给 Codex 的指引），内容与 CLAUDE.md 基本平行但更新滞后。改动架构/接口/配置节时同步更新两份文件，避免两处指引不一致。

## 调试与故障排查

```powershell
# 运行脚本（双击或命令行）
.\SDGO工具脚本.ahk
```

**F12 坐标捕获**: 在任意窗口按下 F12，将鼠标所在窗口的 Client 坐标和像素颜色复制到剪贴板，同时写入日志。用于为新分辨率填写 Settings.ini 坐标。

**验证方式**: 策略层改动先跑 `tests/` 下对应测试（退出码 0=PASS）。模块行为（状态机、图像检测、键鼠输入）没有自动化测试 — 修改后运行脚本，观察 GUI 状态变化，检查日志输出确认行为正确。

**常见问题排查**:
1. 游戏窗口未检测到 → 确认 `gonline.exe` 进程在运行
2. 图像搜索频繁失败 → 检查游戏分辨率是否为 1024x768，桌面分辨率是否与 Settings.ini 中的分辨率节匹配
3. taskkill 失败 → 以管理员身份运行脚本
4. 建房坐标偏移 → 用 F12 在游戏中重新抓取，更新 Settings.ini 中对应分辨率节的坐标
5. 模块不响应 → 检查该服 `[Server.*]` 的 `Modules=` 字段是否包含模块名
