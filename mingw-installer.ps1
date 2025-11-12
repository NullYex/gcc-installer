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
        $file = Get-Item -LiteralPath $FilePath -ErrorAction SilentlyContinue
        if (-not $file) {
            return
        }
        
        $processes = Get-Process | Where-Object {
            try {
                $_.Modules | Where-Object { $_.FileName -eq $FilePath }
            } catch {
                $null
            }
        }
        
        $directoryPath = Split-Path -Path $FilePath -Parent
        $processes += Get-Process | Where-Object {
            try {
                $_.Path -and $_.Path.StartsWith($directoryPath, [StringComparison]::OrdinalIgnoreCase)
            } catch {
                $false
            }
        }
        
        $processes = $processes | Select-Object -Unique
        
        foreach ($proc in $processes) {
            try {
                Write-Host "Killing process: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Gray
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 200
            } catch {}
        }
        
        Start-Sleep -Milliseconds 500
    }
    catch {}
}

function Force-DeleteFile {
    param([string]$Path)
    
    if (Test-Path -LiteralPath $Path) {
        try {
            Write-Host "[INFO] Attempting to remove file: $Path" -ForegroundColor Gray
            Kill-LockingProcesses -FilePath $Path
            
            Set-ItemProperty -LiteralPath $Path -Name Attributes -Value Normal -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            Write-Host "[OK] File removed successfully`n" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARNING] Could not remove file: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "`n[INFO] Please re-start your pc and re-run this script!`n " -ForegroundColor Cyan
            exit 1
        }
    }
}

function Kill-ProcessesUsingDirectory {
    param([string]$Path)
    
    try {
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
    catch {}
}

function Test-AdminPrivileges {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[WARNING] This script requires administrator privileges!" -ForegroundColor Yellow
        Write-Host "[INFO] Restarting with admin privileges...`n" -ForegroundColor Cyan
        
        try {
            $url = "https://raw.githubusercontent.com/NullYex/gcc-installer/main/mingw-installer.ps1"
            $command = "irm $url | iex; Read-Host 'Press Enter to exit'"
            
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$command`""
            exit 0
        }
        catch {
            Write-Host "[ERROR] Failed to restart as administrator." -ForegroundColor Red
            Write-Host "[INFO] Please manually run PowerShell as Administrator and retry." -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to exit"
            exit 1
        }
    }
}

function Ensure-Directory {
    param([string]$Path)
    
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
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
        Write-Host "`n[DOWNLOAD] Killing processes and preparing for download..." -ForegroundColor Cyan
        
        $parentDir = Split-Path -Path $DestinationPath -Parent
        Kill-ProcessesUsingDirectory -Path $parentDir
        
        Write-Host ""
        
        if (Test-Path -LiteralPath $DestinationPath) {
            Force-DeleteFile -Path $DestinationPath
        }
               
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.Timeout = 30000
        $request.UserAgent = "PowerShell/7.0"
        
        $response = $request.GetResponse()
        [long]$fileSizeBytes = $response.ContentLength
        $fileSizeMB = [math]::Round($fileSizeBytes / 1MB, 2)
        
        Write-Host "[DOWNLOAD] Downloading MinGW... ($fileSizeMB MB)`n" -ForegroundColor Cyan
        
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
        
        Write-Host "`n`n[OK] Download completed successfully!`n" -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
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
        
        Write-Host "`n[EXTRACT] Extracting MinGW..." -ForegroundColor Cyan
        
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
                $targetDir = Split-Path -Path $targetPath -Parent
                $null = New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction SilentlyContinue
                
                if (Test-Path -LiteralPath $targetPath) {
                    try {
                        Set-ItemProperty -LiteralPath $targetPath -Name Attributes -Value Normal -ErrorAction SilentlyContinue
                        Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
                
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
        
        $zip.Dispose()
        Write-Host "`n`n[OK] Extraction completed!`n" -ForegroundColor Green
    }
    catch {
        Write-Host "`n[ERROR] Extraction failed: $($_.Exception.Message)`n" -ForegroundColor Red
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
        $shortcutDir = Split-Path -Path $ShortcutPath -Parent
        Ensure-Directory -Path $shortcutDir
        
        if (Test-Path -LiteralPath $ShortcutPath) {
            Remove-Item -LiteralPath $ShortcutPath -Force -ErrorAction SilentlyContinue
        }
        
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortCut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.Description = $Description
        
        if ($WorkingDirectory) {
            $shortcut.WorkingDirectory = $WorkingDirectory
        }
        else {
            $shortcut.WorkingDirectory = Split-Path -Path $TargetPath -Parent
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
Write-Host "[SETUP] Setting up pre-installed MinGW-gcc...`n" -ForegroundColor Yellow

Ensure-Directory -Path $mingwDir
Download-FileOptimized -Url $mingwUrl -DestinationPath $mingwZip
Extract-Archive-Optimized -ZipPath $mingwZip -DestinationPath $mingwDir

Remove-Item -LiteralPath $mingwZip -Force -ErrorAction SilentlyContinue
Write-Host "[CLEANUP] Cleaned up temporary files`n" -ForegroundColor Gray

$mingwBinDir = Join-Path $mingwDir "bin"

if (-not (Test-Path -LiteralPath $mingwBinDir -PathType Container)) {
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

if (Test-Path -LiteralPath $guiExePath) {
    $shortcutCreated = Create-Shortcut -TargetPath $guiExePath -ShortcutPath $shortcutPath -Description "MinGW Package Manager" -WorkingDirectory (Split-Path -Path $guiExePath -Parent)
}
else {
    Write-Host "[WARNING] GUI executable not found at $guiExePath" -ForegroundColor Yellow
    Write-Host "[INFO] Shortcut creation skipped" -ForegroundColor Gray
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   [SUCCESS] Installation Completed, Enjoy!" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Cyan
