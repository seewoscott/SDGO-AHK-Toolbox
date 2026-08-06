; AutoMatchPolicy.ahk - AutoMatch 的纯时序与状态判定常量。

class AutoMatchLockSweep {
    static InitialDelayMs := 30
    static IntervalMs := 10
    static StepCount := 10
    static DeltaX := 4
    static SettleMs := 30
}

class AutoMatchPolicy {
    static CombatTickIntervalMs := 200
    static LockedCheckIntervalMs := 1000
    static RoomConfirmFrames := 3
    static LockLossFrames := 3
    static RoomKeyHoldMs := 50
    static WeaponKeyHoldMs := 50
    static PrimaryWeaponSettleMs := 200
    static MasterInterKeyDelayMs := 100
    static PrimaryShotOffsets := [0]
    static ResultCountDelayMs := 1500
    static ResultReturnDelayMs := 11500

    static ShouldStopOutput(outputStart, now, durationSeconds) {
        return outputStart > 0 && now - outputStart >= durationSeconds * 1000
    }

    static IsPrimaryShotDue(shotCount, elapsedMs) {
        return shotCount < this.PrimaryShotOffsets.Length
            && elapsedMs >= this.PrimaryShotOffsets[shotCount + 1]
    }

    static ShouldFallbackFromLock(failureCount) {
        return failureCount >= this.LockLossFrames
    }

    static IsRoomActionDue(lastActionTick, nowTick, timeoutSeconds) {
        return lastActionTick <= 0
            || nowTick - lastActionTick >= Max(1, timeoutSeconds) * 1000
    }

    static RoomActionSequence(roomState) {
        if (roomState == "NOT_READY")
            return ["F5"]
        if (roomState == "MASTER")
            return ["F5", "Enter"]
        return []
    }

    static CombatDetectionDecision(result) {
        if (result.error != "")
            return "ERROR"
        if (result.lock_state == "LOCKED")
            return "LOCKED"
        return "PRIMARY"
    }

    static ShouldCountResult(elapsedMs) {
        return elapsedMs >= this.ResultCountDelayMs
    }

    static ShouldReturnToRoom(elapsedMs) {
        return elapsedMs >= this.ResultReturnDelayMs
    }
}

class AutoMatchRoomIdentityTracker {
    static CreateState() {
        return {
            pending_key: "", pending_count: 0,
            stable_key: "", stable_slot: 0, stable_state: "UNKNOWN",
            ambiguous_count: 0
        }
    }

    static Update(state, result) {
        if (result.status != "OK") {
            state.pending_key := ""
            state.pending_count := 0
            state.ambiguous_count++
            if (state.ambiguous_count >= AutoMatchPolicy.RoomConfirmFrames) {
                state.stable_key := ""
                state.stable_slot := 0
                state.stable_state := "UNKNOWN"
            }
            return {accepted: false, newly_confirmed: false}
        }

        state.ambiguous_count := 0
        candidateKey := result.self_slot_index ":" result.self_state
        if (candidateKey == state.stable_key)
            return {accepted: true, newly_confirmed: false}
        if (candidateKey != state.pending_key) {
            state.pending_key := candidateKey
            state.pending_count := 1
            return {accepted: false, newly_confirmed: false}
        }
        state.pending_count++
        if (state.pending_count < AutoMatchPolicy.RoomConfirmFrames)
            return {accepted: false, newly_confirmed: false}

        state.stable_key := candidateKey
        state.stable_slot := result.self_slot_index
        state.stable_state := result.self_state
        state.pending_key := ""
        state.pending_count := 0
        return {accepted: true, newly_confirmed: true}
    }
}

class AutoMatchPrimaryRunner {
    static RecoveryMs := 3000

    static CreateState() {
        return {active: false, shot_count: 0}
    }

    static Begin(state, actions) {
        this.Stop(state, actions)
        state.active := true
        state.shot_count := 0
        if (AutoMatchPolicy.PrimaryShotOffsets.Length > 0) {
            actions.Fire()
            state.shot_count++
        }
        this.ScheduleNext(state, actions)
    }

    static Step(state, actions) {
        if (!state.active)
            return false
        if (state.shot_count < AutoMatchPolicy.PrimaryShotOffsets.Length) {
            actions.Fire()
            state.shot_count++
            this.ScheduleNext(state, actions)
            return false
        }
        actions.StopTimer()
        state.active := false
        return true
    }

    static Stop(state, actions) {
        actions.StopTimer()
        state.active := false
    }

    static ScheduleNext(state, actions) {
        if (state.shot_count >= AutoMatchPolicy.PrimaryShotOffsets.Length) {
            actions.StartTimer(this.RecoveryMs)
            return
        }
        previousOffset := state.shot_count > 0
            ? AutoMatchPolicy.PrimaryShotOffsets[state.shot_count] : 0
        nextOffset := AutoMatchPolicy.PrimaryShotOffsets[state.shot_count + 1]
        actions.StartTimer(Max(1, nextOffset - previousOffset))
    }
}

class AutoMatchSweepRunner {
    static CreateState() {
        return {active: false, step: 0, x: 0, y: 0, position_initialized: false}
    }

    static Begin(state, actions, lockWeaponKey) {
        this.Stop(state, actions)
        if (!actions.ActivateGame())
            return false
        if (!actions.SelectWeapon(lockWeaponKey))
            return false
        actions.RightButtonUp()
        actions.Delay(AutoMatchLockSweep.InitialDelayMs)
        if (!state.position_initialized) {
            position := actions.GetMousePosition()
            state.x := position.x
            state.y := position.y
            state.position_initialized := true
        }
        state.step := 0
        state.active := true
        actions.StartTimer(AutoMatchLockSweep.IntervalMs)
        return true
    }

    static Step(state, actions) {
        if (!state.active)
            return false
        state.x += AutoMatchLockSweep.DeltaX
        actions.MoveMouse(state.x, state.y)
        state.step++
        if (state.step < AutoMatchLockSweep.StepCount)
            return false

        actions.StopTimer()
        state.active := false
        actions.RightButtonDown()
        return true
    }

    static Stop(state, actions) {
        actions.StopTimer()
        if (state.active)
            actions.RightButtonUp()
        state.active := false
    }

    static ResetPosition(state) {
        state.x := 0
        state.y := 0
        state.step := 0
        state.position_initialized := false
    }
}
