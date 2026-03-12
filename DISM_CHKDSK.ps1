#Requires -Version 5.1
#region --- METADATA BLOCK ---

<# 
.SYNOPSIS
    WinRepair Utility - Windows System Diagnostics and Repair Script.

.DESCRIPTION
    Runs SFC, DISM, and CHKDSK to diagnose and repair common Windows issues.
    Logs all output to a timestamped file. Automatically detects USB drives 
	and prompts the user to save logs there if one is found.

.PARAMETER InvokeSFC
    Run the System File Checker scan.

.PARAMETER InvokeDISM
    Run the DISM image repair scan.

.PARAMETER InvokeCHKDSK
    Schedule a CHKDSK scan on the next reboot.

.PARAMETER RebootAfter
    Prompt the user to reboot after all tasks complete.

.PARAMETER UseCHKDSK_R
    Run CHKDSK with the /r flag for a deep bad sector scan.

.PARAMETER SFC
	Alias for InvokeSFC.

.PARAMETER DISM
	Alias for InvokeDISM.

.PARAMETER CHKDSK
	Alias for InvokeCHKDSK.

#>

#endregion

#region --- SCRIPT PARAMETERS ---

[CmdletBinding()]
param(
	# Internal command switches. 
	[switch]$InvokeSFC,
	[switch]$InvokeDISM,
	[switch]$InvokeCHKDSK,
	

	# User-friendly aliases.
	[switch]$SFC,
	[switch]$DISM,
	[switch]$CHKDSK,

	# Options.
	[switch]$RebootAfter,
	[switch]$UseCHKDSK_R
)

if ($SFC) { $InvokeSFC = $true }
if ($DISM) { $InvokeDISM = $true }
if ($CHKDSK) { $InvokeCHKDSK = $true }

#endregion

# region--- ADMIN ELEVATION ---

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
	
	Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
	exit
}

if (-not (Test-IsAdministrator)) {
	Write-Host "We are not running with the correct level of privileges, hold on fam, we about to fix this..." -ForegroundColor Yellow
	Start-ElevatedSelf
	}
#endregion


#region --- CONFIG & LOG SETUP ---

$defaultLogRoot = Join-Path $env:ProgramData "WinRepairUtility\Logs"
$logRoot = $defaultLogRoot

$usbDrive = Get-CimInstance Win32_LogicalDisk |
	Where-Object { $_.DriveType -eq 2 } |
	Select-Object -ExpandProperty DeviceID -First 1

if ($usbDrive) {

	Write-Host ""
	Write-Host "USB drive detected: $usbDrive." -ForegroundColor Green

	$usbChoice = Read-Host "Do you want to save logs to your fancy USB drive? (Y/N)"

	if ($usbChoice.ToUpper() -in @("Y","YES"))	{

		$logRoot = Join-Path $usbDrive "WinRepairUtility\Logs"
		Write-Host "Logs will be saved to the USB drive at: $logRoot" -ForegroundColor Green
	}
	else {

		Write-Host "Logs will be saved locally at: $defaultLogRoot" -ForegroundColor Cyan
	}
}
else {

	Write-Host "No USB drive detected. Logs will be saved locally at: $defaultLogRoot" -ForegroundColor Cyan
}

