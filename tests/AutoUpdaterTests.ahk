#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\Lib\ConfigManager.ahk
#Include %A_ScriptDir%\..\Lib\Logger.ahk
#Include %A_ScriptDir%\..\Lib\AutoUpdater.ahk

AssertEqual(actual, expected, message) {
    if (actual != expected)
        throw Error(message ": expected " expected ", got " actual)
}

AssertEqual(AutoUpdater.CompareVersions("1.0.1", "1.0.0"), 1, "newer patch version")
AssertEqual(AutoUpdater.CompareVersions("v2.2.1", "2.2.1"), 0, "v prefix")
AssertEqual(AutoUpdater.CompareVersions("2.10.0", "2.9.9"), 1, "numeric version comparison")
AssertEqual(AutoUpdater.CompareVersions("2.2.1", "2.2.1.0"), 0, "missing segment")
AssertEqual(AutoUpdater.CompareVersions("2.1.9", "2.2.0"), -1, "older version")
hashTestFile := A_Temp "\SDGO-AutoUpdaterHashTest.txt"
FileDelete(hashTestFile)
FileAppend("abc", hashTestFile, "UTF-8")
AssertEqual(StrLower(AutoUpdater.GetSha256(hashTestFile)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 calculation")
FileDelete(hashTestFile)
FileAppend("AutoUpdater tests passed`n", "*")
ExitApp(0)
