; RoomSelfDetector.ahk - room slot and local-player detection.
; Algorithm snapshot: GameUiMonitorAHK 468fe3b.

class RoomSelfDetector {
    static SlotCount := 12
    static RequiredColorMatches := 1
    static SelfMinEdgeCoverage := 0.70
    static SelfMinMargin := 0.5
    static RegionX := 10 / 1024
    static RegionY := 312 / 768
    static RegionW := 310 / 1024
    static RegionH := 228 / 768

    static Detect(clientRect, sourceCapture := "") {
        try {
            region := this.BuildRegion(clientRect)
            rowHeight := region.h / this.SlotCount
            borderMargin := Max(2, Round(rowHeight * 0.16))
            captureRegion := {
                x: region.x,
                y: region.y - borderMargin,
                w: region.w,
                h: region.h + borderMargin * 2
            }
            capture := IsObject(sourceCapture)
                ? sourceCapture
                : ScreenCapture.CaptureRegionPixels(captureRegion)
            if (!capture.ok)
                return this.ErrorResult(capture.error)

            slots := []
            Loop this.SlotCount {
                bounds := this.BuildSlotBounds(region, A_Index)
                slots.Push(this.DetectSlot(A_Index, bounds, capture))
            }
            for _, slot in slots {
                if (slot.occupied) {
                    metrics := this.ComputeSelfBorderMetrics(capture, slot.region)
                    slot.self_score := metrics.score
                    slot.self_border_top := metrics.top
                    slot.self_border_bottom := metrics.bottom
                    slot.self_border_eligible := metrics.eligible
                }
            }

            candidate := this.SelectSelfCandidateDetails(slots)
            if (candidate.index <= 0) {
                return {
                    status: "UNKNOWN", self_slot_index: 0, self_state: "UNKNOWN",
                    margin: candidate.margin, slots: slots, error: ""
                }
            }
            selfSlot := slots[candidate.index]
            return {
                status: "OK", self_slot_index: candidate.index,
                self_state: selfSlot.state, margin: candidate.margin,
                slots: slots, error: ""
            }
        } catch as err {
            return this.ErrorResult(err.Message)
        }
    }

    static ErrorResult(message) {
        return {
            status: "ERROR", self_slot_index: 0, self_state: "UNKNOWN",
            margin: 0.0, slots: [], error: message
        }
    }

    static BuildRegion(clientRect) {
        return {
            x: clientRect.x + Round(clientRect.w * this.RegionX),
            y: clientRect.y + Round(clientRect.h * this.RegionY),
            w: Max(1, Round(clientRect.w * this.RegionW)),
            h: Max(1, Round(clientRect.h * this.RegionH))
        }
    }

    static BuildSlotBounds(region, slotIndex) {
        top := region.y + Round((slotIndex - 1) * region.h / this.SlotCount)
        bottom := region.y + Round(slotIndex * region.h / this.SlotCount)
        return {x: region.x, y: top, w: region.w, h: Max(1, bottom - top)}
    }

    static DetectSlot(slotIndex, bounds, capture) {
        regions := this.BuildSlotRegions(bounds)
        hasMaster := this.HasColor(capture, regions.status, 0x66F603, 80)
        hasReady := !hasMaster && this.HasColor(capture, regions.status, 0x00FFFF, 70)
        hasName := !hasMaster && !hasReady && this.HasColor(capture, regions.name, 0xFFFFFF, 70)
        occupied := hasMaster || hasReady || hasName
        state := !occupied ? "EMPTY" : (hasMaster ? "MASTER" : (hasReady ? "READY" : "NOT_READY"))
        return {
            index: slotIndex, state: state, occupied: occupied,
            self_score: 0.0, self_border_top: 0.0,
            self_border_bottom: 0.0, self_border_eligible: false,
            region: bounds
        }
    }

    static BuildSlotRegions(bounds) {
        rowPadY := Max(1, Round(bounds.h / 19))
        contentH := Max(1, bounds.h - rowPadY * 2)
        nameX := bounds.x + this.ScaleX(65, bounds.w)
        statusX := bounds.x + this.ScaleX(245, bounds.w)
        statusRight := bounds.x + this.ScaleX(305, bounds.w)
        name := this.CenterBand({x: nameX, y: bounds.y + rowPadY,
            w: this.ScaleX(165, bounds.w), h: contentH})
        status := this.CenterBand({x: statusX, y: bounds.y + rowPadY,
            w: Max(1, statusRight - statusX), h: contentH})
        return {name: name, status: status}
    }

