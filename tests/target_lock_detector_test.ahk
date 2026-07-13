#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\ScreenCapture.ahk
#Include ..\Lib\TargetLockDetector.ahk

AssertDetectorContract()

expectedByScenario := Map()
for _, size in [[1024, 768], [2048, 1536]] {
    clientRect := {x: 37, y: 61, w: size[1], h: size[2]}
    results := RunScenarios(clientRect)
    for scenario, actual in results {
        expected := scenario == "locked" ? "LOCKED" : "UNLOCKED"
        AssertEqual(actual, expected, size[1] "x" size[2] " " scenario)
        if (expectedByScenario.Has(scenario))
            AssertEqual(actual, expectedByScenario[scenario], "双尺寸结论一致: " scenario)
        else
            expectedByScenario[scenario] := actual
    }
}

errorResult := TargetLockDetector.Detect(
    {x: 0, y: 0, w: 1024, h: 768},
    {ok: false, error: "synthetic capture failure"}
)
AssertEqual(errorResult.state, "ERROR", "截图失败状态")
AssertEqual(errorResult.error, "synthetic capture failure", "截图失败原因")

FileAppend("target_lock_detector_test: PASS`n", "*")
ExitApp(0)

AssertDetectorContract() {
    ; 固定 GameUiMonitorAHK CombatHudDetector.DetectLockBrackets 的只读参数快照。
    AssertEqual(TargetLockDetector.RegionLeft, 0.38, "RegionLeft")
    AssertEqual(TargetLockDetector.RegionTop, 0.30, "RegionTop")
    AssertEqual(TargetLockDetector.RegionRight, 0.62, "RegionRight")
    AssertEqual(TargetLockDetector.RegionBottom, 0.72, "RegionBottom")
    AssertEqual(TargetLockDetector.SampleStep, 3, "SampleStep")
    AssertEqual(TargetLockDetector.GreenMin, 200, "GreenMin")
    AssertEqual(TargetLockDetector.GreenRedDelta, 20, "GreenRedDelta")
    AssertEqual(TargetLockDetector.GreenBlueDelta, 30, "GreenBlueDelta")
    AssertEqual(TargetLockDetector.BlueMax, 200, "BlueMax")
    AssertEqual(TargetLockDetector.MinCountRatio, 0.025, "MinCountRatio")
    AssertEqual(TargetLockDetector.MinVerticalSpanRatio, 0.10, "MinVerticalSpanRatio")
    AssertEqual(TargetLockDetector.RequiredSidePixelCount(246), 4, "1024宽度最小像素数")
    AssertEqual(TargetLockDetector.RequiredSidePixelCount(492), 4, "2048宽度最小像素数")
}

RunScenarios(clientRect) {
    results := Map()

    capture := NewCapture(clientRect)
    results["blank"] := TargetLockDetector.Detect(clientRect, capture).state

    capture := NewCapture(clientRect)
    DrawLockBrackets(capture, TargetLockDetector.BuildRegion(clientRect), true, true)
    results["locked"] := TargetLockDetector.Detect(clientRect, capture).state

    capture := NewCapture(clientRect)
    DrawLockBrackets(capture, TargetLockDetector.BuildRegion(clientRect), true, false)
    results["single_side"] := TargetLockDetector.Detect(clientRect, capture).state

    capture := NewCapture(clientRect)
    DrawOrdinaryGreenHud(capture, TargetLockDetector.BuildRegion(clientRect))
    results["green_hud"] := TargetLockDetector.Detect(clientRect, capture).state

    return results
}

NewCapture(clientRect) {
    bits := Buffer(clientRect.w * clientRect.h * 4, 0)
    return {
        ok: true,
        error: "",
        x: clientRect.x,
        y: clientRect.y,
        w: clientRect.w,
        h: clientRect.h,
        stride: clientRect.w * 4,
        bits: bits
    }
}

DrawLockBrackets(capture, region, drawLeft, drawRight) {
    top := region.y + Round(region.h * 0.30)
    height := Round(region.h * 0.38)
    thickness := Max(5, Round(region.w * 0.02))
    armWidth := Max(28, Round(region.w * 0.12))
    left := region.x + Round(region.w * 0.28)
    right := region.x + Round(region.w * 0.70)

    if (drawLeft) {
        FillRegion(capture, {x: left, y: top, w: thickness, h: height}, 120, 230, 120)
        FillRegion(capture, {x: left, y: top, w: armWidth, h: thickness}, 120, 230, 120)
    }
    if (drawRight) {
        FillRegion(capture, {x: right, y: top, w: thickness, h: height}, 120, 230, 120)
        FillRegion(capture, {x: right - armWidth + thickness, y: top, w: armWidth, h: thickness}, 120, 230, 120)
    }
}

DrawOrdinaryGreenHud(capture, region) {
    ; 两侧都有足量绿色，但仅形成薄横条，垂直跨度不足 10%。
    bandHeight := Max(4, Round(region.h * 0.02))
    bandWidth := Round(region.w * 0.22)
    y := region.y + Round(region.h * 0.18)
    FillRegion(capture, {x: region.x + Round(region.w * 0.08), y: y, w: bandWidth, h: bandHeight}, 90, 225, 90)
    FillRegion(capture, {x: region.x + Round(region.w * 0.70), y: y, w: bandWidth, h: bandHeight}, 90, 225, 90)
}

FillRegion(capture, region, r, g, b) {
    x1 := Max(0, Round(region.x - capture.x))
    y1 := Max(0, Round(region.y - capture.y))
    x2 := Min(capture.w - 1, x1 + Round(region.w) - 1)
    y2 := Min(capture.h - 1, y1 + Round(region.h) - 1)
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            offset := y * capture.stride + x * 4
            NumPut("UChar", b, capture.bits, offset)
            NumPut("UChar", g, capture.bits, offset + 1)
            NumPut("UChar", r, capture.bits, offset + 2)
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
