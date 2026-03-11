#Requires -Version 5.1
<# 
.SYNOPSIS
    WinRepair Utility - Windows System Diagnostics and Repair Script.

.DESCRIPTION
    Runs SFC, DISM, and CHKDSK to diagnose and repair common Windows issues.
    Logs all output to a timestamped file. Supports USB log redirection.

.PARAMETER RunSFC
    Run the System File Checker scan.

.PARAMETER RunDISM
    Run the DISM image repair scan.

.PARAMETER RunCHKDSK
    Schedule a CHKDSK scan on the next reboot.

.PARAMETER RebootAfter
    Prompt the user to reboot after all tasks complete.

.PARAMETER UseCHKDSK_R
    Run CHKDSK with the /r flag for a deep bad sector scan.

.PARAMETER PreferUSBLog
    Save logs to a detected USB drive instead of the local drive.
#>

#region --- Script Parameters ---

[CmdletBinding()]
param(
	[switch]$InvokeSFC,
	[switch]$InvokeDISM,
	[switch]$InvokeCHKDSK,
	[switch]$RebootAfter,
	[switch]$UseCHKDSK_R,
	[switch]$PreferUSBLog
)

#endregion


# Region---Admin Elevation---

function Test-IsAdministrator {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($identity)
	return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
	
	$arguments = @(
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", "`"$PSCommandPath`""
		)

		if ($InvokeSFC) { $arguments += "-InvokeSFC" }
		if ($InvokeDISM) { $arguments += "-InvokeDISM" }
		if ($InvokeCHKDSK) { $arguments += "-InvokeCHKDSK" }
		if ($RebootAfter) { $arguments += "-RebootAfter" }
		if ($UseCHKDSK_R) { $arguments += "-UseCHKDSK_R" }
		if ($PreferUSBLog) { $arguments += "-PreferUSBLog" }	
	
	Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
	exit
}

if (-not (Test-IsAdministrator)) {
	Write-Host "We are not running with the correct level of privileges, hold on fam, we about to fix this..." -ForegroundColor Yellow
	Start-ElevatedSelf
	}
#end region


#region --- Config & Log Setup ---

$defaultLogRoot = Join-Path $env:ProgramData "WinRepairUtility\Logs"
$logRoot = $defaultLogRoot

if ($PreferUSBLog) {
	$usbDrive = Get-CimInstance Win32_LogicalDisk |
		Where-Object { $_.DriveType -eq 2 } |
		Select-Object -ExpandProperty DeviceID -First 1

    if ($usbDrive) {
		$logRoot = Join-Path $usbDrive "WinRepairUtility\Logs"
		Write-Host "So, you inserted a USB drive, aren't YOU fancy? GOOD! Your logs will be saved to $logRoot" -ForegroundColor Green
	}
	else {
		Write-Host "No USB drive detected, logs will be saved to local drive at: $defaultLogRoot" -ForegroundColor Cyan
	}
}

