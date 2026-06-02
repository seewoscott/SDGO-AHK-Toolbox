; ConfigManager.ahk — INI 配置文件读写
; 提供类型化读写和默认值

class ConfigManager {
    static g_IniPath := A_ScriptDir "\Data\Settings.ini"
    static GameDir  := A_Desktop "\SDGO UNION 1.4.3"
    static GamePath := A_Desktop "\SDGO UNION 1.4.3\SDGO_Launcher.exe"
    static GameExe  := "gonline.exe"

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
