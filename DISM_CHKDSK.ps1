[CmdletBinding()]
param(
	[switch]$RunSFC,
	[switch]$RunDISM,
	[switch]$RunCHKDSK,
	[switch]$RebootAfter,
	[switch]$UseCHKDSK_R
)

# Ensure script is running with admin privileges, otherwise re-launch with admin rights

function Test-IsAdministrator {
	$indentity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($indentity)
	return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
	
	$arguments = @(
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", "`"$PSCommandPath`""
		)
	
	Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
}

if (-not (Test-IsAdministrator)) {
	Write-Host "We are not running with the correct level of privileges, hold on fam, we about to fix this..." -ForegroundColor Yellow
	Start-ElevatedSelf
}

#Detect USB drive

$usbDrive = (Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 } | Select-Object -ExpandProperty DeviceID -First 1)
if (-not $usbDrive) { $usbDrive = "C:" }

#Create log folder

$logFolder = "$usbDrive\DISM_Logs"
if (-not (Test-Path $logFolder)) { 

	New-Item -ItemType Directory -Path $logFolder | Out-Null 
}

#Define Log file

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "$logFolder\DISM_CHKDSK_$timestamp.log"

#Log Start

"=== SFC + DISM + CHKDSK Script Started $(Get-Date) ===" | Out-File -FilePath $logFile -Encoding utf8 -Append

#Run SFC 
"Running SFC /scannow" | Tee-Object -filePath %logFile -Append
sfc /scannow | Tee-Object -filePath %logFile -Append 


#Run DISM
"Running DISM" | Tee-Object -FilePath $logFile -Append
DISM /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

#Queue and run CHKDSK with Y

if ($LASTEXITCODE -eq 0) {
	Write-host "DISM completed successfully. Scheduling CHKDSK on next reboot" | Tee-Object -FilePath $logFile -Append
	cmd /c "echo Y|chkdsk C: /f /r /x" | Tee-Object -FilePath $logFile -Append
	Write-host "CHKDSK scheduled. Restarting in 30 seconds..." | Tee-Object -FilePath $logFile -Append
	shutdown /r /t 30
}else {
	Write-Host "DISM failed. Check yo logs, sucka." | Tee-Object -FilePath $logFile -Append
}

"===> Script Completed. Thank you, please come again! <==="