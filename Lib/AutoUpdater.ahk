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

    static CheckAndApply(currentVersion) {
        if (!A_IsCompiled || !ConfigManager.Read("Updater", "Enabled", 1))
            return false
        shareFolder := RTrim(ConfigManager.Read("Updater", "ShareFolder", ""), "\")
        if (shareFolder = "")
            return false
        versionFile := shareFolder "\" ConfigManager.Read("Updater", "VersionFile", "version.json")
        try manifest := FileRead(versionFile, "UTF-8")
        catch as e {
            Logger.Debug("Update check skipped: cannot read version manifest (" e.Message ")")
            return false
        }
        if !RegExMatch(manifest, '"version"\s*:\s*"([^"\r\n]+)"', &versionMatch) {
            Logger.Warn("Update check skipped: version.json has no version")
            return false
        }
        remoteVersion := versionMatch[1]
        if (AutoUpdater.CompareVersions(remoteVersion, currentVersion) <= 0)
            return false
        if !RegExMatch(manifest, '"file_name"\s*:\s*"([^"\\/\r\n]+)"', &fileMatch) {
            Logger.Warn("Update check skipped: version.json has an unsafe or missing file_name")
            return false
        }
        if !RegExMatch(manifest, '"sha256"\s*:\s*"([a-fA-F0-9]{64})"', &hashMatch) {
            Logger.Warn("Update check skipped: version.json has no valid SHA-256")
            return false
        }
        remoteExe := shareFolder "\" fileMatch[1]
        if !FileExist(remoteExe) {
            Logger.Warn("Update check skipped: release executable is missing: " remoteExe)
            return false
        }
        stageExe := A_Temp "\SDGO-update-" A_TickCount ".exe"
        try FileCopy(remoteExe, stageExe, 1)
        catch as e {
            Logger.Warn("Update download failed: " e.Message)
            return false
        }
        if !FileExist(stageExe) {
            Logger.Warn("Update download failed: staging file was not created")
            return false
        }
        if (StrLower(AutoUpdater.GetSha256(stageExe)) != StrLower(hashMatch[1])) {
            Logger.Warn("Update download failed: SHA-256 mismatch")
            try FileDelete(stageExe)
            return false
        }
        Logger.Info("New version v" remoteVersion " found; applying update")
        AutoUpdater.RestartWithReplacement(stageExe, A_ScriptFullPath)
        return true
    }

    static GetSha256(filePath) {
        command := "certutil -hashfile " Chr(34) filePath Chr(34) " SHA256"
        try output := ComObject("WScript.Shell").Exec(command).StdOut.ReadAll()
        catch as e {
            Logger.Warn("Cannot calculate update SHA-256: " e.Message)
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
        batch := "@echo off`r`n"
            . "timeout /t 2 /nobreak >nul`r`n"
            . "move /y " q stageExe q " " q targetExe q " >nul`r`n"
            . "if errorlevel 1 exit /b 1`r`n"
            . "start " q q " " q targetExe q "`r`n"
            . "del " q "%~f0" q "`r`n"
        FileAppend(batch, batchFile, "UTF-8")
        Run('"' A_ComSpec '" /c ""' batchFile '""', , "Hide")
        ExitApp(0)
    }
}
