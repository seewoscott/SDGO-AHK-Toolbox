; ScreenCapture.ahk — 轻量 GDI 屏幕区域截图 (AHK v2)

class ScreenCapture {
    static CaptureRegionPixels(region) {
        width := Max(1, Round(region.w))
        height := Max(1, Round(region.h))
        screenDC := 0
        memoryDC := 0
        bitmap := 0
        previousObject := 0
        bits := Buffer(width * height * 4, 0)
        errorMessage := ""
        copied := false

        try {
            screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
            if (!screenDC)
                throw Error("GetDC failed")

            memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
            if (!memoryDC)
                throw Error("CreateCompatibleDC failed")

            bitmap := DllCall("gdi32\CreateCompatibleBitmap",
                "Ptr", screenDC, "Int", width, "Int", height, "Ptr")
            if (!bitmap)
                throw Error("CreateCompatibleBitmap failed")

            previousObject := DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
            if (!previousObject)
                throw Error("SelectObject failed")

            ; SRCCOPY | CAPTUREBLT，包含普通分层窗口内容。
            if (!DllCall("gdi32\BitBlt",
                "Ptr", memoryDC,
                "Int", 0, "Int", 0,
                "Int", width, "Int", height,
                "Ptr", screenDC,
                "Int", Round(region.x), "Int", Round(region.y),
                "UInt", 0x40CC0020,
                "Int"))
                throw Error("BitBlt failed")

            bitmapInfo := Buffer(40, 0)
            NumPut(
                "UInt", 40,
                "Int", width,
                "Int", -height,
                "UShort", 1,
                "UShort", 32,
                "UInt", 0,
                bitmapInfo
            )
            scanLines := DllCall("gdi32\GetDIBits",
                "Ptr", memoryDC,
                "Ptr", bitmap,
                "UInt", 0,
                "UInt", height,
                "Ptr", bits.Ptr,
                "Ptr", bitmapInfo.Ptr,
                "UInt", 0,
                "Int")
            if (scanLines != height)
                throw Error("GetDIBits returned " scanLines " of " height " scan lines")

            copied := true
        } catch as err {
            errorMessage := err.Message
        } finally {
            if (previousObject && memoryDC)
                DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", previousObject, "Ptr")
            if (bitmap)
                DllCall("gdi32\DeleteObject", "Ptr", bitmap)
            if (memoryDC)
                DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
            if (screenDC)
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
        }

        return {
            ok: copied,
            error: errorMessage,
            x: Round(region.x),
            y: Round(region.y),
            w: width,
            h: height,
            stride: width * 4,
            bits: bits
        }
    }
}
