; CombatTargetDetector.ahk - combined target marker and lock bracket detection.
; Algorithm snapshot: GameUiMonitorAHK 468fe3b.

class CombatTargetDetector {
    static ReferenceClientWidth := 1024
    static ReferenceClientHeight := 768

    static Detect(clientRect, sourceCapture := "") {
        try {
            view := this.RelativeRegion(clientRect, 0.10, 0.20, 0.90, 0.80)
            lockRegion := TargetLockDetector.BuildRegion(clientRect)
            capture := IsObject(sourceCapture)
                ? sourceCapture
                : ScreenCapture.CaptureRegionPixels(view)
            if (!capture.ok)
                return this.ErrorResult(capture.error)

            scaleX := Max(0.01, clientRect.w / this.ReferenceClientWidth)
            scaleY := Max(0.01, clientRect.h / this.ReferenceClientHeight)
            target := this.AnalyzeTargetMarkers(capture, view, scaleX, scaleY)
            lockState := TargetLockDetector.Analyze(capture, lockRegion, scaleX, scaleY)
            return {
                lock_state: lockState,
                target_presence: target.presence,
                target_count: target.count,
                error: ""
            }
        } catch as err {
            return this.ErrorResult(err.Message)
        }
    }

    static ErrorResult(message) {
        return {lock_state: "ERROR", target_presence: "ERROR", target_count: 0, error: message}
    }

    static RelativeRegion(rect, left, top, right, bottom) {
        x1 := rect.x + Round(rect.w * left)
        y1 := rect.y + Round(rect.h * top)
        x2 := rect.x + Round(rect.w * right)
        y2 := rect.y + Round(rect.h * bottom)
        return {x: x1, y: y1, w: Max(1, x2 - x1), h: Max(1, y2 - y1)}
    }

    static ScaleStep(baseStep, scale) {
        return Max(1, Round(baseStep * scale))
    }