if (-not (Test-Path -Path $logRoot)) {
	New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logRoot "WinRepair_$timestamp.log"

"=== WinRepair Script Started: $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding utf8

$script:UseDeepDISM = $false
$script:ForceAutoReboot = $false
#endregion


#region --- HELPER FUNCTIONS ---

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

function Confirm-CHKDSKReboot {
	Write-Host ""
	Write-Host "WARNING:" -ForegroundColor Red
	Write-Host "This option includes CHKDSK on the system drive."
	Write-Host "CHKDSK cannot complete while Windows is running and WILL be scheuled for the next reboot."
	Write-Host "By continuing, the system will automatically reboot after the repair scans complete."
	Write-Host "There will be NO FURTHER reboot confirmation prompt prior to the system reboot."
	Write-Host ""

	$confirm1 = Read-Host "Are you sure you want to proceed with this option? (Y/N)"

	if ($confirm1.ToUpper() -notin @("Y", "YES")) {
		Write-Host "Returning to main menu..." -ForegroundColor Yellow
		return $false
	}

	$confirm2 = Read-Host "Are you absolutely sure? Last chance. (Y/N)"

	if ($confirm2.ToUpper() -notin @("Y", "YES")) {
		Write-Host "Returning to main menu..." -ForegroundColor Yellow
		return $false
	}

	Write-Host "Confirmation accepted. Now would be a great time to pull out a book, this is going to be a while...proceeding with the scan." -ForegroundColor Green

}

#endregion

#region --- QUICK-SELECT HELPER FUNCTIONS

function Set-QuickScanProfile{
	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $false
	$script:UseCHKDSK_R = $false
	$script:RebootAfter = $false
	$script:UseDeepDISM = $false

	Write-Log "Quick Scan selected. This will run DISM followed by SFC."

}

function Set-EnhancedScanProfile{
	if (-not (Confirm-CHKDSKReboot)) {
		return $false
	}

	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $true
	$script:UseCHKDSK_R = $false
	$script:RebootAfter = $true
	$script:UseDeepDISM = $false
	$script:ForceAutoReboot = $true

	Write-Log "Enhanced Scan selected. This will run DISM followed by SFC and then CHKDSK upon an automatic reboot once the first two scans are complete."
	return $true
}

function Set-DeepScanProfile{
		if (-not (Confirm-CHKDSKReboot)) {
		return $false
	}

	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $true
	$script:UseCHKDSK_R = $true
	$script:RebootAfter = $true
	$script:UseDeepDISM = $true
	$script:ForceAutoReboot = $true

	Write-Log "Deep Scan selected. This will run DISM followed by SFC and then CHKDSK upon an automatic reboot once the first two scans are complete."
	return $true

}

#endregion

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

#endregion


#region ---REPAIR FUNCTIONS---

function Invoke-DISM {
	Write-Log "Starting Deployment Image Servicing and Management (DISM) scan. This will check the health of the Windows image and attempt repairs if necessary."
	Write-Log "Grab a coffee, this might take a bit."
	
	if ($script:UseDeepDISM) {
		Write-Log "Deep DISM mode enabled. DISM will run ScanHealth before RestoreHealth."
		Write-Log "This will allow DISM to check for component store corruption. This will take a while."
		
		DISM /Online /Cleanup-Image /ScanHealth | Tee-Object -FilePath $logFile -Append
		
		$scanExitCode = $LASTEXITCODE
		Write-Log "DISM ScanHealth completed with exit code: $scanExitCode."

		switch ($scanExitCode) {
			0 { Write-Log "DISM ScanHealth completed successfully." }
			1 { Write-Log "DISM ScanHealth found issues with your Windows image. Review the log output for more details." }
			2 { Write-Log "DISM ScanHealth found issues with your Windows image and further corrective action may be required. Review the log for more details." }
	 		3 { Write-Log "DISM ScanHealth could not perform the requested operation. The scan may have failed or it was interrupted." }
			default { Write-Log "DISM ScanHealth encountered an unexpected error with exit code: $scanExitCode. Please check the logs for more details." }
	}

		Write-Log ""
	}

		Write-Log "Running DISM RestoreHealth. This will check the health of your Windows image and attempt repairs if necessary."
		Write-Log "This will take quite a while. You may want to go grab a coffee."

		DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append
		
		$exitCode = $LASTEXITCODE
		Write-Log "DISM RestoreHealth completed with exit code: $exitCode."

		switch ($exitCode) {
			0 { Write-Log "DISM RestoreHealth completed successfully. Your Windows image appears to be pretty healthy! Good job!" }
			1 { Write-Log "DISM RestoreHealth found issues with the Windows image. Review the log output for more details." }
			2 { Write-Log "DISM RestoreHealth found issues with the Windows image but was unable to fix some of them. Review the log for more details."}
	 		3 { Write-Log "DISM RestoreHealth could not perform the requested operation. The scan may have failed or it was interrupted." }
			default { Write-Log "DISM RestoreHealth encountered an unexpected error with exit code: $exitCode. Please check the logs for more details." }
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

function Invoke-AutoReboot {
	Write-Log "Automatic reboot has been scheduled. System will reboot in 30 seconds with no further prompts."
	Write-Log "Please save all your work and close any open applications immediately to avoid data loss."

	shutdown.exe /r /t 30 /c "WinRepair has completed DISM and SFC scans and is rebooting to complete final scan."
}

#endregion


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
	if ($script:ForceAutoReboot) {
		Write-Log "Automatic reboot mode is enabled for this scan profile."
		Invoke-AutoReboot
	}
	else {
		Invoke-RebootPrompt
	}
}
else {
	Write-Log "RebootAfter switch is not engaged. The script will end without prompting for a reboot."
}

Write-Log "=== WinRepair Script Completed all selected tasks. $(Get-Date) ==="
Write-Log "That's all folks! No more to see here, I am sure you have other things to do."
Write-Log "Thank you for using the WinRepair Utility. Have a GREAT day!"

#endregion