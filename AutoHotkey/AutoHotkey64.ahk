; ================================
; CS2 + PresentMon Benchmark Runner (AutoHotkey v2) v3.0
; Finds (or downloads) the official PresentMon console app -> closes any running PresentMon -> launches it armed with a hotkey
; Launches PresentMon ONCE (one capture session for every run). Then repeats runCount times:
;   start CS2 -> workshop map over console -> closes Console -> 6 Seconds later -> beeps -> capDelay seconds later presses the capture hotkey
;   -> waits for the run to finish -> quits CS2 by console -> runGap seconds -> next run (restartCS2EachRun = false reloads the map in one CS2 session instead).
; Each run gets its own CSV (...-1.csv, ...-2.csv, ...). PresentMon is stopped after the last run.
; CSV output goes to the "captures" folder next to this script.
; Notes: disable "Ask which account to use each time Steam start"
; If there is a "cs2_video.txt" CS2 Video Configuration file in the "cs2_video" folder it will copy that to your Steam Account and backup the existing cs2_video.txt
; ================================

#Requires AutoHotkey v2.0
#SingleInstance Force   ; a second copy would type into the same console and look like "extra" runs

; ---------- Settings ----------
; --- PresentMon capture (adjustable) ---
capKey    := "F5"      ; PresentMon --hotkey. Single key (F1-F12, etc.)
capTime   := 109       ; seconds recorded, PresentMon --timed
capDelay  := 0.5       ; seconds after benchmark start before recording begins (decimals OK; handled by AHK in ms, PresentMon --delay is left at 0)
runCount  := 1         ; number of benchmark runs in one CS2 session (whole number, 1 or more). Runs 2+ press the console key and type map_workshop again ON PURPOSE
runGap    := 1       ; seconds between the end of one run and the start of the next (decimals OK)
pmAdmin   := true      ; true = add --restart_as_admin (PresentMon needs admin or "Performance Log Users" group)
pmProcess := "cs2.exe" ; only record this process
endMarginSec := 15     ; extra seconds after capture ends before quitting CS2
consoleKeyToSend := "{sc029}"   ; key that TOGGLES the CS2 console (sc029 = the ` / ~ key left of 1). Change it if you rebound it.
reopenConsoleAfterRun := true   ; true = CS2 does NOT open the console by itself, so the script presses the console key (same as pressing ~ by hand) before every follow-up command: next run and final quit. It is a TOGGLE
quitViaConsole := true ; true = open the console and type quit (what worked when ~ was pressed by hand). If CS2 is still running, window close / Alt+F4 / process kill follow automatically
restartCS2EachRun := true   ; true = every run is a full cycle: start CS2 -> benchmark -> capture -> quit CS2 by console -> runGap -> next run. false = reload the map inside ONE CS2 session
quitConsoleWaitSeconds := 25  ; seconds CS2 gets to exit after the quit command before the script escalates
workshopMap := "de_dust2"     ; map inside the workshop addon. Typed explicitly; CS2's console autocomplete was adding it by itself
quitStepSeconds := 5   ; seconds to wait after each quit step before trying the next, stronger one
steamSilent := true   ; true = start Steam to tray without its window/friends list (only applies if Steam is not already running)

pmExe       := A_ScriptDir "\PresentMon\presentmon.exe"
pmBundledExe := A_ScriptDir "\CapFrameX_beta1.7.6.portable\PresentMon\PresentMon-2.3.1-x64.exe" ; official exe shipped inside the old bundle
pmFallbackUrl := "https://github.com/GameTechDev/PresentMon/releases/download/v2.3.1/PresentMon-2.3.1-x64.exe"
capturesDir := A_ScriptDir "\captures"
logFile     := A_ScriptDir "\benchmark.log"

steamExe := ResolveSteamExe()
steamArgs := steamSilent ? ' -silent -nofriendsui' : ''   ; Steam flags must come BEFORE -applaunch
workshopId   := "3240880604"
steamUserId := "1317333533"
; only needed to copy files there like cs2 video settings

cs2Win := "Counter-Strike 2 ahk_exe cs2.exe"   ; match by title AND process so no other window is picked
cs2WindowWaitSeconds := 120
postWindowSettleMs   := 15000
startHotkeyToSend := "{" capKey "}"   ; derived from capKey so they never disagree

closeConsoleDelayMs := 3000
mapStartDelayMs     := 6000
benchmarkDurationMs := (capTime + endMarginSec) * 1000   ; counted from the hotkey press (capDelay has already elapsed by then)

runCount := Max(1, Round(runCount))   ; guard against 0 / negative / decimals
Log("Script loaded: runCount=" runCount " runGap=" runGap " capDelay=" capDelay " capTime=" capTime " quitViaConsole=" quitViaConsole)
runGap   := Max(0, runGap)

; ---------- Elevation Helper ----------
EnsureAdminAndRerun() {
    if !A_IsAdmin {
        Log("Not admin; relaunching elevated…")
        try {
            Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
        } catch as e {
            MsgBox "Failed to request elevation:`n" e.Message, "Error", "Iconx"
        }
        ExitApp
    }
}

