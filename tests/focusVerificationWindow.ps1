param([Parameter(Mandatory = $true)][string]$TitleFile, [int]$OwnerProcessId)

# Activate only the exact window title supplied by the owning MATLAB verifier.
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VerificationWindowFocus {
    public delegate bool WindowVisitor(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowVisitor visitor, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int length);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(IntPtr name, string title);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint first, uint second, bool attach);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr window);
}
'@
$verificationTitle = [IO.File]::ReadAllText($TitleFile)
$verificationWindow = [VerificationWindowFocus]::FindWindow([IntPtr]::Zero, $verificationTitle)
if ($verificationWindow -eq [IntPtr]::Zero) {
    $verificationOwners = [Collections.Generic.HashSet[int]]::new()
    [void]$verificationOwners.Add($OwnerProcessId)
    $verificationProcesses = Get-CimInstance Win32_Process
    do {
        $verificationAdded = $false
        foreach ($verificationItem in $verificationProcesses) {
            if ($verificationOwners.Contains([int]$verificationItem.ParentProcessId)) {
                if ($verificationOwners.Add([int]$verificationItem.ProcessId)) { $verificationAdded = $true }
            }
        }
    } while ($verificationAdded)
    $verificationCaptions = [Collections.Generic.List[string]]::new()
    $verificationVisitor = [VerificationWindowFocus+WindowVisitor]{
        param($verificationHandle, $verificationData)
        $verificationOwner = [uint32]0
        [void][VerificationWindowFocus]::GetWindowThreadProcessId($verificationHandle, [ref]$verificationOwner)
        if ($verificationOwners.Contains([int]$verificationOwner)) {
            $verificationCaption = [Text.StringBuilder]::new(512)
            [void][VerificationWindowFocus]::GetWindowText($verificationHandle, $verificationCaption, 512)
            if ($verificationCaption.Length -gt 0) { $verificationCaptions.Add($verificationCaption.ToString()) }
        }
        return $true
    }
    [void][VerificationWindowFocus]::EnumWindows($verificationVisitor, [IntPtr]::Zero)
    throw ('Verification window was not found. Owned captions: ' + ($verificationCaptions -join ' | '))
}
$verificationProcess = [uint32]0
$verificationForegroundThread = [VerificationWindowFocus]::GetWindowThreadProcessId([VerificationWindowFocus]::GetForegroundWindow(), [ref]$verificationProcess)
$verificationTargetThread = [VerificationWindowFocus]::GetWindowThreadProcessId($verificationWindow, [ref]$verificationProcess)
$verificationCurrentThread = [VerificationWindowFocus]::GetCurrentThreadId()
try {
    [void][VerificationWindowFocus]::AttachThreadInput($verificationCurrentThread, $verificationForegroundThread, $true)
    [void][VerificationWindowFocus]::AttachThreadInput($verificationCurrentThread, $verificationTargetThread, $true)
    [void][VerificationWindowFocus]::BringWindowToTop($verificationWindow)
    [void][VerificationWindowFocus]::SetForegroundWindow($verificationWindow)
    [void][VerificationWindowFocus]::SetFocus($verificationWindow)
} finally {
    [void][VerificationWindowFocus]::AttachThreadInput($verificationCurrentThread, $verificationTargetThread, $false)
    [void][VerificationWindowFocus]::AttachThreadInput($verificationCurrentThread, $verificationForegroundThread, $false)
}
if ([VerificationWindowFocus]::GetForegroundWindow() -ne $verificationWindow) {
    throw 'Verification window did not acquire foreground focus.'
}
