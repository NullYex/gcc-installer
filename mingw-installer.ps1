$ErrorActionPreference = 'Stop'
$mingwDir = Join-Path $env:SystemDrive "MinGW"
$mingwUrl = "https://github.com/NullYex/gcc-installer/releases/download/mingw-gcc/MinGW.zip"
$mingwZip = Join-Path $mingwDir "MinGW.zip"
$guiExePath = Join-Path $mingwDir "libexec\mingw-get\guimain.exe"
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$shortcutPath = Join-Path $startMenuDir "MinGW Manager.lnk"

function Show-AsciiArt {
    Write-Host "`n`n   MingW Pre-Installed Setup by NullYex Team" -ForegroundColor Cyan
    Write-Host "---------------------------------------" -ForegroundColor Cyan
    Write-Host "  Now, No more fking with Mingw setup! " -ForegroundColor Cyan
    Write-Host "---------------------------------------`n`n" -ForegroundColor Cyan
}

function Kill-LockingProcesses {
    param([string]$FilePath)
    
    try {
        # Get file handle info to find what's locking it
        $file = Get-Item $FilePath -ErrorAction SilentlyContinue
        if (-not $file) {
            return
        }
        
        # Use handle.exe or alternative method to find locking processes
        # Alternative: Check all running processes for file access
        $processes = Get-Process | Where-Object {
            try {
                $_.Modules | Where-Object { $_.FileName -eq $FilePath }
            } catch {
                $null
            }
        }
        
        # Also check by directory since module check might miss some
        $directoryPath = Split-Path $FilePath -Parent
        $processes += Get-Process | Where-Object {
            try {
                $_.Path -and $_.Path.StartsWith($directoryPath, [StringComparison]::OrdinalIgnoreCase)
            } catch {
                $false
            }
        }
        
        # Kill duplicate processes
        $processes = $processes | Select-Object -Unique
        
        foreach ($proc in $processes) {
            try {
                Write-Host "Killing process: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Gray
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 200
            } catch {
                # Ignore
            }
        }
        
        Start-Sleep -Milliseconds 500
    }
    catch {
        # Silently continue
    }
}

function Force-DeleteFile {
    param([string]$Path)
    
    if (Test-Path $Path) {
        try {
            # Kill any processes that might be locking it
            Write-Host "Attempting to remove file: $Path" -ForegroundColor Gray
            Kill-LockingProcesses -FilePath $Path
            
            # Clear readonly attributes
            Set-ItemProperty -Path $Path -Name Attributes -Value Normal -ErrorAction SilentlyContinue
            
            # Wait a bit to ensure processes are fully killed
            Start-Sleep -Milliseconds 300
            
            # Try to delete
            Remove-Item -Path $Path -Force -ErrorAction Stop
            Write-Host "[OK] File removed successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARNING] Could not remove file: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "`n"
            Write-Host "[INFO] Please re-start your pc and re-run this script!`n " -ForegroundColor Yellow
        }
    }
}

function Kill-ProcessesUsingDirectory {
    param([string]$Path)
    
    try {
        # Kill any processes that might be using files from this directory
        Write-Host "[SETUP] Checking for processes using: $Path" -ForegroundColor Yellow
        
        $processes = Get-Process | Where-Object { 
            try { 
                $_.Path -and $_.Path.StartsWith($Path, [StringComparison]::OrdinalIgnoreCase) 
            } catch { 
                $false 
            }
        }
        
        if ($processes.Count -gt 0) {
            foreach ($proc in $processes) {
                try {
                    Write-Host "  Terminating: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Gray
                    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 200
                } catch {}
            }
            Start-Sleep -Milliseconds 500
        }
    }
    catch {
        # Silently continue if process enumeration fails
    }
}

function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[WARNING] This script requires administrator privileges!" -ForegroundColor Yellow
        Write-Host "Please run PowerShell as Administrator and retry." -ForegroundColor Yellow
        exit 1
    }
}