; ---------- Logging ----------
Log(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", logFile)
}

; ---------- PresentMon: detect -> acquire -> verify ----------
EnsurePresentMon() {

    ; 1. Detect: own folder, then the exe bundled with the old CapFrameX package
    if FileExist(pmExe)
        return
    if FileExist(pmBundledExe) {
        DirCreate(A_ScriptDir "\PresentMon")
        FileCopy(pmBundledExe, pmExe, 1)
        Log("Copied bundled PresentMon to " pmExe)
        return
    }
    ; 2. Acquire: official release from GitHub (latest, fallback to pinned)
    Log("PresentMon not found; downloading")
    DirCreate(A_ScriptDir "\PresentMon")
    ps := "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; "
        . "try{$u=(Invoke-RestMethod 'https://api.github.com/repos/GameTechDev/PresentMon/releases/latest' -UseBasicParsing).assets "
        . "| ? name -like 'PresentMon-*-x64.exe' | select -First 1 -Expand browser_download_url}catch{}; "
        . "if(-not $u){$u='" pmFallbackUrl "'}; "
        . "Invoke-WebRequest $u -OutFile '" pmExe "' -UseBasicParsing; "
        . "if((Get-Item '" pmExe "').Length -lt 100000){Remove-Item '" pmExe "'; exit 1}"
    RunWait('powershell -NoLogo -NoProfile -Command "' ps '"', , "Hide")
    ; 3. Verify
    if !FileExist(pmExe)
        ErrBox("PresentMon download failed.`n`nGet it from:`nhttps://github.com/GameTechDev/PresentMon/releases/latest`nand save it as:`n" pmExe)
    Log("PresentMon downloaded to " pmExe)
}

; ---------- Helpers ----------
ErrBox(txt) {
    MsgBox txt, "Error", "Iconx"
    ExitApp
}

; resolve Steam installation folder
steamExe := ResolveSteamExe()

ResolveSteamExe() {
    exe := SteamExeFromRegistry()
    if exe
        return exe

    ; Fallback: default folder
    defaultExe := A_Is64bitOS
        ? "C:\Program Files (x86)\Steam\steam.exe"
        : "C:\Program Files\Steam\steam.exe"
    return FileExist(defaultExe) ? defaultExe : ""
}

SteamExeFromRegistry() {
    ; Prefer HKCU, then HKLM (WOW6432Node first on 64-bit)
    regCandidates := [
        ["HKCU\Software\Valve\Steam", "SteamExe"],    ; full path
        ["HKCU\Software\Valve\Steam", "SteamPath"],   ; folder
        ["HKLM\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"],
        ["HKLM\SOFTWARE\Valve\Steam", "InstallPath"]
    ]

    for pair in regCandidates {
        try {
            val := RegRead(pair[1], pair[2])
            exe := NormalizeSteamPathToExe(val)
            if exe && FileExist(exe)
                return exe
        }
    }
    return ""
}

