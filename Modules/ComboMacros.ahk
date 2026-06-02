; ComboMacros.ahk — 连招宏模块
; 录制/回放按键序列, 仅游戏窗口生效
; 游戏内热键 F1~F8, 全局控制 Ctrl+Alt+F1~F8 用于录制

global g_ComboMacros_Enabled := false
global g_ComboMacros_Recording := false
global g_ComboMacros_RecordSlot := 1
global g_ComboMacros_RecordedKeys := ""
global g_ComboMacros_RecordStart := 0
global g_ComboMacroSequences := Map()  ; slot# → [{"key":"a","delay":50,"count":1}, ...]

ComboMacros_Init() {
    ; 从配置加载已保存的序列
    loop 8 {
        seqStr := ConfigManager.Read("ComboMacros", "Macro" A_Index "_Sequence", "")
        if (seqStr != "") {
            try {
                sequences := []
                ; 格式: "key,delay,count;key,delay,count;..."
                parts := StrSplit(seqStr, ";")
                for part in parts {
                    if (part == "")
                        continue
                    fields := StrSplit(part, ",")
                    if (fields.Length >= 2)
                        sequences.Push({key: fields[1], delay: Integer(fields[2]), count: fields.Length >= 3 ? Integer(fields[3]) : 1})
                }
                g_ComboMacroSequences[A_Index] := sequences
            }
        }
    }
    Logger.Info("ComboMacros 模块初始化完成 (已加载 " g_ComboMacroSequences.Count " 个宏序列)")
}

ComboMacros_Start() {
    g_ComboMacros_Enabled := true
    Logger.Info("ComboMacros: 已启动 (F1~F8=播放, Ctrl+Alt+F1~F8=录制)")
}

ComboMacros_Stop() {
    g_ComboMacros_Enabled := false
    g_ComboMacros_Recording := false
    Logger.Info("ComboMacros: 已停止")
}

ComboMacros_Tick() {
    ; 占位
}

ComboMacros_Cleanup() {
    ComboMacros_Stop()
    Logger.Info("ComboMacros: 已清理")
}

; 开始录制 (slot: 1-8)
ComboMacros_StartRecording(slot) {
    if (!GameUtils.IsGameActive()) {
        Logger.Warn("ComboMacros: 录制需要在游戏窗口激活时进行")
        return false
    }
    g_ComboMacros_Recording := true
    g_ComboMacros_RecordSlot := slot
    g_ComboMacros_RecordedKeys := ""
    g_ComboMacros_RecordStart := A_TickCount
    Logger.Info("ComboMacros: 开始录制到槽位 " slot " (按 Ctrl+Alt+F" slot " 停止)")
    ; 注意: 实际录制通过 Hotkey 钩子捕获按键, 这里仅标记状态
    ToolTip("🔴 录制中... 按 Ctrl+Alt+F" slot " 停止", , , 1)
    return true
}

; 停止录制并保存
ComboMacros_StopRecording() {
    if (!g_ComboMacros_Recording)
        return
    g_ComboMacros_Recording := false
    ToolTip("", , , 1)
    duration := A_TickCount - g_ComboMacros_RecordStart
    Logger.Info("ComboMacros: 录制停止 (槽位 " g_ComboMacros_RecordSlot ", 持续 " Round(duration/1000, 1) "s)")

    ; 解析录制的按键序列
    sequences := ComboMacros_ParseRecording()
    if (sequences.Length == 0) {
        Logger.Warn("ComboMacros: 录制的序列为空")
        return
    }
    g_ComboMacroSequences[g_ComboMacros_RecordSlot] := sequences
    ; 保存到配置文件
    ComboMacros_SaveToConfig(g_ComboMacros_RecordSlot, sequences)
    Logger.Info("ComboMacros: 宏已保存到槽位 " g_ComboMacros_RecordSlot " (" sequences.Length " 个动作)")
}

; 解析录制数据为序列
ComboMacros_ParseRecording() {
    ; 简化实现: 将录制的原始字符串转为序列
    ; 格式: "key,timestamp;key,timestamp;..."
    if (g_ComboMacros_RecordedKeys == "")
        return []
    sequences := []
    entries := StrSplit(g_ComboMacros_RecordedKeys, ";")
    prevTime := g_ComboMacros_RecordStart
    for entry in entries {
        if (entry == "")
            continue
        parts := StrSplit(entry, ",")
        if (parts.Length >= 2) {
            key := parts[1]
            ts := Integer(parts[2])
            delay := ts - prevTime
            prevTime := ts
            sequences.Push({key: key, delay: Max(30, delay), count: 1})
        }
    }
    return sequences
}

; 保存序列到配置文件
ComboMacros_SaveToConfig(slot, sequences) {
    seqStr := ""
    for s in sequences {
        if (seqStr != "")
            seqStr .= ";"
        seqStr .= s.key "," s.delay "," s.count
    }
    ConfigManager.Write("ComboMacros", "Macro" slot "_Sequence", seqStr)
}

; 播放指定槽位的连招宏
ComboMacros_PlayMacro(slot) {
    if (!g_ComboMacros_Enabled || !GameUtils.IsGameActive())
        return
    if (!g_ComboMacroSequences.Has(slot) || g_ComboMacroSequences[slot].Length == 0) {
        Logger.Warn("ComboMacros: 槽位 " slot " 无序列")
        return
    }
    sequences := g_ComboMacroSequences[slot]
    for seq in sequences {
        if (!GameUtils.IsGameActive())  ; 中途失去焦点则停止
            break
        loop seq.count {
            GameUtils.SendGameKey("{" seq.key "}", seq.delay)
        }
    }
}

; 录制按键钩子 (在主脚本 Hotkey 中调用)
ComboMacros_HookKey(keyName) {
    if (!g_ComboMacros_Recording)
        return
    ts := A_TickCount
    if (g_ComboMacros_RecordedKeys != "")
        g_ComboMacros_RecordedKeys .= ";"
    g_ComboMacros_RecordedKeys .= keyName "," ts
}
