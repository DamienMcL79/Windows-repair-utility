[CmdletBinding()]
param(
	[switch]$RunSFC,
	[switch]$RunDISM,
	[switch]$RunCHKDSK,
	[switch]$RebootAfter,
	[switch]$UseCHKDSK_R,
	[switch]$PreferUSBLog
)

# Ensure script is running with admin privileges, otherwise re-launch with admin rights

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

		if ($RunSFC) { $arguments += "-RunSFC" }
		if ($RunDISM) { $arguments += "-RunDISM" }
		if ($RunCHKDSK) { $arguments += "-RunCHKDSK" }
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

# Determine log location

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
#Create log folder if it doesn't exist

if (-not (Test-Path -Path $logRoot)) {
	New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
}

#Define log file with timestamp

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logRoot "WinRepair_$timestamp.log"

#Write initial log entry

"=== WinRepair Script Started: $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding utf8

function Write-Log {
	param(
		[string]$Message
	)
	if ([string]::IsNullOrWhiteSpace($Message)) {
		Write_Host ""
		Add-Content -Path $LogFile -Value ""
		return
	}
	$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$logEntry = "[$timeStamp] $Message"

	Write-Host $logEntry
	Add-Content -Path $logFile -Value $logEntry
}

Write-Log "Oh great, now you are making me write logs? Like I didn't have anything better to do? I guess, whatever..."
Write-Log "Logs will be saved to: $logFile"

# If no switches are provided, run all checks by default

if (-not ($RunSFC -or $RunDISM -or $RunCHKDSK)) {
	Write-Log "No repair task switches provided. Yay, chaos will reign! Run ALL the things! (SFC, DISM, CHKDSK)"
	$RunSFC = $true
	$RunDISM = $true
	$RunCHKDSK = $true
}
else {
	Write-Log "Repair task switches detected, we will run only the specified tasks. Your choice, your consequences!"
}

Write-Log "Task selection: Run SFC: $RunSFC, Run DISM: $RunDISM, Run CHKDSK: $RunCHKDSK"

#Run SFC 
#"Running SFC /scannow" | Tee-Object -filePath %logFile -Append
function Run-SFC {

	Write-Log "Starting System File Checker (SFC) scan. This may take a while. Go ahead, check out the break room, stretch your legs, maybe go touch some grass. I'll be here when you get back."
	sfc /scannow | Tee-Object -FilePath $logFile -Append
	$exitCode = $LASTEXITCODE
	Write-Log "SFC scan completed with exit code: $exitCode."

	switch ($exitCode){
		0 { Write-Log "SFC did not find any integrity violations. Your system files are in good shape! Congrats, you win a cookie!" }
		1 { Write-Log "SFC found integrity violations and successfully repaired them. Your system files have been fixed! Great job, you win a gold star!" }
		2 { Write-Log "SFC found integrity violations but was unable to fix some of them. Your system files may still be corrupted. Consider running SFC again or using DISM for further repairs. Don't worry, it's not the end of the world, just a minor setback!" }
		3 { Write-Log "SFC could not perform the requested operation. The scan may have failed or have been interrupted." }
		default { Write-Log "SFC encountered an unexpected error with exit code: $exitCode. Please check the logs for more details and consider seeking additional help if needed." }
	}

	Write-Log ""

} 

function Run-DISM {

	Write-Log "Starting Deployment Image Servicing and Management (DISM) scan. (It is really nerdy that I know the meanings of these acronyms, isn't it?) This will check the health of the Windows image and attempt repairs if necessary. Grab a coffee, this might take a bit."
	
	DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

	$exitCode = $LASTEXITCODE
	Write-Log "DISM scan completed with exit code: $exitCode."

	switch ($exitCode) {
		0 { Write-Log "DISM did not find any issues with the Windows image. Your system is in good shape! GREAT JOB!" }
		1 { Write-Log "DISM found issues with the Windows image and successfully repaired them. Your system has been fixed! That is great, now we can get back to work!" }
		2 { Write-Log "DISM found issues with the Windows image but was unable to fix some of them. Your system may still have problems. Consider running DISM again or I don't know, try something else?" }
		3 { Write-Log "DISM could not perform the requested operation. The scan may have failed or been interrupted." }
		default { Write-Log "DISM encountered an unexpected error with exit code: $exitCode. Please check the logs for more details and consider seeking additional help if needed." }
	}

	Write-Log ""

}

#Queue and run CHKDSK with Y

#if ($LASTEXITCODE -eq 0) {
#	Write-host "DISM completed successfully. Scheduling CHKDSK on next reboot" | Tee-Object -FilePath $logFile -Append
#	cmd /c "echo Y|chkdsk C: /f /r /x" | Tee-Object -FilePath $logFile -Append
#	Write-host "CHKDSK scheduled. Restarting in 30 seconds..." | Tee-Object -FilePath $logFile -Append
#	shutdown /r /t 30
#}
#else {
#	Write-Host "DISM failed. Check yo logs, sucka." | Tee-Object -FilePath $logFile -Append
#}
#
#"===> Script Completed. Thank you, please come again! <==="