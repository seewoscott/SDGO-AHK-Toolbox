# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SDGO工具脚本 — 基于 **AutoHotkey v2** 的 SD高达私服（SDGO UNION 1.4.3）游戏自动化工具箱。通过 GUI 控制面板管理多个自动化模块（刷图、建房、看门狗等），每个模块以独立的状态机运行，由主脚本每秒轮询驱动。

**要求**: AutoHotkey v2.0+，Windows，管理员权限（用于 taskkill 杀进程）。**没有构建系统、测试框架或 CI/CD** — 所有验证都是手动的。

## 架构总览

采用 **Hub-Spoke（中枢-辐条）架构**：

```
SDGO工具脚本.ahk (Hub)
  ├── #Include → Lib/ConfigManager.ahk   (INI 读写 + 分辨率适配)
  ├── #Include → Lib/Logger.ahk          (分级日志 + 文件轮转)
  ├── #Include → Lib/GameUtils.ahk       (游戏窗口检测 + 键鼠发送 + 图像搜索 + 登录)
  │
  ├── #Include → Modules/AutoFarm.ahk       (单人刷图, 当前启用)
  ├── #Include → Modules/AutoFarmMulti.ahk  (多人刷图, 当前启用)
  ├── #Include → Modules/AutoMatch.ahk      (刷场次, 当前启用)
  ├── #Include → Modules/RestartGame.ahk    (重启建房, 当前启用)
  ├── #Include → Modules/FarmWatchdog.ahk   (刷图看门狗, 当前启用)
  │
  └── (独立) Modules/ScreenWatcher.ahk (异常画面监控, 未被主脚本 #Include, 可独立运行)
```

**包含顺序**: ConfigManager → Logger → GameUtils → AutoFarm → RestartGame → AutoFarmMulti → FarmWatchdog → AutoMatch。ScreenWatcher 独立于主脚本，需要时可通过 INI 开关或单独启动。

**运行时模型**: `SetTimer(GuiTick, 1000)` 每秒调用所有已加载模块的 `_Tick()`。每个模块在 Tick 内做像素/图像检测、状态判断和键鼠操作。

## 目录结构

| 目录/文件 | 作用 |
|-----------|------|
| `SDGO工具脚本.ahk` | 主脚本 — GUI、热键、模块调度、紧急停止 |
| `Lib/ConfigManager.ahk` | 静态类，INI 读写 + 类型自动解析 + 分辨率适配坐标回退 |
| `Lib/Logger.ahk` | 静态类，分级日志（DEBUG/INFO/WARN/ERROR）、缓冲刷盘、文件轮转 |
| `Lib/GameUtils.ahk` | 静态类，游戏窗口交互中枢 — 窗口检测、ControlSend/Send 按键、ControlClick 鼠标、PixelSearch/ImageSearch、DoLogin() 登录流程 |
| `Modules/*.ahk` | 功能模块，统一接口（见下文） |
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
- **状态常量定义**（可选）: RestartGame 使用 `RESTART_STATE := Map("IDLE", 0, ...)` 做枚举映射（实际 switch 仍用字符串）

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
| `DoLogin()` | 完整四阶段登录流程 |
| `WaitFor(conditionFunc, timeoutMs:=5000, checkIntervalMs:=200)` | 轮询等待辅助 |

**图像搜索**: `ImageSearch()` 在 D3D9 窗口上兼容性有限，各模块通常使用 `*90~*120` 的容差变体。`PixelSearch()` 更可靠，但同样需要窗口在前景。

**Login 流程** (`DoLogin()`): 四阶段 — 输入密码 → 确认按钮 → 频道选择 (PixelSearch 0x071940) → 频道列表验证 (ImageSearch `channel_list.png`) → 选择初级频道1 → 大厅验证 (ImageSearch `lobby.png`)。

## 模块间协作