if (-not (Test-Path -Path $logRoot)) {
	New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logRoot "WinRepair_$timestamp.log"

"=== WinRepair Script Started: $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding utf8

#endregion


#region --- Helper Functions ---

function Write-Log {
	param(
		[string]$Message
	)

	if ([string]::IsNullOrWhiteSpace($Message)) {
		Write-Host ""
		Add-Content -Path $logFile -Value ""
		return
	}

	$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$logEntry = "[$timeStamp] $Message"

	Write-Host $logEntry
	Add-Content -Path $logFile -Value $logEntry
}

#end region


#region --- STARTUP LOGGING & TASK SELECTION ---

Write-Log "Oh great, now you are making me write logs? Like I didn't have anything better to do? I guess, whatever..."
Write-Log "Logs will be saved to: $logFile"

if (-not ($InvokeSFC -or $InvokeDISM -or $InvokeCHKDSK)) {
	Write-Log "No repair task switches provided. Yay, chaos will reign! Run ALL the things! (SFC, DISM, CHKDSK)"
	$InvokeSFC = $true
	$InvokeDISM = $true
	$InvokeCHKDSK = $true
}
else {
	Write-Log "Repair task switches detected, we will run only the specified tasks. Your choice, your consequences!"
}

Write-Log "Task selection: SFC: $InvokeSFC, DISM: $InvokeDISM, CHKDSK: $InvokeCHKDSK"

#end region


#region ---REPAIR FUNCTIONS---

function Invoke-DISM {
	Write-Log "Starting Deployment Image Servicing and Management (DISM) scan. (It is really nerdy that I know the meanings of these acronyms, isn't it?) This will check the health of the Windows image and attempt repairs if necessary. Grab a coffee, this might take a bit."
	
	DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

	$exitCode = $LASTEXITCODE
	Write-Log "DISM scan completed with exit code: $exitCode."

	switch ($exitCode) {
		0 { Write-Log "DISM completed successfully. Your Windows image appears to be pretty healthy! Keep eating those apples champ!" }
		1 { Write-Log "DISM found issues with the Windows image. Review the log output for more details." }
		2 { Write-Log "DISM found issues with the Windows image but was unable to fix some of them. Review the log for more details...or if you are feeling spicy, I have ideas."}
	 	3 { Write-Log "DISM could not perform the requested operation. The scan may have failed or it was interrupted." }
		default { Write-Log "DISM encountered an unexpected error with exit code: $exitCode. Please check the logs for more details and consider seeking additional help if needed." }
	}

	Write-Log ""
}

function Invoke-SFC {
	Write-Log "Starting System File Checker (SFC) scan. This may take a while. Go ahead, check out the break room, stretch your legs, maybe go touch some grass. I'll be here when you get back."

	sfc /scannow | Tee-Object -FilePath $logFile -Append

	$exitCode = $LASTEXITCODE
	Write-Log "SFC scan completed with exit code: $exitCode."

	switch ($exitCode){
		0 { Write-Log "SFC did not find any integrity violations. Your system files are in good shape! Congrats, you win a cookie!" }
		1 { Write-Log "SFC found integrity violations and successfully repaired them. Your system files should be okay now. Great job, you win a gold star!" }
		2 { Write-Log "SFC found integrity violations but was unable to fix some of them. Your system files may still be corrupted. Consider running SFC again or using DISM for further repairs. Don't worry, it's not the end of the world, just a minor setback!" }
		3 { Write-Log "SFC could not perform the requested operation. The scan may have failed or it was interrupted." }
		default { Write-Log "SFC encountered an unexpected error with exit code: $exitCode. Please check the logs for more details and consider seeking additional help if needed." }
	}

	Write-Log ""
} 

function Invoke-CHKDSK {
	$systemDrive = $env:SystemDrive
	Write-Log "Preparing to schedule CHKDSK on system drive ($systemDrive)."

	if ($UseCHKDSK_R) {
		$chkdskArgs = "$systemDrive /f /r"
		Write-Log "CHKDSK will be scheduled with /f and /r. This is a deep scan so it will be thorough but will take an incredibly long time to complete. I'd recommend leaving the computer and coming back later."
	}
	else {
		$chkdskArgs = "$systemDrive /f"
		Write-Log "CHKDSK will be scheduled with /f. This will attempt to fix any errors it finds. Should be pretty quick, for a CHKDSK at least."
	}

	Write-Log "Queuing CHKDSK with automatic confirmation."

	cmd.exe /c "echo Y|chkdsk $chkdskArgs" | Tee-Object -FilePath $logFile -Append

	$exitCode = $LASTEXITCODE
	Write-Log "CHKDSK scheduling command completed with exit code: $exitCode."

	switch ($exitCode) {
		0 { Write-Log "CHKDSK was successfully scheduled for the next reboot. Your system will be checked for disk errors and repaired if necessary on the next startup. Don't forget to save your work and restart your computer soon!" }
		1 { Write-Log "CHKDSK scheduling command completed but returned a non-zero exit code. Please check the logs for more details." }
		default { Write-Log "CHKDSK scheduling command encountered an unexpected error with exit code: $exitCode. Please check the logs for more details and consider seeking additional help if needed." }
	}
}

function Invoke-RebootPrompt {
	Write-Log "Reboot switch has been engaged."
	$rebootChoice = Read-Host "Do you want to reboot now to allow CHKDSK to run? (Y/N)"

	switch ($rebootChoice.ToUpper()) {
		{$_ -in @("Y", "YES")} {
			Write-Log "Rebooting now. See you on the other side!"
			Restart-Computer -Force
		}
		default {
			Write-Log "Reboot declined. Script will end without restarting."
		}
  	}
} 

#end region


#region --- MAIN EXECUTION ---

if ($InvokeDISM) {
	Write-Log "DISM switch is engaged. Launching DISM scan..."
	Invoke-DISM
}
else {
	Write-Log "DISM switch is not engaged. Skipping DISM scan. Your Windows image will just be here not being scanned, should be okay, right?"
}

if ($InvokeSFC) {
	Write-Log "SFC switch is engaged. Launching SFC scan..."
	Invoke-SFC
}
else {
	Write-Log "SFC switch is not engaged. Skipping SFC scan. Your system files will remain unscanned and potentially corrupted. But hey, you seem to know what you're doing."
}	

if ($InvokeCHKDSK) {
	Write-Log "CHKDSK switch is engaged. Launching CHKDSK scheduling..."
	Invoke-CHKDSK
}
else {
	Write-Log "CHKDSK switch is not engaged. Skipping CHKDSK scheduling. I mean, at least you will have more time to do other things. Hopefully your disk passed the two previous diagnostic checks. If not, well, good luck with that!"
}

if ($RebootAfter) {
	Invoke-RebootPrompt
}
else {
	Write-Log "RebootAfter switch is not engaged. The script will end without prompting for a reboot."
}

Write-Log "=== WinRepair Script Completed all selected tasks. $(Get-Date) ==="
Write-Log "That's all folks! No more to see here, I am sure you have other things to do."
Write-Log "Thank you for using the WinRepair Utility. Have a GREAT day!"

#end region