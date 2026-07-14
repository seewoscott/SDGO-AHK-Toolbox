#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\AutoMatchPolicy.ahk

AssertEqual(AutoMatchLockSweep.InitialDelayMs, 30, "sweep initial delay")
AssertEqual(AutoMatchLockSweep.IntervalMs, 50, "sweep interval")
AssertEqual(AutoMatchLockSweep.StepCount, 20, "sweep steps")
AssertEqual(AutoMatchLockSweep.DeltaX, 2, "sweep delta")
AssertEqual(AutoMatchLockSweep.SettleMs, 30, "sweep settle")
x := 100
Loop AutoMatchLockSweep.StepCount
    x += AutoMatchLockSweep.DeltaX
AssertEqual(x, 140, "sweep total displacement")

AssertEqual(AutoMatchPolicy.RoomConfirmFrames, 3, "room confirm frames")
AssertEqual(AutoMatchPolicy.LockLossFrames, 3, "lock loss frames")
AssertEqual(AutoMatchPolicy.RoomKeyHoldMs, 50, "room key hold duration")
AssertEqual(AutoMatchPolicy.WeaponKeyHoldMs, 50, "weapon key hold duration")
AssertEqual(AutoMatchPolicy.MasterInterKeyDelayMs, 100, "master key interval")
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[1], 0, "primary shot 1")
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[2], 3000, "primary shot 2")
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[3], 6000, "primary shot 3")
AssertEqual(AutoMatchPrimaryRunner.IntervalMs, 3000, "primary timer interval")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(0, 0), true, "primary first shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(1, 2999), false, "primary second shot early")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(1, 3000), true, "primary second shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(2, 6000), true, "primary third shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(3, 9000), false, "primary sequence complete")
AssertEqual(AutoMatchPolicy.ShouldFallbackFromLock(2), false, "lock loss frame 2")
AssertEqual(AutoMatchPolicy.ShouldFallbackFromLock(3), true, "lock loss frame 3")
AssertEqual(AutoMatchPolicy.IsRoomActionDue(0, 1000, 5), true, "first room action due")
AssertEqual(AutoMatchPolicy.IsRoomActionDue(1000, 5999, 5), false, "room action rate limited")
AssertEqual(AutoMatchPolicy.IsRoomActionDue(1000, 6000, 5), true, "room action retry due")
memberActions := AutoMatchPolicy.RoomActionSequence("NOT_READY")
AssertEqual(memberActions.Length, 1, "member action count")
AssertEqual(memberActions[1], "F5", "member action F5")
masterActions := AutoMatchPolicy.RoomActionSequence("MASTER")
AssertEqual(masterActions.Length, 2, "master action count")
AssertEqual(masterActions[1], "F5", "master action F5 first")
AssertEqual(masterActions[2], "Enter", "master action Enter second")
AssertEqual(AutoMatchPolicy.RoomActionSequence("UNKNOWN").Length, 0, "unknown no action")
AssertEqual(AutoMatchPolicy.CombatDetectionDecision(
    {lock_state: "LOCKED", target_presence: "PRESENT", error: ""}),
    "LOCKED", "locked target decision")
AssertEqual(AutoMatchPolicy.CombatDetectionDecision(
    {lock_state: "UNLOCKED", target_presence: "PRESENT", error: ""}),
    "PRIMARY", "unlocked target fallback")
AssertEqual(AutoMatchPolicy.CombatDetectionDecision(
    {lock_state: "LOCKED", target_presence: "ABSENT", error: ""}),
    "PRIMARY", "missing target fallback")
AssertEqual(AutoMatchPolicy.CombatDetectionDecision(
    {lock_state: "ERROR", target_presence: "ERROR", error: "capture failed"}),
    "ERROR", "capture error holds state")
AssertEqual(AutoMatchPolicy.ShouldStopOutput(1000, 60999, 60), false, "output cutoff early")
AssertEqual(AutoMatchPolicy.ShouldStopOutput(1000, 61000, 60), true, "output cutoff due")
AssertEqual(AutoMatchPolicy.ResultCountDelayMs, 1500, "result count delay")
AssertEqual(AutoMatchPolicy.ResultReturnDelayMs, 11500, "result total return delay")
AssertEqual(AutoMatchPolicy.ShouldCountResult(1499), false, "result count early")
AssertEqual(AutoMatchPolicy.ShouldCountResult(1500), true, "result count due")
AssertEqual(AutoMatchPolicy.ShouldReturnToRoom(11499), false, "result return early")
AssertEqual(AutoMatchPolicy.ShouldReturnToRoom(11500), true, "result return due")

