#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\ConfigManager.ahk
#Include ..\Lib\Logger.ahk
#Include ..\Lib\ScreenCapture.ahk
#Include ..\Lib\TargetLockDetector.ahk
#Include ..\Lib\CombatTargetDetector.ahk
#Include ..\Lib\RoomSelfDetector.ahk
#Include ..\Lib\GameUtils.ahk
#Include ..\Modules\AutoMatch.ahk

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
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[1], 0, "primary shot 1")
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[2], 3000, "primary shot 2")
AssertEqual(AutoMatchPolicy.PrimaryShotOffsets[3], 6000, "primary shot 3")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(0, 0), true, "primary first shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(1, 2999), false, "primary second shot early")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(1, 3000), true, "primary second shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(2, 6000), true, "primary third shot due")
AssertEqual(AutoMatchPolicy.IsPrimaryShotDue(3, 9000), false, "primary sequence complete")
AssertEqual(AutoMatchPolicy.ShouldFallbackFromLock(2), false, "lock loss frame 2")
AssertEqual(AutoMatchPolicy.ShouldFallbackFromLock(3), true, "lock loss frame 3")
AssertEqual(AutoMatchPolicy.ShouldStopOutput(1000, 60999, 60), false, "output cutoff early")
AssertEqual(AutoMatchPolicy.ShouldStopOutput(1000, 61000, 60), true, "output cutoff due")

AutoMatch_ResetRoomIdentity()
candidate := {status: "OK", self_slot_index: 2, self_state: "NOT_READY", error: ""}
AssertEqual(AutoMatch_UpdateRoomIdentity(candidate), false, "room frame 1")
AssertEqual(AutoMatch_UpdateRoomIdentity(candidate), false, "room frame 2")
AssertEqual(AutoMatch_UpdateRoomIdentity(candidate), true, "room frame 3")
AssertEqual(g_AutoMatch_RoomStableSlot, 2, "stable room slot")
AssertEqual(g_AutoMatch_RoomStableState, "NOT_READY", "stable room state")

unknown := {status: "UNKNOWN", self_slot_index: 0, self_state: "UNKNOWN", error: ""}
AutoMatch_UpdateRoomIdentity(unknown)
AutoMatch_UpdateRoomIdentity(unknown)
AutoMatch_UpdateRoomIdentity(unknown)
AssertEqual(g_AutoMatch_RoomStableState, "UNKNOWN", "ambiguous clears stable identity")

FileAppend("automatch_policy_test: PASS`n", "*")
ExitApp(0)

AssertEqual(actual, expected, label) {
    if (actual != expected) {
        FileAppend(label ": expected=" expected ", actual=" actual "`n", "*")
        ExitApp(1)
    }
}
