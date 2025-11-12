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
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
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
    Write-Host "  Shortcut creation skipped" -ForegroundColor Gray
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
