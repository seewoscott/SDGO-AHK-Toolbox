#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\ScreenCapture.ahk
#Include ..\Lib\TargetLockDetector.ahk
#Include ..\Lib\CombatTargetDetector.ahk

for _, size in [[1024, 768], [2048, 1536]] {
    client := {x: 0, y: 0, w: size[1], h: size[2]}
    scaleX := client.w / 1024
    scaleY := client.h / 768
    view := CombatTargetDetector.RelativeRegion(client, 0.10, 0.20, 0.90, 0.80)
    lockRegion := TargetLockDetector.BuildRegion(client)

    capture := NewCapture(client)
    empty := CombatTargetDetector.Detect(client, capture)
    AssertEqual(empty.target_presence, "ABSENT", size[1] " empty target")
    AssertEqual(empty.lock_state, "UNLOCKED", size[1] " empty lock")

    DrawDirectionArrow(capture, view, scaleX, scaleY)
    direction := CombatTargetDetector.Detect(client, capture)
    AssertEqual(direction.target_presence, "ABSENT", size[1] " direction arrow")

    capture := NewCapture(client)
    DrawEnemyMarker(capture, view, 0.50, 0.48, scaleX, scaleY)
    target := CombatTargetDetector.Detect(client, capture)
    AssertEqual(target.target_presence, "PRESENT", size[1] " target present")
    AssertEqual(target.lock_state, "UNLOCKED", size[1] " target unlocked")

    DrawLockBrackets(capture, lockRegion, scaleX, scaleY, true)
    locked := CombatTargetDetector.Detect(client, capture)
    AssertEqual(locked.target_presence, "PRESENT", size[1] " locked target")
    AssertEqual(locked.lock_state, "LOCKED", size[1] " lock brackets")

    capture := NewCapture(client)
    DrawLockBrackets(capture, lockRegion, scaleX, scaleY, false)
    single := CombatTargetDetector.Detect(client, capture)
    AssertEqual(single.lock_state, "UNLOCKED", size[1] " single bracket")
}

failed := CombatTargetDetector.Detect({x: 0, y: 0, w: 1024, h: 768},
    {ok: false, error: "synthetic combat failure"})
AssertEqual(failed.lock_state, "ERROR", "combat error state")
FileAppend("combat_target_detector_test: PASS`n", "*")
ExitApp(0)

NewCapture(client) {
    return {ok: true, error: "", x: client.x, y: client.y, w: client.w, h: client.h,
        stride: client.w * 4, bits: Buffer(client.w * client.h * 4, 0)}
}

DrawDirectionArrow(capture, region, scaleX, scaleY) {
    x := region.x + Round(region.w * 0.48)
    y := region.y + Round(region.h * 0.25)
    FillRegion(capture, {x: x, y: y, w: Round(70 * scaleX), h: Max(1, Round(3 * scaleY))}, 230, 40, 40)
    FillRegion(capture, {x: x, y: y + Round(14 * scaleY), w: Round(70 * scaleX), h: Max(1, Round(3 * scaleY))}, 230, 40, 40)
    FillRegion(capture, {x: x + Round(35 * scaleX), y: y, w: Max(1, Round(3 * scaleX)), h: Round(90 * scaleY)}, 230, 40, 40)
}

DrawEnemyMarker(capture, region, centerXRatio, centerYRatio, scaleX, scaleY) {
    width := Round(region.w * 0.08)
    left := region.x + Round(region.w * centerXRatio - width / 2)
    top := region.y + Round(region.h * centerYRatio - 8 * scaleY)
    lineH := Max(1, Round(3 * scaleY))
    FillRegion(capture, {x: left, y: top, w: width, h: lineH}, 230, 40, 40)
    FillRegion(capture, {x: left, y: top + Round(16 * scaleY), w: width, h: lineH}, 230, 40, 40)
    FillRegion(capture, {x: left + Round(10 * scaleX), y: top - Round(18 * scaleY), w: Round(28 * scaleX), h: Round(6 * scaleY)}, 230, 40, 40)
    FillRegion(capture, {x: left + Round(18 * scaleX), y: top + Round(24 * scaleY), w: Round(8 * scaleX), h: Round(8 * scaleY)}, 230, 40, 40)
    FillRegion(capture, {x: left + Round(36 * scaleX), y: top + Round(24 * scaleY), w: Round(8 * scaleX), h: Round(8 * scaleY)}, 230, 40, 40)
}

DrawLockBrackets(capture, region, scaleX, scaleY, bothSides) {
    top := region.y + Round(region.h * 0.30)
    height := Round(region.h * 0.38)
    left := region.x + Round(region.w * 0.28)
    FillRegion(capture, {x: left, y: top, w: Max(1, Round(5 * scaleX)), h: height}, 120, 230, 120)
    FillRegion(capture, {x: left, y: top, w: Round(28 * scaleX), h: Max(1, Round(5 * scaleY))}, 120, 230, 120)
    if (bothSides) {
        right := region.x + Round(region.w * 0.70)
        FillRegion(capture, {x: right, y: top, w: Max(1, Round(5 * scaleX)), h: height}, 120, 230, 120)
        FillRegion(capture, {x: right - Round(24 * scaleX), y: top, w: Round(28 * scaleX), h: Max(1, Round(5 * scaleY))}, 120, 230, 120)
    }
}

FillRegion(capture, region, r, g, b) {
    x1 := Max(0, Round(region.x - capture.x)), y1 := Max(0, Round(region.y - capture.y))
    x2 := Min(capture.w - 1, x1 + Max(1, Round(region.w)) - 1)
    y2 := Min(capture.h - 1, y1 + Max(1, Round(region.h)) - 1)
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            offset := y * capture.stride + x * 4
            NumPut("UChar", b, capture.bits, offset), NumPut("UChar", g, capture.bits, offset + 1), NumPut("UChar", r, capture.bits, offset + 2)
            x++
        }
        y++
    }
}

AssertEqual(actual, expected, label) {
    if (actual != expected) {
        FileAppend(label ": expected=" expected ", actual=" actual "`n", "*")
        ExitApp(1)
    }
}