    static AnalyzeTargetMarkers(capture, region, scaleX := 1.0, scaleY := 1.0) {
        if (!capture.ok)
            return {presence: "ERROR", count: 0}
        localX := Max(0, Round(region.x - capture.x))
        localY := Max(0, Round(region.y - capture.y))
        width := Min(region.w, capture.w - localX)
        height := Min(region.h, capture.h - localY)
        if (width <= 0 || height <= 0)
            return {presence: "ERROR", count: 0}

        stepX := this.ScaleStep(10, scaleX)
        stepY := this.ScaleStep(3, scaleY)
        supportStepX := this.ScaleStep(3, scaleX)
        supportStepY := this.ScaleStep(3, scaleY)
        minRunSamples := Max(1, Ceil(width * 0.015 / stepX))
        maxRunSamples := Max(minRunSamples + 1, Round(width * 0.15 / stepX))
        rowSegments := []

        y := 0
        while (y < height) {
            rowOffset := (localY + y) * capture.stride + localX * 4
            runStart := -1
            runHits := 0
            gap := 0
            x := 0
            while (x < width) {
                pixel := NumGet(capture.bits, rowOffset + x * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if (this.IsEnemyMarkerRed(r, g, b)) {
                    if (runStart < 0)
                        runStart := x
                    runHits++
                    gap := 0
                } else if (runStart >= 0) {
                    gap++
                    if (gap > 1) {
                        this.AddMarkerSegment(rowSegments, y, runStart,
                            x - gap * stepX, runHits, minRunSamples, maxRunSamples)
                        runStart := -1, runHits := 0, gap := 0
                    }
                }
                x += stepX
            }
            if (runStart >= 0)
                this.AddMarkerSegment(rowSegments, y, runStart, width - 1,
                    runHits, minRunSamples, maxRunSamples)
            y += stepY
        }

        candidates := []
        maxPairGap := Max(8, Round(height * 0.045))
        minPairGap := Max(2, Round(height * 0.006))
        for firstIndex, first in rowSegments {
            secondIndex := firstIndex + 1
            pairChecks := 0
            while (secondIndex <= rowSegments.Length) {
                second := rowSegments[secondIndex]
                verticalGap := second.y - first.y
                if (verticalGap > maxPairGap)
                    break
                if (++pairChecks > 40)
                    break
                if (verticalGap >= minPairGap && this.SegmentOverlap(first, second) >= 0.55) {
                    left := Max(first.x1, second.x1)
                    right := Min(first.x2, second.x2)
                    supportWidth := Max(1, right - left)
                    aboveLeft := Max(0, left - supportWidth * 0.35)
                    belowLeft := Max(0, left - supportWidth * 0.25)
                    above := this.CountEnemyRed(capture,
                        localX + aboveLeft,
                        localY + Max(0, first.y - height * 0.065),
                        Min(width - 1, right + supportWidth * 0.35) - aboveLeft,
                        Max(1, first.y - Max(0, first.y - height * 0.065)),
                        supportStepX, supportStepY)
                    below := this.CountEnemyRed(capture,
                        localX + belowLeft,
                        localY + second.y,
                        Min(width - 1, right + supportWidth * 0.25) - belowLeft,
                        Max(1, Min(height - second.y, height * 0.075)),
                        supportStepX, supportStepY)
                    minSupport := Max(2, Round(supportWidth / stepX * 0.05))
                    hasArrowStem := this.HasLongRedStem(capture,
                        localX + left, localY + first.y, supportWidth,
                        Min(height - first.y, Max(supportWidth * 1.6, height * 0.12)), scaleY)
                    supportConfirmed := (above >= minSupport && below >= minSupport)
                        || above + below >= minSupport * 3
                    if (!hasArrowStem && supportConfirmed) {
                        candidates.Push({x: (left + right) / 2,
                            y: (first.y + second.y) / 2})
                        break
                    }
                }
                secondIndex++
            }
        }

        unique := this.DeduplicateCandidates(candidates, width, height)
        return {presence: unique.Length > 0 ? "PRESENT" : "ABSENT", count: unique.Length}
    }

    static AddMarkerSegment(segments, y, x1, x2, hits, minHits, maxHits) {
        if (hits >= minHits && hits <= maxHits && x2 > x1)
            segments.Push({y: y, x1: x1, x2: x2, hits: hits})
    }

    static SegmentOverlap(first, second) {
        overlap := Min(first.x2, second.x2) - Max(first.x1, second.x1)
        if (overlap <= 0)
            return 0.0
        shorter := Min(first.x2 - first.x1, second.x2 - second.x1)
        return shorter > 0 ? overlap / shorter : 0.0
    }

    static CountEnemyRed(capture, x, y, width, height, stepX := 3, stepY := 3) {
        x1 := Max(0, Round(x))
        y1 := Max(0, Round(y))
        x2 := Min(capture.w - 1, x1 + Max(1, Round(width)) - 1)
        y2 := Min(capture.h - 1, y1 + Max(1, Round(height)) - 1)
        count := 0
        sampleY := y1
        while (sampleY <= y2) {
            rowOffset := sampleY * capture.stride
            sampleX := x1
            while (sampleX <= x2) {
                pixel := NumGet(capture.bits, rowOffset + sampleX * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if (this.IsEnemyMarkerRed(r, g, b))
                    count++
                sampleX += stepX
            }
            sampleY += stepY
        }
        return count
    }

    static HasLongRedStem(capture, x, y, width, height, scaleY := 1.0) {
        sampleXs := [x + width * 0.12, x + width * 0.50, x + width * 0.88]
        stepY := this.ScaleStep(2, scaleY)
        requiredRun := Max(this.ScaleStep(10, scaleY), Round(width * 0.35))
        for _, sampleX in sampleXs {
            longest := 0
            current := 0
            sampleY := Max(0, Round(y))
            bottom := Min(capture.h - 1, sampleY + Round(height))
            while (sampleY <= bottom) {
                pixel := NumGet(capture.bits,
                    sampleY * capture.stride + Round(sampleX) * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if (this.IsEnemyMarkerRed(r, g, b)) {
                    current += stepY
                    longest := Max(longest, current)
                } else {
                    current := 0
                }
                sampleY += stepY
            }
            if (longest >= requiredRun)
                return true
        }
        return false
    }

    static DeduplicateCandidates(candidates, width, height) {
        unique := []
        for _, candidate in candidates {
            duplicate := false
            for _, existing in unique {
                if (Abs(candidate.x - existing.x) <= width * 0.04
                    && Abs(candidate.y - existing.y) <= height * 0.06) {
                    duplicate := true
                    break
                }
            }
            if (!duplicate)
                unique.Push(candidate)
        }
        return unique
    }

    static IsEnemyMarkerRed(r, g, b) {
        return r >= 200 && g <= 100 && b <= 100
    }
}
