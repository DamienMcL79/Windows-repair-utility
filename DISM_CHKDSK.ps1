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

.PARAMETER SFC
	Alias for InvokeSFC.

.PARAMETER DISM
	Alias for InvokeDISM.

.PARAMETER DISMMode
	 Sets the DISM scan mode. Accepted values: CheckHealth, ScanHealth, RestoreHealth.

.PARAMETER CHKDSK
	Alias for InvokeCHKDSK.

.PARAMETER CHKDSKMode
	Sets the CHKDSK scan mode. Accepted values: F, FR, FRX, Scan, FB.

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
	[string]$CHKDSKMode,
	[string]$DISMMode,
	[switch]$ResumeDeepScan
)

if ($SFC) { $InvokeSFC = $true }
if ($DISM) { $InvokeDISM = $true }
if ($CHKDSK) { $InvokeCHKDSK = $true }
if ($CHKDSKMode) { $script:CHKDSKMode = $CHKDSKMode }
if ($DISMMode) { $script:DISMMode = $DISMMode }

#endregion

#region --- ADMIN ELEVATION ---

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
		if ($CHKDSKMode) { $arguments += "-CHKDSKMode `"$CHKDSKMode`"" }
		if ($DISMMode) { $arguments += "-DISMMode `"$DISMMode`"" }
		if ($ResumeDeepScan) { $arguments += "-ResumeDeepScan" }
	
	Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
	exit
}

if (-not (Test-IsAdministrator)) {
	Write-Host "We are not running with the correct level of privileges, hold on fam, we about to fix this..." -ForegroundColor Yellow
	Start-ElevatedSelf
	}
#endregion


#region --- CONFIG & LOG SETUP ---

$defaultLogRoot = Join-Path $env:SystemDrive "WinRepairUtility\Logs"
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

$script:DISMMode = $null
$script:ForceAutoReboot = $false
$script:CHKDSKMode = $null

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
	Write-Host "CHKDSK cannot complete while Windows is running and WILL be scheduled for the next reboot."
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

	return $true
}

#endregion

#region --- QUICK-SELECT HELPER FUNCTIONS --- 

function Set-QuickScanProfile{
	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $false
	$script:CHKDSKMode = $null
	$script:RebootAfter = $false
	$script:DISMMode = "ScanHealth"

	Write-Log "Quick Scan selected. This will run DISM ScanHealth followed by SFC."

}

function Set-EnhancedScanProfile{
	if (-not (Confirm-CHKDSKReboot)) {
		return $false
	}

	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $true

	$script:CHKDSKMode = "F"
	$script:RebootAfter = $true
	$script:ForceAutoReboot = $true
	
	$script:DISMMode = "ScanHealth"
	

	Write-Log "Enhanced Scan selected. This will run DISM ScanHealth, followed by SFC, and then CHKDSK upon an automatic reboot once the first two scans are complete."
	return $true
}

function Set-DeepScanProfile{
		if (-not (Confirm-CHKDSKReboot)) {
		return $false
	}

	$script:InvokeDISM = $false
	$script:InvokeSFC = $false
	$script:InvokeCHKDSK = $true
	$script:CHKDSKMode = "FR"
	$script:RebootAfter = $true
	$script:DISMMode = "RestoreHealth"
	$script:ForceAutoReboot = $true

	Write-Log "Deep Scan selected. This will reboot your system and upon reboot it will run CHKDSK. Once CHKDSK is complete, system will load Windows and continue with diagnostics, running DISM RestoreHealth followed by SFC. You will be prompted to perform a full shutdown at the end to complete the final phase of repairs."
	Write-Log "This is the most comprehensive scan profile, but it will take the longest to complete. It's recommended to run this scan when you have a good amount of time set aside and do not need to use your computer for a while."

	if (-not (Register-DeepScanResumeTask)) {
		Write-Log "Deep Scan aborted. Scheduled task could not be created."
		return $false
	}

	return $true
}

#endregion

#region --- MENU SUPPORT FUNCTIONS ---

