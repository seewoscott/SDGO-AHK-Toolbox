; LAN release updater. Stages the new EXE locally, then replaces it after exit.
class AutoUpdater {
    static s_CheckTimer := 0

    ; 启动周期检查: 挂机工具长时间运行, 不能只靠启动时检查一次。
    ; 间隔由 [Updater] CheckIntervalMinutes 配置 (默认 30 分钟, 0=禁用)。
    static StartPeriodicCheck(currentVersion) {
        if (!A_IsCompiled)
            return false
        intervalMin := ConfigManager.Read("Updater", "CheckIntervalMinutes", 30)
        if (intervalMin <= 0)
            return false
        intervalMs := intervalMin * 60000
        AutoUpdater.s_CheckTimer := SetTimer(AutoUpdater.CheckAndApply.Bind(currentVersion), intervalMs)
        Logger.Info("周期更新检查已启动: 每 " intervalMin " 分钟一次")
        return true
    }

    ; 手动检查更新 (GUI 按钮): 立即检查共享目录并弹窗反馈结果。
    static CheckNow(currentVersion) {
        title := "SDGO工具脚本 - 检查更新"
        if (!A_IsCompiled) {
            MsgBox("当前为源码运行模式，不执行自动更新。", title, 64)
            return false
        }
        if (!ConfigManager.Read("Updater", "Enabled", 1)) {
            MsgBox("更新功能已禁用 (Settings.ini [Updater] Enabled=0)。", title, 48)
            return false
        }
        shareFolder := RTrim(ConfigManager.Read("Updater", "ShareFolder", ""), "\")
        if (shareFolder = "") {
            MsgBox("未配置共享目录 (Settings.ini [Updater] ShareFolder 为空)。", title, 48)
            return false
        }
        versionFile := shareFolder "\" ConfigManager.Read("Updater", "VersionFile", "version.json")
        manifest := AutoUpdater.ReadVersionFile(versionFile)
        if (manifest = "") {
            MsgBox("无法读取更新清单:" "`n" versionFile, title, 48)
            return false
        }
        if !RegExMatch(manifest, '"version"\s*:\s*"([^"\r\n]+)"', &versionMatch) {
            MsgBox("更新清单格式错误: 缺少 version 字段。", title, 48)
            return false
        }
        remoteVersion := versionMatch[1]
        if (AutoUpdater.CompareVersions(remoteVersion, currentVersion) <= 0) {
            MsgBox("当前已是最新版本 v" currentVersion "。", title, 64)
            return false
        }
        ; 有新版本: 复用下载 + SHA-256 校验 + 替换重启流程
        MsgBox("发现新版本 v" remoteVersion "，正在下载并更新...", title, 64)
        result := AutoUpdater.CheckAndApply(currentVersion)
        if (!result)
            MsgBox("更新失败，请查看日志 (Data\Logs)。", title, 48)
        return result
    }

    ; 读取共享目录的 version.json。
    ; AHK v2 的 FileRead 直接读 UNC 网络路径会报错误 67 (找不到网络名),
    ; 但 FileCopy 对 UNC 正常 —— 先复制到本地临时文件再读, 绕开该限制。
    static ReadVersionFile(versionFile) {
        localCopy := A_Temp "\SDGO-version-" A_TickCount ".json"
        try FileCopy(versionFile, localCopy, 1)
        catch as e {
            Logger.Debug("更新检查跳过: 无法读取版本清单 (" e.Message ")")
            return ""
        }
        try manifest := FileRead(localCopy, "UTF-8")
        catch as e {
            Logger.Debug("更新检查跳过: 无法读取本地清单副本 (" e.Message ")")
            return ""
        }
        finally FileDelete(localCopy)
        return manifest
    }

    static CheckAndApply(currentVersion) {
        if (!A_IsCompiled || !ConfigManager.Read("Updater", "Enabled", 1))
            return false
        shareFolder := RTrim(ConfigManager.Read("Updater", "ShareFolder", ""), "\")
        if (shareFolder = "")
            return false
        versionFile := shareFolder "\" ConfigManager.Read("Updater", "VersionFile", "version.json")
        manifest := AutoUpdater.ReadVersionFile(versionFile)
        if (manifest = "")
            return false
        if !RegExMatch(manifest, '"version"\s*:\s*"([^"\r\n]+)"', &versionMatch) {
            Logger.Warn("更新检查跳过: version.json 缺少 version 字段")
            return false
        }
        remoteVersion := versionMatch[1]
        if (AutoUpdater.CompareVersions(remoteVersion, currentVersion) <= 0)
            return false
        if !RegExMatch(manifest, '"file_name"\s*:\s*"([^"\\/\r\n]+)"', &fileMatch) {
            Logger.Warn("更新检查跳过: version.json 缺少或 file_name 不安全")
            return false
        }
        if !RegExMatch(manifest, '"sha256"\s*:\s*"([a-fA-F0-9]{64})"', &hashMatch) {
            Logger.Warn("更新检查跳过: version.json 没有有效的 SHA-256")
            return false
        }
        remoteExe := shareFolder "\" fileMatch[1]
        if !FileExist(remoteExe) {
            Logger.Warn("更新检查跳过: 发布的可执行文件缺失: " remoteExe)
            return false
        }
        ; 校验共享 EXE 的 SHA-256 与清单一致 (防止 Resilio 冲突等导致的
        ; "清单版本超前但 EXE 未更新" 中间状态触发失败更新)
        remoteExeHash := AutoUpdater.GetSha256(remoteExe)
        if (remoteExeHash = "" || StrLower(remoteExeHash) != StrLower(hashMatch[1])) {
            Logger.Warn("更新检查跳过: 共享 EXE 与 version.json 的 SHA-256 不匹配 (可能同步未完成或清单冲突), 等待下次检查")
            return false
        }
        stageExe := A_Temp "\SDGO-update-" A_TickCount ".exe"
        try FileCopy(remoteExe, stageExe, 1)
        catch as e {
            Logger.Warn("更新下载失败: " e.Message)
            return false
        }
        if !FileExist(stageExe) {
            Logger.Warn("更新下载失败: 暂存文件未创建")
            return false
        }
        if (StrLower(AutoUpdater.GetSha256(stageExe)) != StrLower(hashMatch[1])) {
            Logger.Warn("更新下载失败: SHA-256 校验不匹配")
            try FileDelete(stageExe)
            return false
        }
        Logger.Info("发现新版本 v" remoteVersion "，正在应用更新")
        AutoUpdater.RestartWithReplacement(stageExe, A_ScriptFullPath)
        return true
    }

    static GetSha256(filePath) {
        command := "certutil -hashfile " Chr(34) filePath Chr(34) " SHA256"
        try output := ComObject("WScript.Shell").Exec(command).StdOut.ReadAll()
        catch as e {
            Logger.Warn("无法计算更新 SHA-256: " e.Message)
            return ""
        }
        if RegExMatch(output, "i)\b([a-f0-9]{64})\b", &match)
            return match[1]
        return ""
    }

    static CompareVersions(left, right) {
        leftParts := StrSplit(RegExReplace(left, "^[vV]"), ".")
        rightParts := StrSplit(RegExReplace(right, "^[vV]"), ".")
        Loop Max(leftParts.Length, rightParts.Length) {
            l := (A_Index <= leftParts.Length && leftParts[A_Index] ~= "^\d+$") ? Integer(leftParts[A_Index]) : 0
            r := (A_Index <= rightParts.Length && rightParts[A_Index] ~= "^\d+$") ? Integer(rightParts[A_Index]) : 0
            if (l > r)
                return 1
            if (l < r)
                return -1
        }
        return 0
    }

    static RestartWithReplacement(stageExe, targetExe) {
        batchFile := A_Temp "\SDGO-update-" A_TickCount ".cmd"
        q := Chr(34)
        ; 更新后用提权方式重启新 EXE。
        ; 旧版用 start 从隐藏窗口启动, 新 EXE 未继承管理员令牌 →
        ; 启动后再次 Run *RunAs 弹 UAC 框, 无人值守时卡死。
        ; 现在批处理只负责替换文件, 重启交给 AHK 的 Run *RunAs
        ; (Unicode 安全, 支持中文路径, 不会像 cmd 批处理那样代码页乱码)。
        batch := "@echo off`r`n"
            . "timeout /t 2 /nobreak >nul`r`n"
            . "move /y " q stageExe q " " q targetExe q " >nul`r`n"
            . "if errorlevel 1 exit /b 1`r`n"
            . "del " q "%~f0" q "`r`n"
        ; 批处理必须用 ANSI(CP0) 编码写入: cmd.exe 按系统代码页(中文=GBK)解析,
        ; 若用 UTF-8 写入, 含中文的 EXE 路径(如 SDGO工具脚本.exe)会被 cmd 按
        ; GBK 解码成乱码, 导致 move 失败或生成乱码文件名。
        FileAppend(batch, batchFile, "CP0")
        ; 隐藏运行替换批处理, 2 秒后它完成 move; 然后提权启动新 EXE
        Run('"' A_ComSpec '" /c ""' batchFile '""', , "Hide")
        Sleep(2500)
        Run("*RunAs " q targetExe q, A_ScriptDir)
        ExitApp(0)
    }
}
