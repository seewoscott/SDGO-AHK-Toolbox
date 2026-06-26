; Logger.ahk — 带时间戳的日志输出
; 日志级别: DEBUG < INFO < WARN < ERROR

class Logger {
    static g_LogDir := A_ScriptDir "\Data\Logs"
    static g_LogLevel := "INFO"
    static g_LevelPriority := Map("DEBUG", 0, "INFO", 1, "WARN", 2, "ERROR", 3)
    static g_LogFile := ""
    static g_Buffer := ""
    static g_BufferSize := 0
    static g_MaxBuffer := 1   ; 缓冲行数, 达到后刷盘 (1=立即刷盘, 方便调试)
    static g_MaxLogFiles := 10
    static g_GuiLogCallback := ""

    ; 初始化: 创建日志目录, 清理旧日志
    static Init(level := "INFO", maxFiles := 10) {
        this.g_LogLevel := level
        this.g_MaxLogFiles := maxFiles
        if (!DirExist(this.g_LogDir))
            DirCreate(this.g_LogDir)
        this.RotateLogs()
        this.g_LogFile := this.g_LogDir "\SDGO_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".log"
    }

    ; 轮转旧日志
    static RotateLogs() {
        files := []
        Loop Files, this.g_LogDir "\SDGO_*.log" {
            files.Push({name: A_LoopFilePath, time: A_LoopFileTimeModified})
        }
        ; 冒泡排序 (按时间升序)
        n := files.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (files[j].time > files[j + 1].time) {
                    tmp := files[j]
                    files[j] := files[j + 1]
                    files[j + 1] := tmp
                }
            }
        }
        ; 删除超过数量的旧文件
        if (n >= this.g_MaxLogFiles) {
            Loop n - this.g_MaxLogFiles + 1 {
                try FileDelete(files[A_Index].name)
            }
        }
    }

    ; 核心写入方法
    static Log(level, msg) {
        if (this.g_LevelPriority.Get(level, 0) < this.g_LevelPriority.Get(this.g_LogLevel, 1))
            return
        ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        line := "[" ts "] [" level "] " msg "`n"
        this.g_Buffer .= line
        this.g_BufferSize++
        if (this.g_BufferSize >= this.g_MaxBuffer || level == "ERROR")
            this.Flush()
        ; 通知 GUI (如果已注册回调)
        if (this.g_GuiLogCallback != "")
            SetTimer(this.g_GuiLogCallback, -1)
    }

    static Debug(msg) => this.Log("DEBUG", msg)
    static Info(msg)  => this.Log("INFO", msg)
    static Warn(msg)  => this.Log("WARN", msg)
    static Error(msg) => this.Log("ERROR", msg)

    ; 刷盘
    static Flush() {
        if (this.g_Buffer == "" || this.g_LogFile == "")
            return
        try FileAppend(this.g_Buffer, this.g_LogFile, "UTF-8")
        this.g_Buffer := ""
        this.g_BufferSize := 0
    }

    ; 注册 GUI 日志更新回调
    static RegisterGuiCallback(funcName) {
        this.g_GuiLogCallback := funcName
    }

    ; 获取所有日志行 (供 GUI 日志面板)
    static GetLines(maxLines := 200) {
        if (this.g_LogFile == "" || !FileExist(this.g_LogFile))
            return []
        content := FileRead(this.g_LogFile)
        lines := StrSplit(content, "`n")
        if (lines.Length <= maxLines)
            return lines
        result := []
        start := lines.Length - maxLines + 1
        Loop maxLines {
            result.Push(lines[start + A_Index - 1])
        }
        return result
    }
}