    static ComputeSelfBorderMetrics(capture, region) {
        edgeH := Min(region.h, Max(2, Round(region.h * 0.11)))
        bands := this.BuildSelfBorderBands(region.x, region.w)
        top := this.MeasureBrightCyanEdge(capture, bands, region.y - edgeH, edgeH * 2)
        bottom := this.MeasureBrightCyanEdge(capture, bands, region.y + region.h - edgeH, edgeH * 2)
        minEdge := Min(top, bottom)
        averageEdge := (top + bottom) / 2
        ; (Port from GameUiMonitorAHK) 双边缘检测奖励: 上下均有亮青色时,
        ; effectiveMinEdge 获得 1.4x 倍率, 避免高分辨率插值导致边缘偏淡而漏判
        bothDetected := top > 0 && bottom > 0
        effectiveMinEdge := Min(1.0, minEdge * (bothDetected ? 1.4 : 1.0))
        return {
            top: top, bottom: bottom,
            score: 100 * this.Clamp(0.65 * minEdge + 0.35 * averageEdge, 0, 1),
            eligible: effectiveMinEdge >= this.SelfMinEdgeCoverage
        }
    }

    static BuildSelfBorderBands(x, width) {
        rightStart := x + this.ScaleX(230, width)
        rightEnd := x + this.ScaleX(244, width)
        return [{x: rightStart, w: Max(1, rightEnd - rightStart)}]
    }

    static MeasureBrightCyanEdge(capture, bands, y, height) {
        best := 0.0
        second := 0.0
        Loop height {
            coverage := this.MeasureBrightCyanCoverage(capture, bands, y + A_Index - 1, 1)
            if (coverage > best) {
                second := best, best := coverage
            } else if (coverage > second) {
                second := coverage
            }
        }
        return (best + second) / 2
    }

    static MeasureBrightCyanCoverage(capture, bands, y, height) {
        matched := 0
        total := 0
        for _, band in bands {
            localX := Round(band.x - capture.x)
            localY := Round(y - capture.y)
            if (localX < 0 || localY < 0
                || localX + band.w > capture.w || localY + height > capture.h)
                continue
            Loop height {
                rowOffset := (localY + A_Index - 1) * capture.stride + localX * 4
                Loop band.w {
                    pixel := NumGet(capture.bits, rowOffset + (A_Index - 1) * 4, "UInt")
                    b := pixel & 255
                    g := (pixel >> 8) & 255
                    r := (pixel >> 16) & 255
                    total++
                    if (g >= 150 && b >= 150 && Min(g, b) - r >= 25)
                        matched++
                }
            }
        }
        return total > 0 ? matched / total : 0.0
    }

    static SelectSelfCandidateDetails(slots) {
        bestIndex := 0
        bestScore := -1.0
        secondScore := -1.0
        for _, slot in slots {
            if (!slot.occupied || !slot.self_border_eligible)
                continue
            if (slot.self_score > bestScore) {
                secondScore := bestScore
                bestScore := slot.self_score
                bestIndex := slot.index
            } else if (slot.self_score > secondScore) {
                secondScore := slot.self_score
            }
        }
        margin := bestScore >= 0
            ? (secondScore >= 0 ? bestScore - secondScore : bestScore)
            : 0.0
        if (secondScore >= 0 && margin < this.SelfMinMargin)
            bestIndex := 0
        return {index: bestIndex, margin: margin}
    }

    static HasColor(capture, region, color, variation) {
        return ScreenCapture.CountColorMatches(
            capture, region, color, variation, this.RequiredColorMatches
        ) >= this.RequiredColorMatches
    }

    static ScaleX(referencePixels, actualWidth) {
        return Max(1, Round(referencePixels * actualWidth / 310))
    }

    static CenterBand(region) {
        bandH := Max(3, Round(region.h * 0.15))
        return {x: region.x, y: region.y + Floor((region.h - bandH) / 2), w: region.w, h: bandH}
    }

    static Clamp(value, minimum, maximum) {
        return Min(maximum, Max(minimum, value))
    }
}
