; RestartGamePolicy.ahk — 重启建房模式的纯判断规则

class RestartGamePolicy {
    static FarmMode := "FARM"
    static MatchMode := "MATCH"

    static DetectWorkMode(autoFarmEnabled, autoFarmMultiEnabled, autoMatchEnabled) {
        ; 模块意外同时开启时沿用原来的刷图优先级，避免改变既有行为。
        if (autoFarmEnabled || autoFarmMultiEnabled)
            return this.FarmMode
        if (autoMatchEnabled)
            return this.MatchMode
        return this.FarmMode
    }

    static NormalizeWorkMode(workMode) {
        return StrUpper(String(workMode)) == this.MatchMode
            ? this.MatchMode
            : this.FarmMode
    }

    static ShouldSelectTask(workMode) {
        return this.NormalizeWorkMode(workMode) == this.FarmMode
    }

    static NeedsBattleModeSwitch(workMode) {
        return this.NormalizeWorkMode(workMode) == this.MatchMode
    }

    static WorkModeLabel(workMode) {
        return this.NormalizeWorkMode(workMode) == this.MatchMode
            ? "刷场次"
            : "自动刷图"
    }
}