NormalizeSteamPathToExe(val) {
    if !val
        return ""
    ; strip quotes and normalize
    val := Trim(val, ' "' . "`t`r`n")
    val := StrReplace(val, "/", "\")
    val := RTrim(val, "\")

    ; If the value is already the exe, keep it; otherwise append \steam.exe
    if InStr(StrLower(val), "steam.exe")
        return val
    return val "\steam.exe"
}

; Bring CS2 to the foreground and confirm it really has focus.
; Retries because Windows can refuse a focus change while another window (Steam, PresentMon, UAC) is active.
FocusCS2(attempts := 5) {
    Loop attempts {
        if WinActive(cs2Win)
            return true
        try WinActivate(cs2Win)          ; also restores the window if it is minimized
        if WinWaitActive(cs2Win, , 1)
            return true
    }
    Log("Could not focus CS2 after " attempts " attempts")
    return false
}

; Type directly into an already-open console and press Enter
TypeInConsole(cmd) {
    Log("Typing in console: " cmd)
    FocusCS2()
    Sleep 120
    ; Console is already open because of: +con_enable 1 -console +toggleconsole
    Send "{Text}" cmd
    Sleep 80
    Send "{Enter}"
}

; Open the console with the console key. The key is a TOGGLE, so call this only when the console is known to be closed.
OpenConsole() {
    Log("Opening console with the console key")
    FocusCS2()
    Sleep 150
    Send consoleKeyToSend
    Sleep 500   ; let the console open before typing
}

; Quit CS2. Default path never touches the console. Escalates fast, every step is logged:
; close window -> Alt+F4 -> end process -> taskkill /F
QuitCS2() {
    if (quitViaConsole) {
        if (reopenConsoleAfterRun)
            OpenConsole()
        TypeInConsole("quit")
        if CS2Closed(quitConsoleWaitSeconds)
            return
        Log("Quit: quit command did not close CS2")
    }

    Log("Quit: closing CS2 window")
    try WinClose(cs2Win)
    if CS2Closed(quitStepSeconds)
        return

    Log("Quit: window ignored the close; sending Alt+F4")
    if FocusCS2()
        Send "!{F4}"
    if CS2Closed(quitStepSeconds)
        return

    Log("Quit: ending cs2.exe (ProcessClose)")
    pid := ProcessClose(pmProcess)
    Log("Quit: ProcessClose returned PID " pid " (0 = nothing ended, e.g. access denied)")
    if CS2Closed(quitStepSeconds)
        return

    Log("Quit: ProcessClose failed; running taskkill /F")
    code := RunWait(A_ComSpec ' /c taskkill /F /T /IM ' pmProcess ' >> "' logFile '" 2>&1', , "Hide")
    Log("Quit: taskkill exit code " code " (its message is in the lines above)")
    if !CS2Closed(quitStepSeconds)
        Log("Quit: FAILED, cs2.exe is still running")
}

; Start CS2 through Steam, wait for its window, let it settle, give it focus.
; CS2 opens with its console already open (+toggleconsole), ready for the map command.
LaunchCS2() {
    if !FileExist(steamExe)
        ErrBox("Steam not found at:`n" steamExe)
    Run('"' steamExe '"' steamArgs ' -applaunch 730 +con_enable 1 -console +toggleconsole')
    Log("Steam launch: silent=" steamSilent)
    if !WinWait(cs2Win, , cs2WindowWaitSeconds) {
        Log("CS2 window not detected within timeout")
        MsgBox "Couldn't detect the CS2 window within ~" cs2WindowWaitSeconds " seconds.", "Notice"
    } else {
        Log("CS2 window detected; focusing: " (FocusCS2() ? "OK" : "FAILED"))
    }
    Sleep postWindowSettleMs
    FocusCS2()   ; Steam / PresentMon may have taken focus during the settle time
}

; Stop the single PresentMon session cleanly (a force-kill leaves the capture session behind).
StopPresentMon() {
    if !ProcessExist(pmExeName)
        return
    Log("Stopping PresentMon")
    try RunWait('"' pmExe '" --terminate_existing_session', , "Hide")
    if !ProcessWaitClose(pmExeName, 5)
        return
    Log("PresentMon still running; ending it")
    ProcessClose(pmExeName)
}

; True once no cs2.exe process exists (waits up to secs).
CS2Closed(secs) {
    if ProcessWaitClose(pmProcess, secs)
        return false
    Log("Quit: CS2 is closed")
    return true
}


; --- 1b) Prepare cs2_video config BEFORE launching Steam/CS2 ---
; This step is OPTIONAL. Set doPrepareVideoConfig := true if you want to run it.
doPrepareVideoConfig := false

if (doPrepareVideoConfig) {
sourceVideo := A_ScriptDir "\cs2_video\cs2_video.txt"
cfgFolder   := "C:\Program Files (x86)\Steam2\userdata\" steamUserId "\730\local\cfg"
targetVideo := cfgFolder "\cs2_video.txt"

Log("cs2_video copy: source=" sourceVideo)
Log("cs2_video copy: cfgFolder=" cfgFolder)
Log("cs2_video copy: target=" targetVideo)

; If source file does not exist, skip this step (no exit)
if !FileExist(sourceVideo) {
    Log("Source cs2_video.txt not found — skipping copy/backup step")
} else {
    ; Ensure destination exists AND we have write permission (write-test)
    try {
        DirCreate(cfgFolder)
        f := FileOpen(cfgFolder "\.__writetest.tmp", "w")
        f.Write("ok")
        f.Close()
        FileDelete cfgFolder "\.__writetest.tmp"
        Log("Write test OK in cfgFolder")
    } catch as e {
        Log("Write test FAILED: " e.Message " | Extra=" e.Extra)
        EnsureAdminAndRerun()
    }

    ; Backup existing file (timestamped) if present
    if FileExist(targetVideo) {
        ts := FormatTime(, "yyyyMMdd-HHmmss")
        backup := cfgFolder "\cs2_video.backup." ts ".txt"
        try {
            FileCopy(targetVideo, backup, 1)
            Log("Backed up existing to: " backup)
        } catch as e {
            ErrBox("Failed to back up existing cs2_video.txt:`n" e.Message "`n`nFrom: " targetVideo "`nTo: " backup)
        }
    }

    ; Copy new file (overwrite)
    try {
        FileCopy(sourceVideo, targetVideo, 1)
        Log("Copied cs2_video.txt to target")
    } catch as e {
        ErrBox("Failed to copy cs2_video.txt into cfg folder:`n" e.Message "`n`nFrom: " sourceVideo "`nTo: " targetVideo)
    }
}

}



; --- PresentMon: ensure installed, close if already running, then launch armed ---
EnsurePresentMon()

pmExeName := "presentmon.exe"
if ProcessExist(pmExeName) {
    Log("PresentMon already running; closing")
    ProcessClose pmExeName
    ProcessWaitClose(pmExeName, 5)
}

DirCreate(capturesDir)
outFile := capturesDir "\CS2_" FormatTime(, "yyyyMMdd-HHmmss") ".csv"
; No --terminate_on_proc_exit: ONE PresentMon session must survive CS2 quitting between runs; the script stops it after the last run.
pmArgs := ' --process_name ' pmProcess
        . ' --multi_csv --no_console_stats'
        . ' --hotkey "' capKey '"'
        . ' --timed ' capTime
        . ' --stop_existing_session'    ; a force-killed PresentMon leaves its capture session behind and the next start exits with an error
        . ' --output_file "' outFile '"'
        . (pmAdmin ? ' --restart_as_admin' : '')
Log("Launching: " pmExe pmArgs)
Run('"' pmExe '"' pmArgs, capturesDir, "Min")
Sleep 4000   ; allow UAC prompt / ETW session start

; Fail fast: without PresentMon the whole benchmark would run with nothing captured.
; (While a UAC prompt is open PresentMon is still alive, so this only trips when it really exited.)
if !ProcessExist(pmExeName) {
    Log("PresentMon is NOT running after launch")
    ErrBox("PresentMon closed right after launch, so nothing would be captured.`n`n"
         . "Likely causes: the UAC prompt was declined/missed, or an error in its arguments.`n"
         . "To see the error, paste this in an Administrator Command Prompt:`n`n"
         . '"' pmExe '"' pmArgs)
}
Log("PresentMon is running")

; 3-7) Benchmark runs. PresentMon is already running and stays up for ALL runs (one session).
; restartCS2EachRun = true : every run starts CS2, benchmarks, captures, quits CS2 by console.
; restartCS2EachRun = false: CS2 starts once and the map is reloaded between runs.
Loop runCount {
    runNo := A_Index
    isLastRun := (runNo = runCount)
    Log("Run " runNo "/" runCount " starting" (isLastRun ? " (LAST run)" : " (more runs follow)"))
    Loop runNo {                       ; audible run number: 1 beep = run 1, 2 beeps = run 2, ...
        SoundBeep 800, 80
        Sleep 120
    }

    ; CS2 up with an open console
    if (runNo = 1 || restartCS2EachRun)
        LaunchCS2()
    else if (reopenConsoleAfterRun)
        OpenConsole()                  ; same CS2 session: console is closed, press the console key

    ; 5) Run workshop map
    TypeInConsole("map_workshop " workshopId " " workshopMap)
    Sleep closeConsoleDelayMs
    Send "{Escape}" ; close console so the benchmark view is clean

    ; 6) Start capture after map loads
    Sleep mapStartDelayMs
    SoundBeep 1500, 150
    Sleep 100
    SoundBeep 2000, 150
    Sleep Round(capDelay * 1000)   ; capture begins capDelay seconds after benchmark start
    Send startHotkeyToSend
    Log("Run " runNo "/" runCount ": capture hotkey sent (CSV index -" runNo ")")

    ; 7) Wait for the capture to finish (+ margin)
    Sleep benchmarkDurationMs

    ; 8) Quit CS2 by console (every run in restart mode, otherwise after the last run)
    if (restartCS2EachRun || isLastRun)
        QuitCS2()

    ; Gap before the next run starts
    if (!isLastRun) {
        Log("Run " runNo "/" runCount " done; waiting " runGap " s before the next run")
        Sleep Round(runGap * 1000)
    } else {
        Log("Run " runNo "/" runCount " was the LAST run")
    }
}

; 9) Cleanup: stop the single PresentMon session
StopPresentMon()
Log("Done. " runCount " run(s). CSV files are in " capturesDir)
consoleKey := "{F10}"

steamUserId := "1317333533"
