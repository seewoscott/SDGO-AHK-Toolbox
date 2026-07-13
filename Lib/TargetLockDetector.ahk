; TargetLockDetector.ahk — AutoMatch 锁定框结构检测 (AHK v2)
; 参数快照来源: GameUiMonitorAHK CombatHudDetector.DetectLockBrackets (2026-07-13)

class TargetLockDetector {
    static RegionLeft := 0.38
    static RegionTop := 0.30
    static RegionRight := 0.62
    static RegionBottom := 0.72
    static SampleStep := 3
    static GreenMin := 200
    static GreenRedDelta := 20
    static GreenBlueDelta := 30
    static BlueMax := 200
    static MinCountRatio := 0.025
    static MinVerticalSpanRatio := 0.10

    static Detect(clientRect, sourceCapture := "") {
        try {
            region := this.BuildRegion(clientRect)
            capture := IsObject(sourceCapture)
                ? sourceCapture
                : ScreenCapture.CaptureRegionPixels(region)

            if (!capture.ok)
                return {state: "ERROR", error: capture.error}

            return {state: this.Analyze(capture, region), error: ""}
        } catch as err {
            return {state: "ERROR", error: err.Message}
        }
    }

    static BuildRegion(clientRect) {
        x1 := clientRect.x + Round(clientRect.w * this.RegionLeft)
        y1 := clientRect.y + Round(clientRect.h * this.RegionTop)
        x2 := clientRect.x + Round(clientRect.w * this.RegionRight)
        y2 := clientRect.y + Round(clientRect.h * this.RegionBottom)
        return {x: x1, y: y1, w: Max(1, x2 - x1), h: Max(1, y2 - y1)}
    }

    static Analyze(capture, region) {
        x1 := Max(0, Round(region.x - capture.x))
        y1 := Max(0, Round(region.y - capture.y))
        x2 := Min(capture.w - 1, x1 + region.w - 1)
        y2 := Min(capture.h - 1, y1 + region.h - 1)
        if (x2 <= x1 || y2 <= y1)
            throw Error("lock region is outside capture bounds")

        centerX := (x1 + x2) / 2
        leftCount := 0
        rightCount := 0
        leftMinY := y2
        leftMaxY := y1
        rightMinY := y2
        rightMaxY := y1
        step := this.SampleStep

        y := y1
        while (y <= y2) {
            rowOffset := y * capture.stride
            x := x1
            while (x <= x2) {
                pixel := NumGet(capture.bits, rowOffset + x * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if (this.IsLockGreen(r, g, b)) {
                    if (x < centerX) {
                        leftCount++
                        leftMinY := Min(leftMinY, y)
                        leftMaxY := Max(leftMaxY, y)
                    } else {
                        rightCount++
                        rightMinY := Min(rightMinY, y)
                        rightMaxY := Max(rightMaxY, y)
                    }
                }
                x += step
            }
            y += step
        }

        minCount := this.RequiredSidePixelCount(region.w)
        minSpan := region.h * this.MinVerticalSpanRatio
        symmetric := leftCount >= minCount && rightCount >= minCount
        verticalShape := leftMaxY - leftMinY >= minSpan
            && rightMaxY - rightMinY >= minSpan
        return symmetric && verticalShape ? "LOCKED" : "UNLOCKED"
    }

    static RequiredSidePixelCount(regionWidth) {
        return Max(4, Round((regionWidth / this.SampleStep) * this.MinCountRatio))
    }

    static IsLockGreen(r, g, b) {
        return g >= this.GreenMin
            && g - r >= this.GreenRedDelta
            && g - b >= this.GreenBlueDelta
            && b <= this.BlueMax
    }
}