tracker := AutoMatchRoomIdentityTracker.CreateState()
candidate := {status: "OK", self_slot_index: 2, self_state: "NOT_READY"}
AssertEqual(AutoMatchRoomIdentityTracker.Update(tracker, candidate).accepted, false, "room frame 1")
AssertEqual(AutoMatchRoomIdentityTracker.Update(tracker, candidate).accepted, false, "room frame 2")
third := AutoMatchRoomIdentityTracker.Update(tracker, candidate)
AssertEqual(third.accepted, true, "room frame 3")
AssertEqual(third.newly_confirmed, true, "room newly confirmed")
AssertEqual(tracker.stable_slot, 2, "stable room slot")
AssertEqual(tracker.stable_state, "NOT_READY", "stable room state")
unknown := {status: "UNKNOWN", self_slot_index: 0, self_state: "UNKNOWN"}
AutoMatchRoomIdentityTracker.Update(tracker, unknown)
AutoMatchRoomIdentityTracker.Update(tracker, unknown)
AutoMatchRoomIdentityTracker.Update(tracker, unknown)
AssertEqual(tracker.stable_state, "UNKNOWN", "three ambiguous frames clear identity")

actions := SweepActionRecorder(100, 200)
sweep := AutoMatchSweepRunner.CreateState()
AutoMatchSweepRunner.Begin(sweep, actions, "2")
AssertEqual(actions.events[1], "stop_timer", "begin cancels old timer")
AssertEqual(actions.events[2], "activate", "activate before weapon")
AssertEqual(actions.events[3], "weapon:2", "select weapon two")
AssertEqual(actions.events[4], "right_down", "right down before movement")
AssertEqual(actions.events[5], "delay:30", "initial delay")
AssertEqual(actions.events[6], "get_position", "record mouse position")
AssertEqual(actions.events[7], "start_timer:50", "start 50ms timer")
Loop 19
    AssertEqual(AutoMatchSweepRunner.Step(sweep, actions), false, "sweep incomplete step " A_Index)
AssertEqual(AutoMatchSweepRunner.Step(sweep, actions), true, "sweep completes step 20")
AssertEqual(actions.moves.Length, 20, "exact sweep movement count")
Loop 20 {
    AssertEqual(actions.moves[A_Index].x, 100 + A_Index * 2, "sweep x step " A_Index)
    AssertEqual(actions.moves[A_Index].y, 200, "sweep y step " A_Index)
}
AssertEqual(actions.moves[20].x, 140, "sweep total displacement")
AssertEqual(actions.events[actions.events.Length - 1], "stop_timer", "completion stops timer first")
AssertEqual(actions.events[actions.events.Length], "right_up", "completion releases right button")
AssertEqual(sweep.active, false, "completed sweep inactive")

activationFailureActions := SweepActionRecorder(100, 200, false)
activationFailureSweep := AutoMatchSweepRunner.CreateState()
AssertEqual(AutoMatchSweepRunner.Begin(activationFailureSweep,
    activationFailureActions, "2"), false, "activation failure rejects sweep")
AssertEqual(activationFailureActions.events.Length, 2, "activation failure action count")
AssertEqual(activationFailureActions.events[1], "stop_timer", "activation failure stops old timer")
AssertEqual(activationFailureActions.events[2], "activate", "activation failure only attempts activation")
AssertEqual(activationFailureSweep.active, false, "activation failure leaves sweep inactive")

weaponFailureActions := SweepActionRecorder(100, 200, true, false)
weaponFailureSweep := AutoMatchSweepRunner.CreateState()
AssertEqual(AutoMatchSweepRunner.Begin(weaponFailureSweep,
    weaponFailureActions, "2"), false, "weapon failure rejects sweep")
