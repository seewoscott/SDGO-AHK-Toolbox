; ConfigManager.ahk — INI 配置文件读写
; 提供类型化读写和默认值
; 支持多服务端配置 (3-tier: [Server.<Profile>] → [General] → 默认值)

class ConfigManager {
    static g_IniPath := A_ScriptDir "\Data\Settings.ini"

    ; 中文显示名映射 (profile key → display name)
    ; 注意: INI 文件的中文值会被 IniRead 乱码, 所以中文映射硬编码在此
    static s_DisplayNames := {OC_ASIA: "OC亚服", OC_CHINA: "OC梦服"}

    ; 服务端动态属性 (由 LoadServerConfig() 设置)
    static ServerProfile := "OC_ASIA"
    static ServerDisplayName := "OC亚服"
    static GameDir  := A_Desktop "\SDGO UNION 1.4.3"
    static GamePath := A_Desktop "\SDGO UNION 1.4.3\SDGO_Launcher.exe"
    static GameExe  := "gonline.exe"
    static LauncherExe := "SDGO_Launcher.exe"
    static LoginPassword := "SeewoScott"
    static LoginChannelColor := "0x071940"
    static RoomName := "炸狗房，新手来~"
    static LogDir := ""

    ; ===== 多服配置支持 =====

    ; 3-tier fallback: [Server.<ServerProfile>] → [General] → 默认值
    static ReadServer(key, default := "") {
        if (this.ServerProfile != "") {
            val := IniRead(this.g_IniPath, "Server." this.ServerProfile, key, "")
            if (val != "")
                return this.ParseValue(val)
        }
        val := IniRead(this.g_IniPath, "General", key, "")
        if (val != "")
            return this.ParseValue(val)
        return default
    }

    ; 从当前服务端配置加载所有动态属性
    static LoadServerConfig() {
        this.ServerProfile := this.Read("Game", "ServerProfile", "OC_ASIA")
        this.ServerDisplayName := this.s_DisplayNames.HasProp(this.ServerProfile)
            ? this.s_DisplayNames.%this.ServerProfile% : this.ServerProfile
        this.GameExe := this.ReadServer("GameExe", "gonline.exe")
        this.LauncherExe := this.ReadServer("LauncherExe", "SDGO_Launcher.exe")
        this.GameDir := this.ReadServer("GameDir", A_Desktop "\SDGO UNION 1.4.3")
        this.GamePath := this.ReadServer("GamePath", this.GameDir "\SDGO_Launcher.exe")
        this.LoginPassword := this.ReadServer("LoginPassword", "SeewoScott")
        this.LoginChannelColor := this.ReadServer("LoginChannelColor", "0x071940")
        this.RoomName := this.ReadServer("RoomName", "炸狗房，新手来~")
        this.LogDir := this.ReadServer("LogDir", "")
    }

    ; 枚举所有 [Server.*] 节, 返回 DisplayName 列表 (用于 GUI 下拉框)
    static GetServerProfiles() {
        profiles := []
        if (!FileExist(this.g_IniPath))
            return profiles
        sections := IniRead(this.g_IniPath)
        for section in StrSplit(sections, "`n", "`r") {
            if (InStr(section, "Server.") == 1) {
                key := SubStr(section, 8)
                displayName := this.s_DisplayNames.HasProp(key) ? this.s_DisplayNames.%key% : key
                profiles.Push(displayName)
            }
        }
        return profiles
    }

    ; 根据 DisplayName 反查 profile key (如 "OC梦服" → "OC_CHINA")
    static GetProfileKey(displayName) {
        for key, dn in this.s_DisplayNames.OwnProps() {
            if (dn == displayName)
                return key
        }
        return displayName
    }

    ; 读取整个 section 为一个简单 Object {key: value, ...}
    ; 避免 AHK v2 class static 方法中 Map() 的作用域问题
    static LoadSection(section) {
        result := {}
        if (!FileExist(this.g_IniPath))
            return result
        raw := IniRead(this.g_IniPath, section)
        if (raw == "")
            return result
        Loop Parse, raw, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line == "" || !InStr(line, "="))
                continue
            eqPos := InStr(line, "=")
            k := SubStr(line, 1, eqPos - 1)
            v := SubStr(line, eqPos + 1)
            result.%k% := this.ParseValue(v)
        }
        return result
    }

    ; 读取单个值 (支持类型和默认值)
    static Read(section, key, default := "") {
        val := IniRead(this.g_IniPath, section, key, "")
        if (val == "")
            return default
        return this.ParseValue(val)
    }

    ; 按分辨率读取坐标: 先查 [2880x1800] 节, 没有再查通用默认值
    static ReadCoord(section, key, defaultVal) {
        global g_ResolutionProfile
        if (g_ResolutionProfile != "") {
            val := IniRead(this.g_IniPath, g_ResolutionProfile, key, "")
            if (val != "")
                return this.ParseValue(val)
        }
        return this.Read(section, key, defaultVal)
    }

    ; 写入单个值
    static Write(section, key, value) {
        IniWrite(value, this.g_IniPath, section, key)
    }

    ; 删除键
    static Delete(section, key := "") {
        if (key == "")
            IniDelete(this.g_IniPath, section)
        else
            IniDelete(this.g_IniPath, section, key)
    }

    ; 解析值类型: 数字返回 Integer/Float, "0"/"1" 返回 Boolean
    static ParseValue(val) {
        if (val == "0" || val == "1") {
            try return Integer(val)
        }
        if (RegExMatch(val, "^\d+$"))
            return Integer(val)
        if (RegExMatch(val, "^\d+\.\d+$"))
            return Float(val)
        return val
    }
}