function Ensure-Directory {
    param([string]$Path)
    
    if (-not (Test-Path $Path -PathType Container)) {
        try {
            $null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
            Write-Host "[OK] Created directory: $Path" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to create directory: $Path" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
}

function Show-ProgressBar {
    param (
        [Parameter(Mandatory)]
        [double]$TotalValue,
        
        [Parameter(Mandatory)]
        [double]$CurrentValue,
        
        [Parameter(Mandatory)]
        [string]$ProgressText,
        
        [string]$Suffix = "",
        [int]$BarWidth = 30
    )
    
    $percent = [math]::Min($CurrentValue / $TotalValue, 1.0)
    $percentComplete = [math]::Round($percent * 100, 2)
    $filledWidth = [int]($BarWidth * $percent)
    
    $filledChar = [char]9608
    $emptyChar = [char]9617
    $bar = ($filledChar.ToString() * $filledWidth) + ($emptyChar.ToString() * ($BarWidth - $filledWidth))
    
    $currentDisplay = [math]::Round($CurrentValue, 2)
    $totalDisplay = [math]::Round($TotalValue, 2)

    $percentStr = $percentComplete.ToString("##0.00").PadLeft(6)
    $currentStr = $currentDisplay.ToString("#.##").PadLeft($totalDisplay.ToString("#.##").Length)
    
    Write-Host -NoNewLine "`r$ProgressText $bar [ $currentStr$Suffix / $totalDisplay$Suffix ] $percentStr%"
}

function Download-FileOptimized {
    param (
        [Parameter(Mandatory)]
        [string]$Url,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    try {
        Write-Host ""
        Write-Host "[DOWNLOAD] Killing processes and preparing for download..." -ForegroundColor Cyan
        
        # Kill processes from the directory first
        Kill-ProcessesUsingDirectory -Path (Split-Path $DestinationPath -Parent)
        
        Write-Host ""
        
        # Force delete existing file if it exists
        if (Test-Path $DestinationPath) {
            Force-DeleteFile -Path $DestinationPath
        }
               
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.Timeout = 30000
        $request.UserAgent = "PowerShell/7.0"
        
        $response = $request.GetResponse()
        [long]$fileSizeBytes = $response.ContentLength
        $fileSizeMB = [math]::Round($fileSizeBytes / 1MB, 2)
        
        Write-Host "[DOWNLOAD] Downloading MinGW... ($fileSizeMB MB)" -ForegroundColor Cyan
        Write-Host "`n"
        
        $responseStream = $response.GetResponseStream()
        $fileStream = [System.IO.FileStream]::new($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 65536)
        
        $buffer = [byte[]]::new(65536)
        [long]$totalBytesRead = 0
        [long]$bytesRead = 0
        
        do {
            $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -gt 0) {
                $fileStream.Write($buffer, 0, $bytesRead)
                $totalBytesRead += $bytesRead
                $totalMB = [math]::Round($totalBytesRead / 1MB, 2)
                
                Show-ProgressBar -TotalValue $fileSizeMB -CurrentValue $totalMB -ProgressText "Downloading" -Suffix "MB"
            }
        } while ($bytesRead -gt 0)
        
        $fileStream.Dispose()
        $responseStream.Dispose()
        $response.Dispose()
        
        Write-Host ""
        Write-Host "[OK] Download completed successfully!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Extract-Archive-Optimized {
    param (
        [Parameter(Mandatory)]
        [string]$ZipPath,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    try {
        Write-Host "[EXTRACT] Killing processes from extraction directory..." -ForegroundColor Cyan
        Kill-ProcessesUsingDirectory -Path $DestinationPath
        
        Write-Host ""
        Write-Host "[EXTRACT] Extracting MinGW..." -ForegroundColor Cyan
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $totalEntries = $zip.Entries.Count
        $currentEntry = 0
        
        foreach ($entry in $zip.Entries) {
            $currentEntry++
            $percent = [math]::Round(($currentEntry / $totalEntries) * 100, 2)
            Write-Host -NoNewLine "`r[$percent%] Extracting $currentEntry/$totalEntries files..."
            
            $targetPath = Join-Path $DestinationPath $entry.FullName
            
            if ($entry.Name -eq "") {
                $null = New-Item -Path $targetPath -ItemType Directory -Force -ErrorAction SilentlyContinue
            }
            else {
                $targetDir = Split-Path $targetPath -Parent
                $null = New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction SilentlyContinue
                
                # Force overwrite existing files
                if (Test-Path $targetPath) {
                    try {
                        Set-ItemProperty -Path $targetPath -Name Attributes -Value Normal -ErrorAction SilentlyContinue
                        Remove-Item -Path $targetPath -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
                
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
        
        $zip.Dispose()
        Write-Host ""
        Write-Host "[OK] Extraction completed!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host ""
        Write-Host "[ERROR] Extraction failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

function Add-ToPath {
    param (
        [Parameter(Mandatory)]
        [string]$PathToAdd,
        
        [string]$PathType = "User"
    )
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", $PathType)
    $pathArray = $currentPath -split ";"
    
    if ($pathArray -notcontains $PathToAdd) {
        $newPath = $PathToAdd + ";" + $currentPath
        [Environment]::SetEnvironmentVariable("PATH", $newPath, $PathType)
        return $true
    }
    return $false
}

function Create-Shortcut {
    param (
        [Parameter(Mandatory)]
        [string]$TargetPath,
        
        [Parameter(Mandatory)]
        [string]$ShortcutPath,
        
        [string]$Description = "",
        [string]$WorkingDirectory = ""
    )
    
    try {
        $shortcutDir = Split-Path $ShortcutPath -Parent
        Ensure-Directory -Path $shortcutDir
        
        if (Test-Path $ShortcutPath) {
            Remove-Item $ShortcutPath -Force -ErrorAction SilentlyContinue
        }
        
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortCut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.Description = $Description
        
        if ($WorkingDirectory) {
            $shortcut.WorkingDirectory = $WorkingDirectory
        }
        else {
            $shortcut.WorkingDirectory = Split-Path $TargetPath -Parent
        }
        
        $shortcut.Save()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shortcut) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
        
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to create shortcut: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Clear-Host
Show-AsciiArt
Test-AdminPrivileges
Write-Host "[SETUP] Setting up pre-installed MinGW-gcc..." -ForegroundColor Yellow
Write-Host ""

Ensure-Directory -Path $mingwDir
Download-FileOptimized -Url $mingwUrl -DestinationPath $mingwZip
Extract-Archive-Optimized -ZipPath $mingwZip -DestinationPath $mingwDir

Remove-Item -Path $mingwZip -Force -ErrorAction SilentlyContinue
Write-Host "[CLEANUP] Cleaned up temporary files" -ForegroundColor Gray
Write-Host ""

$mingwBinDir = Join-Path $mingwDir "bin"

if (-not (Test-Path $mingwBinDir -PathType Container)) {
    Write-Host "[WARNING] bin directory not found at $mingwBinDir" -ForegroundColor Yellow
    $mingwBinDir = $mingwDir
}

Write-Host "[PATH] Updating system PATH..." -ForegroundColor Cyan
$pathAdded = Add-ToPath -PathToAdd $mingwBinDir -PathType "User"

if ($pathAdded) {
    Write-Host "[OK] Added $mingwBinDir to User PATH" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Path already in environment" -ForegroundColor Gray
}

Write-Host ""

# Write-Host "[SHORTCUT] Creating Start Menu shortcut..." -ForegroundColor Cyan

if (Test-Path $guiExePath) {
    $shortcutCreated = Create-Shortcut -TargetPath $guiExePath -ShortcutPath $shortcutPath -Description "MinGW Package Manager" -WorkingDirectory (Split-Path $guiExePath -Parent)
    
    if ($shortcutCreated) {
        # Write-Host "[OK] Created shortcut: $shortcutPath" -ForegroundColor Green
    }
}
else {
    Write-Host "[WARNING] GUI executable not found at $guiExePath" -ForegroundColor Yellow
    Write-Host "Shortcut creation skipped" -ForegroundColor Gray
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Installation Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
# Write-Host "[INFO] Installation Directory: $mingwDir" -ForegroundColor Yellow
# Write-Host "[INFO] Binary Directory: $mingwBinDir" -ForegroundColor Yellow
# Write-Host "[INFO] Start Menu Shortcut: $shortcutPath" -ForegroundColor Yellow
# Write-Host ""
# Write-Host "[IMPORTANT] Please restart your terminal/PowerShell for PATH changes to take effect" -ForegroundColor Yellow
# Write-Host ""