AssertEqual(weaponFailureActions.events.Length, 3, "weapon failure action count")
AssertEqual(weaponFailureActions.events[3], "weapon:2", "weapon failure attempts weapon two")
AssertEqual(weaponFailureSweep.active, false, "weapon failure leaves sweep inactive")

interruptedActions := SweepActionRecorder(20, 30)
interrupted := AutoMatchSweepRunner.CreateState()
AutoMatchSweepRunner.Begin(interrupted, interruptedActions, "2")
Loop 5
    AutoMatchSweepRunner.Step(interrupted, interruptedActions)
AutoMatchSweepRunner.Stop(interrupted, interruptedActions)
AssertEqual(interruptedActions.moves.Length, 5, "interrupted movement count")
AssertEqual(interruptedActions.events[interruptedActions.events.Length - 1],
    "stop_timer", "interruption stops timer")
AssertEqual(interruptedActions.events[interruptedActions.events.Length],
    "right_up", "interruption releases right button")
AssertEqual(interrupted.active, false, "interrupted sweep inactive")

primaryActions := PrimaryActionRecorder()
primary := AutoMatchPrimaryRunner.CreateState()
AutoMatchPrimaryRunner.Begin(primary, primaryActions)
AssertEqual(primaryActions.events[1], "stop_timer", "primary begin cancels old timer")
AssertEqual(primaryActions.events[2], "fire", "primary fires immediately")
AssertEqual(primaryActions.events[3], "start_timer:3000", "primary schedules second shot")
AssertEqual(AutoMatchPrimaryRunner.Step(primary, primaryActions), false, "primary second shot continues")
AssertEqual(primaryActions.fireCount, 2, "primary second shot count")
AssertEqual(primaryActions.events[primaryActions.events.Length],
    "start_timer:3000", "primary schedules third shot")
AssertEqual(AutoMatchPrimaryRunner.Step(primary, primaryActions), true, "primary third shot completes")
AssertEqual(primaryActions.fireCount, 3, "primary exact shot count")
AssertEqual(primaryActions.events[primaryActions.events.Length], "stop_timer", "primary stops before W2")
AssertEqual(primary.active, false, "primary timer inactive after third shot")

primaryInterruptedActions := PrimaryActionRecorder()
primaryInterrupted := AutoMatchPrimaryRunner.CreateState()
AutoMatchPrimaryRunner.Begin(primaryInterrupted, primaryInterruptedActions)
AutoMatchPrimaryRunner.Stop(primaryInterrupted, primaryInterruptedActions)
AssertEqual(primaryInterruptedActions.fireCount, 1, "primary interruption keeps only immediate shot")
AssertEqual(primaryInterrupted.active, false, "primary interruption inactive")

FileAppend("automatch_policy_test: PASS`n", "*")
ExitApp(0)

AssertEqual(actual, expected, label) {
    if (actual != expected) {
        FileAppend(label ": expected=" expected ", actual=" actual "`n", "*")
        ExitApp(1)
    }
}

class SweepActionRecorder {
    __New(x, y, activateOk := true, selectOk := true) {
        this.x := x
        this.y := y
        this.activateOk := activateOk
        this.selectOk := selectOk
        this.events := []
        this.moves := []
    }

    ActivateGame() {
        this.events.Push("activate")
        return this.activateOk
    }
    SelectWeapon(key) {
        this.events.Push("weapon:" key)
        return this.selectOk
    }
    RightButtonDown() => this.events.Push("right_down")
    RightButtonUp() => this.events.Push("right_up")
    Delay(milliseconds) => this.events.Push("delay:" milliseconds)
    StartTimer(interval) => this.events.Push("start_timer:" interval)
    StopTimer() => this.events.Push("stop_timer")

    GetMousePosition() {
        this.events.Push("get_position")
        return {x: this.x, y: this.y}
    }

    MoveMouse(x, y) {
        this.events.Push("move:" x "," y)
        this.moves.Push({x: x, y: y})
    }
}

class PrimaryActionRecorder {
    __New() {
        this.events := []
        this.fireCount := 0
    }

    Fire() {
        this.events.Push("fire")
        this.fireCount++
    }
    StartTimer(delayMs) => this.events.Push("start_timer:" delayMs)
    StopTimer() => this.events.Push("stop_timer")
}
