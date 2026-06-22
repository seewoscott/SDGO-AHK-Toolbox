# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SDGO工具脚本 — 基于 **AutoHotkey v2** 的 SD高达私服（SDGO UNION 1.4.3）游戏自动化工具箱。通过 GUI 控制面板管理多个自动化模块（刷图、建房、看门狗等），每个模块以独立的状态机运行，由主脚本每秒轮询驱动。

**要求**: AutoHotkey v2.0+，Windows，管理员权限（用于 taskkill 杀进程）。

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
  ├── #Include → Modules/RestartGame.ahk    (重启建房, 当前启用)
  ├── #Include → Modules/FarmWatchdog.ahk   (刷图看门狗, 当前启用)
  │
  ├── (暂禁) Modules/AntiAFK.ahk       (防掉线 — 心跳+断线重登)
  ├── (暂禁) Modules/ComboMacros.ahk   (连招宏录制/回放)
  └── (暂禁) Modules/DailyRewards.ahk  (每日奖励领取)
  └── (独立) Modules/ScreenWatcher.ahk (异常画面监控, 未被主脚本 #Include)
```

**运行时模型**: `SetTimer(GuiTick, 1000)` 每秒调用所有已加载模块的 `_Tick()`。每个模块在 Tick 内做像素/图像检测、状态判断和键鼠操作，**不得在 Tick 中阻塞超过 ~200ms**。

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


**禁用模块**: 被注释 `#Include` 的模块，主脚本定义同名空桩函数（`ModuleName_Init() => 0` 等），确保编译通过且调用不报错。要启用一个模块：
1. 取消主脚本中对应 `#Include` 的注释
2. 删除主脚本中对应的空桩函数和全局变量定义
3. 取消 GUI 中对应的 GroupBox/Button 注释
4. 取消 `RegisterGlobalHotkeys()` 中对应的 Hotkey 注释

## 游戏窗口交互 (GameUtils)

**目标进程**: `gonline.exe`，D3D9 窗口模式 1024x768。

**输入模式** (配置项 `[Game] InputMode`):
- `control`（默认）: `ControlSend` 后台发送，不需要窗口在前景
- `setforeground`: 先激活窗口再 `Send` 前台发送

**后台鼠标**: 始终使用 `ControlClick`，执行前不激活窗口。

**图像搜索**: `ImageSearch()` 在 D3D9 窗口上兼容性有限（不作为首选），各模块通常使用 `*90~*120` 的容差变体。`PixelSearch()` 更可靠，但同样需要窗口在前景。

**Login 流程** (`DoLogin()`): 四阶段 — 输入密码 "SeewoScott" → 确认按钮 → 频道选择 (PixelSearch 0x071940) → 频道列表验证 (ImageSearch `channel_list.png`) → 选择初级频道1 → 大厅验证 (ImageSearch `lobby.png`)。

## 配置文件 (Data/Settings.ini)

### 分辨率适配机制

存在 `[2880x1800]` 和 `[1920x1080]` 两个分辨率节。脚本启动时检测桌面分辨率，`ConfigManager.ReadCoord()` 优先读取匹配的分辨率节，未找到则回退到通用节。坐标需用 F12 捕获后手工填入。

### 关键配置节

| 节 | 关键选项 |
|----|----------|
| `[General]` | `HotkeyModifier` (默认 `^!`=Ctrl+Alt), `EmergencyStop` (Esc), `GameExe` (gonline.exe) |
| `[Game]` | `InputMode` (control/setforeground), `WindowWidth`/`Height` |
| `[RestartGame]` | `Mode` (once/loop), `MaxLoops` (0=无限), `GamePath`/`GameDir`, 导航坐标, 各阶段超时 |
| `[AutoFarm]` | `MaxRuns` (0=无限刷图) |
| `[FarmWatchdog]` | `Watch_Duration` (停滞检测秒数, 默认 120) |
| `[AntiAFK]` | `HeartbeatInterval` (秒), `DisconnectPattern`, `MaxReconnectAttempts` |
| `[Logging]` | `LogLevel` (DEBUG/INFO/WARN/ERROR), `MaxLogFiles` (轮转保留数) |
| `[ComboMacros]` | `Macro1_Sequence`~`Macro8_Sequence` (JSON 格式按键序列) |
| `[DailyRewards]` | `DetectionMode` (pixel/image), `ButtonColor`, `ButtonArea` |

## 热键

| 热键 | 功能 | 状态 |
|------|------|------|
| `Ctrl+Alt+F2` | 切换 AutoFarm（单人刷图） | 启用 |
| `Ctrl+Alt+F5` | 切换 RestartGame（重启建房） | 启用 |
| `Ctrl+Alt+F6` | 切换 FarmWatchdog（看门狗） | 启用 |
| `Ctrl+Alt+F7` | 切换 AutoFarmMulti（多人刷图） | 启用 |
| `F12` | 坐标捕获 — 复制鼠标 Client 坐标+颜色到剪贴板和日志 | 启用 |
| `Ctrl+Alt+R` | 重载脚本 | 启用 |
| `Ctrl+Alt+Esc` | 紧急停止所有模块 | 启用 |
| `Ctrl+Alt+F1` | 切换 AntiAFK | 暂禁 |
| `Ctrl+Alt+F3` | 切换 ComboMacros | 暂禁 |
| `Ctrl+Alt+F4` | 切换 DailyRewards | 暂禁 |

## 模块依赖与协作

- **FarmWatchdog** 和 **ScreenWatcher** 检测到异常时，调用 `ToggleModule("RestartGame")` 触发自动重启建房
- **FarmWatchdog** 读取 `AutoFarm`/`AutoFarmMulti` 的 `RunCount` 做刷图停滞检测
- **AntiAFK** 与 **RestartGame** 互斥 — AntiAFK 重连期间设置 `g_AntiAFK_Reconnecting = true`，RestartGame 的 Tick 检查此标志后跳过本轮
- 所有模块依赖 `GameUtils`（游戏交互）和 `Logger`（日志），`GameUtils` 依赖 `ConfigManager`（读取配置）

## 图像模板 (Data/Images)

| 文件 | 使用模块 | 用途 | 容差 |
|------|----------|------|------|
| `start_btn.png` | AutoFarm, AutoFarmMulti | 检测开始按钮 | *90 |
| `combat_ui.png` | AutoFarm, AutoFarmMulti | 检测战斗 UI 加载完成 | *90 |
| `end.png` | AutoFarm, AutoFarmMulti | 检测战斗结束标志 | *90 |
| `lobby.png` | RestartGame, GameUtils | 验证已进入大厅 | *120 |
| `create_room.png` | RestartGame | 验证创建房间界面 | *120 |
| `in_room.png` | RestartGame | 验证已进入房间 | *120 |
| `channel_list.png` | GameUtils | 验证频道列表界面 | *120 |
| `channel_select.png` | GameUtils | 频道选择画面参考 | — |
| `watch.png` | ScreenWatcher | 异常画面监控 | *120 |
| `reward_button.png` | DailyRewards | 领取奖励按钮 | *30 |

## 调试与故障排查

```powershell
# 运行脚本（双击或命令行）
.\SDGO工具脚本.ahk

# 查看实时日志
Get-Content "Data\Logs\SDGO_*.log" -Wait -Tail 50
```

**F12 坐标捕获**: 在任意窗口按下 F12，将鼠标所在窗口的 Client 坐标和像素颜色复制到剪贴板，同时写入日志。用于为新分辨率填写 Settings.ini 坐标。

**常见问题排查**:
1. 游戏窗口未检测到 → 确认 `gonline.exe` 进程在运行
2. 图像搜索频繁失败 → 检查游戏分辨率是否为 1024x768，桌面分辨率是否与 Settings.ini 中的分辨节匹配
3. taskkill 失败 → 以管理员身份运行脚本
4. 建房坐标偏移 → 用 F12 在游戏中重新抓取，更新 Settings.ini 中对应分辨率节的坐标
