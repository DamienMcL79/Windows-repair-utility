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
		[Parameter(Mandatory)]
		[string]$Message
	)

	$timeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$logEntry = "[$timeStamp] $Message"

	Write-Host $logEntry
	Add-Content -Path $logFile -Value $logEntry
	}

Write-Log "Oh, now you are making me write logs? Alright, I guess I can do that."

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
	








#Run SFC 
#"Running SFC /scannow" | Tee-Object -filePath %logFile -Append
#fc /scannow | Tee-Object -filePath %logFile -Append 


#Run DISM
#"Running DISM" | Tee-Object -FilePath $logFile -Append
#DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

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