function Show-MainMenu {
		do {
			Clear-Host
        	Write-Host ""
        	Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host "        WINREPAIR UTILITY - MAIN MENU          " -ForegroundColor White
        	Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host ""
        	Write-Host "  --- Individual Tools ---" -ForegroundColor Gray
        	Write-Host ""
        	Write-Host "  1.  DISM - Deployment Image Servicing and Management"
        	Write-Host "  2.  SFC  - System File Checker"
        	Write-Host "  3.  CHKDSK - Check Disk"
        	Write-Host ""
        	Write-Host "  --- Quick Select Profiles ---" -ForegroundColor Gray
        	Write-Host ""
        	Write-Host "  4.  Quick Scan    (DISM ScanHealth + SFC)"
        	Write-Host "  5.  Enhanced Scan (DISM ScanHealth + SFC + CHKDSK, auto reboot)"
        	Write-Host "  6.  Deep Scan     (CHKDSK first, then DISM RestoreHealth + SFC)"
        	Write-Host ""
        	Write-Host "  ---" -ForegroundColor DarkGray
        	Write-Host ""
        	Write-Host "  7.  Help"
        	Write-Host "  8.  Exit"
        	Write-Host ""
        	Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host ""
			
			$choice = Read-Host "   Enter selection [1-8]"

			switch ($choice.Trim()) {
				"1" { Show-DISMMenu }
				"2" {
						$script:DISMMode = $null
						Invoke-SFC
						Invoke-MenuPause
				}
				"3" { Show-CHKDSKMenu }
				"4" {
						Set-QuickScanProfile
						Invoke-DISM
						Invoke-SFC
						Invoke-MenuPause
					}
				"5" {
    				if (Set-EnhancedScanProfile) {
       					if (-not (Invoke-DISM)) {
            				Write-Log "DISM stage failed. Aborting Enhanced Scan."
            				Invoke-MenuPause
        				}
        				else {
            				Invoke-SFC
            				Invoke-CHKDSK
            				Invoke-AutoReboot
        				}
    				}
				}
				"6" {
						if (Set-DeepScanProfile) {
							Invoke-CHKDSK
							Invoke-AutoReboot
						}
					}
				"7" { Show-Help }
				"8" { Exit-WinRepair }
				default {
						Write-Host ""
						Write-Host " Invalid selection. Please select an option between 1 and 8" -ForegroundColor Yellow
						Start-Sleep -Seconds 2
					}
			}
		} while ($true)
}