- **`ToggleModule("ModuleName")`**: 模块间触发机制。FarmWatchdog 和 ScreenWatcher 检测到异常时调用 `ToggleModule("RestartGame")` 触发自动重启建房（ToggleModule 内部会 Start 已停用的模块或 Stop 已运行的模块）
- **RunCount 共享**: FarmWatchdog 读取 `g_AutoFarm_RunCount`、`g_AutoFarmMulti_RunCount`、`g_AutoMatch_RunCount` 做刷图/场次停滞检测
- **图像回退**: AutoMatch 通过 `GameUtils.ResolveImagePath()` 4-tier 回退自动匹配服务端专属图像（`服务器名_` 前缀）
- **SmartSearch**: ★ 只有 AutoMatch 使用 `GameUtils.SmartSearch()`。AutoFarm 和 AutoFarmMulti 有本地重复实现。**新模块应直接调用 `GameUtils.SmartSearch()`**，不要重新实现。
- **ScreenWatcher**: 未被主脚本 #Include，是独立的可选模块。需要时自行启动或通过 INI 开关启用。

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
| `[RestartGame]` | `Mode` (once/loop), `MaxLoops` (0=无限), `GamePath`/`GameDir`, 导航坐标, 各阶段超时 |
| `[AutoFarm]` | `MaxRuns` (0=无限刷图) |
| `[AutoMatch]` | `MaxRuns` (0=无限), `ReadyPixelX/Y/Color`, `SeekSteps`, `SeekMaxRounds`, `ResultColor` |
| `[FarmWatchdog]` | `Watch_Duration` (停滞检测秒数, 默认 120) |
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
| `F12` | 坐标捕获 — 复制鼠标 Client 坐标+颜色到剪贴板和日志 | 启用 |
| `Ctrl+Alt+R` | 重载脚本 | 启用 |
| `Ctrl+Alt+Esc` | 紧急停止所有模块 | 启用 |

## 图像模板 (Data/Images)

| 文件 | 使用模块 | 用途 | 容差 |
|------|----------|------|------|
| `start_btn.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测开始按钮 | *90 |
| `combat_ui.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测战斗 UI 加载完成 | *90 |
| `end.png` | AutoFarm, AutoFarmMulti, AutoMatch | 检测战斗结束标志 | *90 |
| `OC梦服_start_btn.png` | AutoMatch | 新服开始按钮 (ServerProfile=OC梦服 时自动匹配) | *90 |
| `OC梦服_combat_ui.png` | AutoMatch | 新服战斗 UI (ServerProfile=OC梦服 时自动匹配) | *90 |
| `OC梦服_end.png` | AutoMatch | 新服结束标志 (ServerProfile=OC梦服 时自动匹配) | *90 |
| `lobby.png` | RestartGame, GameUtils | 验证已进入大厅 | *120 |
| `create_room.png` | RestartGame | 验证创建房间界面 | *120 |
| `in_room.png` | RestartGame | 验证已进入房间 | *120 |
| `channel_list.png` | GameUtils | 验证频道列表界面 | *120 |
| `channel_select.png` | GameUtils | 频道选择画面参考 | — |
| `watch.png` | ScreenWatcher | 异常画面监控 | *120 |

## 开发指南

### 添加新模块

1. 创建 `Modules/NewModule.ahk`，遵循 5 函数接口：`NewModule_Init()` / `_Start()` / `_Stop()` / `_Tick()` / `_Cleanup()`
2. 状态机使用字符串状态 + `switch` + `A_TickCount` 超时（参考 RestartGame 的 Transition 模式）
3. 在 `SDGO工具脚本.ahk` 中添加 `#Include "Modules\NewModule.ahk"`，并在 `GuiTick()` 中调用 `NewModule_Tick()`
4. （可选）在 `[General] Hotkeys` 中注册热键，在 `GuiCreate()` 中添加 GUI 控件
5. 在 `Data/Settings.ini` 的对应 `[Server.*]` 节的 `Modules=` 字段中添加模块名

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
- 提交信息: `类型: 简短描述`（如 `fix: ReadyPixel 分辨率适配`, `chore: v1.5.5 → v1.5.6`）
- 版本号更新: 独立 commit `chore: X.Y.Z → X.Y.W`

## 调试与故障排查

```powershell
# 运行脚本（双击或命令行）
.\SDGO工具脚本.ahk

# 查看实时日志
Get-Content "Data\Logs\SDGO_*.log" -Wait -Tail 50
```

**F12 坐标捕获**: 在任意窗口按下 F12，将鼠标所在窗口的 Client 坐标和像素颜色复制到剪贴板，同时写入日志。用于为新分辨率填写 Settings.ini 坐标。

**验证方式**: 本项目没有自动化测试。修改后运行脚本，观察 GUI 状态变化，检查日志输出确认模块行为正确。

**常见问题排查**:
1. 游戏窗口未检测到 → 确认 `gonline.exe` 进程在运行
2. 图像搜索频繁失败 → 检查游戏分辨率是否为 1024x768，桌面分辨率是否与 Settings.ini 中的分辨率节匹配
3. taskkill 失败 → 以管理员身份运行脚本
4. 建房坐标偏移 → 用 F12 在游戏中重新抓取，更新 Settings.ini 中对应分辨率节的坐标
5. 模块不响应 → 检查该服 `[Server.*]` 的 `Modules=` 字段是否包含模块名
