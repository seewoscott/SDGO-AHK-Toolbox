#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\Lib\AutoMatchPolicy.ahk

class SweepTestActions {
    __New() {
        this.timer_interval := 0
        this.timer_stops := 0
        this.right_up_count := 0
        this.right_down_count := 0
        this.position_reads := 0
        this.moves := []
    }

    ActivateGame() => true
    SelectWeapon(key) => true
    Delay(milliseconds) => 0
    StartTimer(interval) => this.timer_interval := interval
    StopTimer() => this.timer_stops++
    RightButtonUp() => this.right_up_count++
    RightButtonDown() => this.right_down_count++

    GetMousePosition() {
        this.position_reads++
        return {x: 100, y: 200}
    }

    MoveMouse(x, y) {
        this.moves.Push({x: x, y: y})
    }
}

class PrimaryTestActions {
    __New() {
        this.fire_count := 0
        this.timer_delay := 0
        this.timer_stops := 0
    }

    Fire() => this.fire_count++
    StartTimer(delayMs) => this.timer_delay := delayMs
    StopTimer() => this.timer_stops++
}

AssertEqual(actual, expected, message) {
    if (actual != expected)
        throw Error(message " | expected=" expected ", actual=" actual)
}

AssertTrue(actual, message) {
    if (!actual)
        throw Error(message)
}

AssertEqual(AutoMatchLockSweep.IntervalMs, 10, "sweep interval")
AssertEqual(AutoMatchLockSweep.StepCount, 10, "sweep steps")
AssertEqual(AutoMatchLockSweep.DeltaX, 4, "sweep delta")
AssertEqual(AutoMatchPolicy.CombatTickIntervalMs, 200, "combat tick")
AssertEqual(AutoMatchPolicy.LockedCheckIntervalMs, 1000, "locked target check interval")
AssertEqual(AutoMatchPolicy.PrimaryWeaponSettleMs, 200, "primary weapon settle delay")

sweepState := AutoMatchSweepRunner.CreateState()
sweepActions := SweepTestActions()
AssertTrue(AutoMatchSweepRunner.Begin(sweepState, sweepActions, "2"), "first sweep begins")
AssertEqual(sweepActions.right_up_count, 1, "right button released before first sweep")
AssertEqual(sweepActions.timer_interval, 10, "first sweep timer")
Loop 10
    completed := AutoMatchSweepRunner.Step(sweepState, sweepActions)
AssertTrue(completed, "first sweep completes")
AssertEqual(sweepState.x, 140, "first sweep moves 40px")
AssertEqual(sweepActions.moves.Length, 10, "first sweep move count")
AssertEqual(sweepActions.right_down_count, 1, "right button pressed after first sweep")

AssertTrue(AutoMatchSweepRunner.Begin(sweepState, sweepActions, "2"), "second sweep begins")
Loop 10
    completed := AutoMatchSweepRunner.Step(sweepState, sweepActions)
AssertTrue(completed, "second sweep completes")
AssertEqual(sweepState.x, 180, "second sweep continues from first endpoint")
AssertEqual(sweepActions.position_reads, 1, "mouse position read once per combat")
AssertEqual(sweepActions.right_down_count, 2, "right button pressed after second sweep")

primaryState := AutoMatchPrimaryRunner.CreateState()
primaryActions := PrimaryTestActions()
AutoMatchPrimaryRunner.Begin(primaryState, primaryActions)
AssertEqual(primaryActions.fire_count, 1, "single-shot fires once")
AssertEqual(primaryActions.timer_delay, 3000, "single-shot recovery delay")
AssertTrue(AutoMatchPrimaryRunner.Step(primaryState, primaryActions), "single-shot completes after recovery")
AssertEqual(primaryActions.fire_count, 1, "single-shot does not fire 2/1")

FileAppend("AutoMatchPolicyTests: PASS`n", "*")
ExitApp(0)
