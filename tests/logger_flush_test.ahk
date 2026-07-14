#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\Lib\Logger.ahk

Logger.g_Buffer := "kept-on-failure`n"
Logger.g_BufferSize := 1
Logger.g_LogFile := A_Temp "\missing-parent-" A_TickCount "\test.log"
if (Logger.Flush() != false)
    ExitApp(1)
if (Logger.g_Buffer != "kept-on-failure`n" || Logger.g_BufferSize != 1)
    ExitApp(1)

path := A_Temp "\sdgo-logger-flush-" A_TickCount ".log"
try FileDelete(path)
Logger.g_LogFile := path
if (Logger.Flush() != true)
    ExitApp(1)
if (Logger.g_Buffer != "" || Logger.g_BufferSize != 0)
    ExitApp(1)
if (!InStr(FileRead(path, "UTF-8"), "kept-on-failure"))
    ExitApp(1)
try FileDelete(path)

FileAppend("logger_flush_test: PASS`n", "*")
ExitApp(0)
