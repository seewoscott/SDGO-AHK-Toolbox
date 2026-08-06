; FarmWatchdogPolicy.ahk — 看门狗监控源与阈值的纯判断规则

class FarmWatchdogPolicy {
    static NoneSource := "NONE"
    static AutoFarmSource := "AUTO_FARM"
    static AutoFarmMultiSource := "AUTO_FARM_MULTI"
    static AutoMatchSource := "AUTO_MATCH"

    ; 保持既有优先级：单人刷图 > 多人刷图 > 刷场次。
    static ResolveSource(autoFarmEnabled, autoFarmMultiEnabled, autoMatchEnabled) {
        if (autoFarmEnabled)
            return this.AutoFarmSource
        if (autoFarmMultiEnabled)
            return this.AutoFarmMultiSource
        if (autoMatchEnabled)
            return this.AutoMatchSource
        return this.NoneSource
    }

    static IsFarmSource(source) {
        return source == this.AutoFarmSource || source == this.AutoFarmMultiSource
    }

    static DurationForSource(source, farmDuration, matchDuration) {
        return source == this.AutoMatchSource ? matchDuration : farmDuration
    }

    static SourceLabel(source) {
        switch source {
        case this.AutoFarmSource:      return "单人刷图"
        case this.AutoFarmMultiSource: return "多人刷图"
        case this.AutoMatchSource:     return "刷场次"
        default:                       return "无"
        }
    }

    static CountLabel(source) {
        return source == this.AutoMatchSource ? "场次" : "局数"
    }

    static NormalizeDuration(value, fallback) {
        text := String(value)
        return RegExMatch(text, "^[1-9]\d*$") ? Integer(text) : fallback
    }

    static IsThresholdReached(elapsedSeconds, durationSeconds) {
        return elapsedSeconds >= durationSeconds
    }
}
