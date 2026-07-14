#Requires AutoHotkey v2.0
#SingleInstance Force

main := FileRead(A_ScriptDir "\..\SDGO工具脚本.ahk", "UTF-8")
policy := FileRead(A_ScriptDir "\..\Lib\AutoMatchPolicy.ahk", "UTF-8")
overlay := FileRead(A_ScriptDir "\..\Lib\OverlayManager.ahk", "UTF-8")
gameUtils := FileRead(A_ScriptDir "\..\Lib\GameUtils.ahk", "UTF-8")
module := FileRead(A_ScriptDir "\..\Modules\AutoMatch.ahk", "UTF-8")

AssertIncreasing([
    InStr(main, "Lib\ScreenCapture.ahk"),
    InStr(main, "Lib\TargetLockDetector.ahk"),
    InStr(main, "Lib\CombatTargetDetector.ahk"),
    InStr(main, "Lib\RoomSelfDetector.ahk"),
    InStr(main, "Lib\AutoMatchPolicy.ahk"),
    InStr(main, "Lib\GameUtils.ahk"),
    InStr(main, "Lib\OverlayManager.ahk"),
    InStr(main, "Modules\AutoMatch.ahk")
], "production include order")
AssertContains(policy, "class AutoMatchPolicy", "policy class")
AssertContains(policy, "class AutoMatchPrimaryRunner", "primary timer runner")
AssertContains(overlay, "class OverlayManager", "overlay class")
AssertContains(gameUtils, "static SendGameKeyHeld", "held-key helper")
AssertContains(gameUtils, "&& !forceForeground", "foreground override")
AssertContains(gameUtils, "ControlSend", "control input path")
AssertContains(gameUtils, " down}", "control key down")
AssertContains(gameUtils, " up}", "control key up")
AssertContains(gameUtils, "Sleep(holdMs)", "held-key duration")
AssertContains(module, "AutoMatch_Tick()", "AutoMatch entry point")
AssertContains(main, "Hotkey(mod " Chr(34) "F9" Chr(34), "AutoMatch automation hotkey")
AssertContains(module, "AutoMatchPolicy.RoomKeyHoldMs, 0, true", "room foreground held-key adapter")
AssertContains(module, "AutoMatchPolicy.WeaponKeyHoldMs, 0, true", "weapon foreground held-key adapter")
AssertContains(module, "AutoMatch_PrimaryAttackTimer", "primary attack timer")
AssertContains(module, "AutoMatch_StopPrimaryAttack()", "primary timer cleanup")
AssertContains(module, "if (AutoMatch_CheckOutputDeadline())", "primary timer deadline guard")
AssertContains(module, "case " Chr(34) "WAIT_ROOM" Chr(34), "post-result room state")
AssertContains(module, "AutoMatch_SetState(" Chr(34) "WAIT_ROOM" Chr(34) ")", "result enters room guard")
AssertContains(module, "已确认返回房间", "room guard confirmation")
AssertContains(module, "AutoMatch_TickWaitRoom(windowRect, clientRect)", "room guard client detection")
AssertContains(module, "AutoMatch_UpdateRoomIdentity(result)", "room guard three-frame identity")

FileAppend("toolbox_load_test: PASS`n", "*")
ExitApp(0)

AssertContains(haystack, needle, label) {
    if (!InStr(haystack, needle)) {
        FileAppend(label ": missing " needle "`n", "*")
        ExitApp(1)
    }
}

AssertIncreasing(values, label) {
    previous := 0
    for _, value in values {
        if (value <= previous) {
            FileAppend(label ": invalid dependency order`n", "*")
            ExitApp(1)
        }
        previous := value
    }
}