function Invoke-MenuPause {
		Write-Host ""
		Write-Host "  Press any key to return to the main menu..." -ForegroundColor DarkGray
		$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-DISMMenu {
		do {
			Clear-Host
			Write-Host ""
       		Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host "        DISM - IMAGE SERVICING & MANAGEMENT    " -ForegroundColor White
        	Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host ""
        	Write-Host "  Select a DISM operation to run:" -ForegroundColor Gray
        	Write-Host ""
        	Write-Host "  1.  CheckHealth    - Quick corruption flag check (no repairs)"
        	Write-Host "  2.  ScanHealth     - Deep corruption scan (no repairs)"
        	Write-Host "  3.  RestoreHealth  - Scan and repair component store"
        	Write-Host ""
        	Write-Host "  ---" -ForegroundColor DarkGray
        	Write-Host ""
        	Write-Host "  4.  Return to the Main Menu." 
        	Write-Host ""
        	Write-Host "  =============================================" -ForegroundColor DarkGray
        	Write-Host "" 

        	$choice = Read-Host "  Enter selection [1-4]"

			switch ($choice.Trim()) {
				"1" {
					$script:DISMMode = "CheckHealth"
                	Write-Log "User selected DISM CheckHealth from menu."
                	if (-not (Invoke-DISM)) {
                    Write-Log "DISM CheckHealth encountered an issue."
                	}
                	Invoke-MenuPause
				}
				"2" {
					$script:DISMMode = "ScanHealth"
                	Write-Log "User selected DISM ScanHealth from menu."
                	if (-not (Invoke-DISM)) {
                    	Write-Log "DISM ScanHealth encountered an issue."
                	}
                	Invoke-MenuPause
				}
				"3" {
					$script:DISMMode = "RestoreHealth"
					Write-Log "User selected DISM RestoreHealth from menu."
					if (-not (Invoke-DISM)) {
						Write-Log "DISM RestoreHealth encountered an issue."
					}
					Invoke-MenuPause
				}
				"4" {
					return
				}			
				default {
					Write-Host ""
					Write-Host "  Invalid selection. Please select an option between 1 and 4." -ForegroundColor Yellow
					Start-Sleep -Seconds 2
				}
			}
		} while ($true)
}

function Show-CHKDSKMenu {
	do {
		Clear-Host
        Write-Host ""
        Write-Host "  =============================================" -ForegroundColor DarkGray
        Write-Host "        CHKDSK - CHECK DISK                    " -ForegroundColor White
        Write-Host "  =============================================" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Select a CHKDSK operation to run:" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  1.  /f          - Fix file system errors (schedules on reboot)"
        Write-Host "  2.  /f /r       - Fix errors + bad sector scan (schedules on reboot)"
        Write-Host "  3.  /f /r /x    - Fix errors + bad sectors + forced dismount (reboot)"
        Write-Host "  4.  /scan       - Online scan, no reboot required"
        Write-Host "  5.  /f /b       - Fix errors + full bad cluster re-evaluation (reboot)"
        Write-Host ""
        Write-Host "  ---" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  6.  Return to Main Menu"
        Write-Host ""
        Write-Host "  =============================================" -ForegroundColor DarkGray
        Write-Host ""

        $choice = Read-Host "  Enter selection [1-6]"

		switch ($choice.Trim()) {
			"1" {
				$script:CHKDSKMode = "F"
				Write-Log "User selected CHKDSK /f from menu."
				if (Confirm-CHKDSKReboot) {
					$script:InvokeCHKDSK = $true
					Invoke-CHKDSK
					Invoke-AutoReboot
				}
			}
			"2" {
				$script:CHKDSKMode = "FR"
				Write-Log "User selected CHKDSK /f /r from menu."
				if (Confirm-CHKDSKReboot) {
					$script:InvokeCHKDSK = $true
					Invoke-CHKDSK
					Invoke-AutoReboot
				}
			}
			"3" {
				$script:CHKDSKMode = "FRX"
				Write-Log "User selected CHKDSK /f /r /x from menu."
				if (Confirm-CHKDSKReboot) {
					$script:InvokeCHKDSK = $true
					Invoke-CHKDSK
					Invoke-AutoReboot
				}
			}
			"4" {
				$script:CHKDSKMode = "Scan"
				Write-Log "User selected CHKDSK /scan from menu."
				$script:InvokeCHKDSK = $true
				Invoke-CHKDSK
				Invoke-MenuPause
			}
			"5" {
				$script:CHKDSKMode = "FB"
				Write-Log "User selected CHKDSK /f /b from menu."
				if (Confirm-CHKDSKReboot) {
					$script:InvokeCHKDSK = $true
					Invoke-CHKDSK
					Invoke-AutoReboot
				}
			}
			"6" {
				return
			}
			default {
				Write-Host ""
				Write-Host " Invalid selection. Please select an option between 1 and 6." -ForegroundColor Yellow
				Start-Sleep -Seconds 2
			}
		}
	} while ($true)
}
function Show-Help {
	Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGray
    Write-Host "        WINREPAIR UTILITY - HELP               " -ForegroundColor White
    Write-Host "  =============================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --- INDIVIDUAL TOOLS ---" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  DISM (Deployment Image Servicing and Management)"
    Write-Host "  Scans and repairs the Windows component store. Four modes are available:"
    Write-Host "    CheckHealth   - Quick flag check only. No deep scan, no repairs."
    Write-Host "    ScanHealth    - Deep corruption scan. No repairs performed."
    Write-Host "    RestoreHealth - Scans and attempts to repair any corruption found."
    Write-Host "    ScanHealth with RestoreHealth fallback - Scans first, prompts"
    Write-Host "                    to repair if issues are found."
    Write-Host ""
    Write-Host "  SFC (System File Checker)"
    Write-Host "  Scans all protected Windows system files and attempts to repair"
    Write-Host "  any that are found to be corrupted or missing. Only one scan"
    Write-Host "  mode is available: scannow."
    Write-Host ""
    Write-Host "  CHKDSK (Check Disk)"
    Write-Host "  Scans the file system and disk surface for errors. Five modes:"
    Write-Host "    /f            - Fix file system errors. Schedules on reboot."
    Write-Host "    /f /r         - Fix errors and scan for bad sectors. Reboot."
    Write-Host "    /f /r /x      - Fix errors, bad sectors, forced dismount. Reboot."
    Write-Host "    /scan         - Online scan. No reboot required."
    Write-Host "    /f /b         - Fix errors and re-evaluate all bad clusters. Reboot."
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --- QUICK SELECT PROFILES ---" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Quick Scan"
    Write-Host "  Runs DISM ScanHealth followed by SFC. No reboot required."
    Write-Host "  Best for routine maintenance or a first pass on a suspect system."
    Write-Host ""
    Write-Host "  Enhanced Scan"
    Write-Host "  Runs DISM ScanHealth, then SFC, then schedules CHKDSK /f."
    Write-Host "  System reboots automatically after SFC to run CHKDSK."
    Write-Host "  Best for systems showing signs of instability or file system errors."
    Write-Host ""
    Write-Host "  Deep Scan"
    Write-Host "  Immediately reboots to run CHKDSK /f /r on the system drive."
    Write-Host "  After reboot, runs DISM RestoreHealth followed by SFC."
    Write-Host "  Ends with a full shutdown prompt for a complete power cycle."
    Write-Host "  Best for systems with suspected disk damage or severe corruption."
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press X to return to the main menu..." -ForegroundColor DarkGray
    Write-Host ""

    do {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } while ($key.Character -ne 'x' -and $key.Character -ne 'X')
}
#endregion

#region --- REPAIR FUNCTIONS---

function Invoke-DISM {
	Write-Log "Starting Deployment Image Servicing and Management (DISM) scan. "
	Write-Log "This will check the health of the Windows image and attempt repairs if necessary."

	function Write-LocalDISMExitCode {
		param(
			[string]$OperationName,
			[int]$ExitCode
		)

		Write-Log "$OperationName completed with exit code: $ExitCode."

		switch ($ExitCode) {
			0 { Write-Log "$OperationName completed successfully." }
			1 { Write-Log "$OperationName found issues with the Windows image. Review the log output for more details." }
			2 { Write-Log "$OperationName found issues with the Windows image and further corrective action may be required. Review the log for more details." }
			3 { Write-Log "$OperationName could not perform the requested operation. The scan may have failed or it was interrupted." }
			default { Write-Log "$OperationName encountered an unexpected error with exit code: $ExitCode. Please check the logs for more details." }
		}

		Write-Log ""
	}
	
	switch ($script:DISMMode) {

		"CheckHealth" {

			Write-Log "Running DISM Check Health. This performs a quick check to see if your Windows component store has any corruption flags. It will not find any new corruption as it does not perform a deep scan, and if corruption is found, it will not attempt repairs."

			DISM.exe /Online /Cleanup-Image /CheckHealth | Tee-Object -FilePath $logFile -Append

			$exitCode = $LASTEXITCODE
			Write-LocalDISMExitCode -OperationName "DISM CheckHealth" -ExitCode $exitCode
			
			if ($exitCode -ne 0) {
				Write-Log "DISM CheckHealth detected a flag indicating possible corruption. It is recommended you run DISM RestoreHealth to perform a deep scan and attempt repairs."
			}
			else {
				Write-Log "DISM CheckHealth found no corruption flags. Component store appears to be healthy."
			}

		}

		"ScanHealth" {
			Write-Log "Running DISM Scan Health. This performs a deep corruption scan of the Windows component store. This tool does not perform repairs. If issues are found, you will be prompted to run Restore Health to repair damaged components."

			DISM.exe /Online /Cleanup-Image /ScanHealth | Tee-Object -FilePath $logFile -Append

			$exitCode = $LASTEXITCODE
			Write-LocalDISMExitCode -OperationName "DISM ScanHealth" -ExitCode $exitCode

			if ($exitCode -ne 0) {
				Write-Log "Component store corruption may have been detected."
				$repairChoice = Read-Host "DISM found some issues. Run Restore Health to attempt repairs? (Y/N)"

				if ($repairChoice.ToUpper() -in @("Y", "YES")) {
					Write-Log "Selection confirmed, preparing to run DISM Restore Health. Proceeding with repairs."

					DISM.exe /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

					$restoreExitCode = $LASTEXITCODE
					Write-LocalDISMExitCode -OperationName "DISM RestoreHealth" -ExitCode $restoreExitCode
				}
				else {
					Write-Log "User declined to run DISM Restore Health. Skipping repairs."
					Write-Log "Returning you to the main menu. Running DISM Restore Health is highly recommended prior to running other diagnostics. Please review the logs for more details."
					return $false							
				}
			}
		}
		"RestoreHealth" {
			Write-Log "Running DISM Restore Health. This will scan the Windows component store for corruption and attempts repairs."
			Write-Log "This process can take a while, especially if corruption is found and a repair is necessary."

			DISM.exe /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

			$exitCode = $LASTEXITCODE
			Write-LocalDISMExitCode -OperationName "DISM RestoreHealth" -ExitCode $exitCode
		}

		default {
			Write-Log "DISM mode was not specified. Defaulting to Scan Health."

			DISM.exe /Online /Cleanup-Image /ScanHealth | Tee-Object -FilePath $logFile -Append

			$exitCode = $LASTEXITCODE
			Write-LocalDISMExitCode -OperationName "DISM ScanHealth" -ExitCode $exitCode

			if ($exitCode -ne 0) {
				Write-Log "Component store corruption may have been detected."
				$repairChoice = Read-Host "DISM found some issues. Run Restore Health to attempt repairs? (Y/N)"

				if ($repairChoice.ToUpper() -in @("Y", "YES")) {
					Write-Log "Selection confirmed, preparing to run DISM Restore Health. Proceeding with repairs."

					DISM.exe /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $logFile -Append

					$restoreExitCode = $LASTEXITCODE
					Write-LocalDISMExitCode -OperationName "DISM RestoreHealth" -ExitCode $restoreExitCode
				}
				else {
					Write-Log "User declined to run DISM Restore Health. Skipping repairs."
					Write-Log "Returning you to the main menu. Running DISM Restore Health is highly recommended prior to running other diagnostics. Please review the logs for more details."
					return $false							
				}
			}
		}
	}

	return $true
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

	switch ($script:CHKDSKMode) {
		"F" {
			$chkdskArgs = "$systemDrive /f"
			Write-Log "CHKDSK mode: /f -- Standard error fix. CHKDSK will scan and fix file system errors upon next reboot."
		}
		"FR" {
			$chkdskArgs = "$systemDrive /f /r"
			Write-Log "CHKDSK mode: /f /r -- Error fix plus bad sector scan. This will take significantly longer than a standard scan. Will run upon next reboot."
		}
		"FRX" {
			$chkdskArgs = "$systemDrive /f /r /x"
			Write-Log "CHKDSK mode: /f /r /x -- Error fix, bad sector scan, and forced dismount. Most aggressive scan. Will not work on main system drive. "
		}
		"Scan" {
			$chkdskArgs = "$systemDrive /Scan"
			Write-Log "CHKDSK mode: /Scan -- Online scan. This scan runs without rebooting the machine or locking the volume."
		}
		"FB" {
			$chkdskArgs = "$systemDrive /f /b"
			Write-Log "CHKDSK mode: /f /b -- Error fix plus full bad cluster re-evaluation. This is the most thorough bad sector option but will also take the longest to complete."
		}
		default {
			$chkdskArgs = "$systemDrive /f"
			Write-Log "CHKDSK mode was not specified. Defaulting to /f"
		} 
	}

	if ($script:CHKDSKMode -eq "Scan") {
		Write-Log "Running CHKDSK online scan. This does not require a reboot."
		cmd.exe /c "chkdsk $chkdskArgs" | Tee-Object -FilePath $logFile -Append
		$exitCode = $LASTEXITCODE
		Write-Log "CHKDSK online scan completed with exit code: $exitCode."

		switch ($exitCode) {
			0 {Write-Log "CHKDSK online scan completed successfully."}
			1 {Write-Log "CHKDSK online scan completed. Some issues were discovered and queued for repair. A reboot may be required to apply fixes."}
			default {Write-Log "CHKDSK online scan encountered an unexpected error. Please check logs for more details. Exit code: $exitCode"}
		}
	}
	else {
		Write-Log "Queuing CHKDSK with automatic confirmation."
		cmd.exe /c "echo Y|chkdsk $chkdskArgs" | Tee-Object -FilePath $logFile -Append
		$exitCode = $LASTEXITCODE
		Write-Log "CHKDSK scheduling command completed with exit code: $exitCode."
		switch ($exitCode) {
			0		{Write-Log "CHKDSK successfully scheduled for next reboot. Save your work and restart when ready."}
			3		{Write-Log "CHKDSK successfully scheduled for next reboot. Volume is in use and will be checked on next startup."}
			1		{Write-Log "CHKDSK scheduling returned a non-zero exit code. Please check the logs for more details."}
			default {Write-Log "CHKDSK scheduling encountered an unexpected error with exit code: $exitCode."}
		}
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

	Write-Host ""
	Write-Host "   System will reboot in 30 seconds." -ForegroundColor Yellow
	Write-Host "   Press R to reboot immediately or wait for the countdown." -ForegroundColor Yellow
	Write-Host "" 

	for ($1 = 30; $1 -gt 0; $1--) {
		Write-Host "`r $1 seconds remaining...    " -NoNewLine -ForegroundColor Yellow
		
		if ($Host.UI.RawUI.KeyAvailable) {
			$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
			if($key.Character -eq 'r' -or $key.Character -eq 'R') {
				Write-Log "User triggered immediate reboot."
                Write-Host "`r  Rebooting now...              " -ForegroundColor Yellow
                shutdown.exe /r /t 0 /c "WinRepair: User triggered immediate reboot."
                return
			}
		}

		Start-Stop -Seconds 1

	}

	Write-Host "`r  Rebooting now...              " -ForegroundColor Yellow
}
function Register-DeepScanResumeTask {
    Write-Log "Registering scheduled task for Deep Scan post-reboot continuation."

    $taskName  = "WinRepair_DeepScanResume"
    $scriptPath = $PSCommandPath

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ResumeDeepScan"

    $trigger = New-ScheduledTaskTrigger -AtLogOn

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -RunOnlyIfNetworkAvailable:$false

    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Force | Out-Null

        Write-Log "Scheduled task '$taskName' registered successfully. It will run once on next login and resume the Deep Scan workflow."
        return $true
    }
    catch {
        Write-Log "Failed to register scheduled task. Error: $_"
        Write-Log "Deep Scan cannot continue without the scheduled task. Aborting."
        return $false
    }
}

function Remove-DeepScanResumeTask {
	$taskName = "WinRepair_DeepScanResume"

	try {
		if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
			Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
			Write-Log "Scheduled task '$taskName' removed successfully."
		}
		else {
			Write-Log "Scheduled task '$taskName' not found. No need to remove."
    	}
	}
	catch {
		Write-Log "Failed to remove scheduled task. Error: $_"
		Write-Log "Please check Task Scheduler on your system and remove any task named '$taskName' to prevent it from running again on next login."
	}
}
function Resume-DeepScanWorkflow {
	Remove-DeepScanResumeTask
	Write-Log "Resuming Deep Scan workflow after reboot."
	Write-Log "CHKDSK should complete upon reboot. Continuing with DISM RestoreHealth and SFC scans..."

	$script:DISMMode = "RestoreHealth"
	$script:InvokeDISM = $true
	$script:InvokeSFC = $true
	$script:InvokeCHKDSK = $false
	$script:RebootAfter = $false
	$script:ForceAutoReboot = $false

	Write-Log "Deep Scan resume: Launching DISM RestoreHealth scan..."

	if (-not (Invoke-DISM)) {
		Write-Log "DISM stage failed or halted. Main execution is stopping now."
		return
	}

	Invoke-SFC

	Write-Log "Deep Scan post-reboot repair phase is complete."
	Write-Log "A full shutdown is recommended. Once shutdown is complete, wait 30 to 60 seconds before powering on the system again."

	$powerCycleChoice = Read-Host "Shut down now so a full power cycle can be completed? (Y/N)"

	switch ($powerCycleChoice.ToUpper()) {
		{$_ -in @("Y", "YES")} {
			Write-Log "Shutting down now. Remember to wait 30 to 60 seconds after the system powers off before turning it back on to ensure a full power cycle."
			Stop-Computer -Force
		}
		default {
			Write-Log "Power cycle declined. Please remember to perform a full shutdown and power cycle as soon as possible to complete the repair process and ensure system stability."
		}
  	}
}

#endregion

#region --- MENU SYSTEMFUNCTION ---

function Exit-WinRepair {
	Write-Log ""
	Write-Log "Exiting WinRepair. Thank you for using the WinRepair Utility. Have a GREAT day!"
	Write-Log "Returning to command line..."
	Write-Log ""
	exit 	
}

#endregion

#region --- MAIN EXECUTION ---

if ($ResumeDeepScan) {
	Resume-DeepScanWorkflow
	Write-Log "Resuming Deep Scan workflow is complete. Ending script execution."
	return
}

Show-MainMenu

if ($InvokeDISM) {
	Write-Log "DISM switch is engaged. Launching DISM scan..."

	if (-not (Invoke-DISM)) {
			Write-Log "DISM stage reported that the workflow should stop. Main execution is halting now."
			return
	}
}
else {
	Write-Log "DISM switch is not engaged. Skipping DISM operation."
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