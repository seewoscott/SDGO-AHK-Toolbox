#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\ScreenCapture.ahk
#Include ..\Lib\RoomSelfDetector.ahk

for _, size in [[1024, 768], [2048, 1536]] {
    client := {x: 31, y: 47, w: size[1], h: size[2]}
    for _, state in ["MASTER", "READY", "NOT_READY"] {
        capture := NewCapture(client)
        DrawSlot(capture, client, 2, state, true)
        DrawSlot(capture, client, 5, "NOT_READY", false)
        result := RoomSelfDetector.Detect(client, capture)
        AssertEqual(result.status, "OK", size[1] "x" size[2] " status")
        AssertEqual(result.self_slot_index, 2, size[1] "x" size[2] " self slot")
        AssertEqual(result.self_state, state, size[1] "x" size[2] " " state)
    }

    capture := NewCapture(client)
    DrawSlot(capture, client, 2, "READY", true)
    DrawSlot(capture, client, 3, "NOT_READY", true)
    ambiguous := RoomSelfDetector.Detect(client, capture)
    AssertEqual(ambiguous.status, "UNKNOWN", size[1] "x" size[2] " ambiguous")
}

failed := RoomSelfDetector.Detect({x: 0, y: 0, w: 1024, h: 768},
    {ok: false, error: "synthetic room failure"})
AssertEqual(failed.status, "ERROR", "capture error status")
AssertEqual(failed.error, "synthetic room failure", "capture error message")
FileAppend("room_self_detector_test: PASS`n", "*")
ExitApp(0)

NewCapture(client) {
    return {ok: true, error: "", x: client.x, y: client.y, w: client.w, h: client.h,
        stride: client.w * 4, bits: Buffer(client.w * client.h * 4, 0)}
}

DrawSlot(capture, client, slotIndex, state, isSelf) {
    room := RoomSelfDetector.BuildRegion(client)
    bounds := RoomSelfDetector.BuildSlotBounds(room, slotIndex)
    regions := RoomSelfDetector.BuildSlotRegions(bounds)
    if (state == "MASTER")
        FillRegion(capture, regions.status, 0x66, 0xF6, 0x03)
    else if (state == "READY")
        FillRegion(capture, regions.status, 0x00, 0xFF, 0xFF)
    else
        FillRegion(capture, regions.name, 0xFF, 0xFF, 0xFF)

    if (isSelf) {
        band := RoomSelfDetector.BuildSelfBorderBands(bounds.x, bounds.w)[1]
        lineH := Max(2, Round(client.h / 768 * 2))
        FillRegion(capture, {x: band.x, y: bounds.y, w: band.w, h: lineH}, 40, 220, 230)
        FillRegion(capture, {x: band.x, y: bounds.y + bounds.h - lineH,
            w: band.w, h: lineH}, 40, 220, 230)
    }
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
