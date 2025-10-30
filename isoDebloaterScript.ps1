# Windows ISO Debloater
# Author: itsNileshHere
# Date: 2023-11-21
# Description: A simple PSscript to modify windows iso file. For more info check README.md

param(
    [switch]$noPrompt,
    [string]$isoPath = "",
    [string]$winEdition = "",
    [string]$outputISO = "",
    [ValidateSet("yes", "no")]$useDISM = "",
    [ValidateSet("yes", "no")]$AppxRemove = "",
    [ValidateSet("yes", "no")]$CapabilitiesRemove = "",
    [ValidateSet("yes", "no")]$OnedriveRemove = "",
    [ValidateSet("yes", "no")]$EDGERemove = "",
    [ValidateSet("yes", "no")]$AIRemove = "",
    [ValidateSet("yes", "no")]$DefenderRemove = "",
    [ValidateSet("yes", "no")]$TPMBypass = "",
    [ValidateSet("yes", "no")]$UserFoldersEnable = "",
    [ValidateSet("yes", "no")]$ESDConvert = "",
    [ValidateSet("yes", "no")]$useOscdimg = ""
)

# If -noPrompt is used, ensure required parameters are provided
if ($noPrompt) {
    $missing = @("isoPath","winEdition","outputISO") | Where-Object { [string]::IsNullOrWhiteSpace((Get-Variable $_).Value) }
    if ($missing) { Write-Error "When using -noPrompt, these parameters are required: $($missing -join ', ')"; Exit 1 }
}

# Disable Pause if -noprompt is used
if ($noPrompt) { function Pause { } }

# Administrator Privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Re-launching with elevated privileges..." -ForegroundColor Yellow
    $params = @()
    $PSBoundParameters.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [switch] -and $_.Value) { $params += "-$($_.Key)" }
        elseif ($_.Value -is [string] -and $_.Value) { $params += "-$($_.Key)", "`"$($_.Value)`"" }
    }    
    $argss = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" $($params -join ' ')"
    if (Get-Command wt -ErrorAction SilentlyContinue) { Start-Process wt "PowerShell $argss" -Verb RunAs }
    else { Start-Process PowerShell $argss -Verb RunAs }
    Exit
}
Clear-Host
$asciiArt = @"
 _       ___           __                      _________ ____     ____       __    __            __           
| |     / (_)___  ____/ /___ _      _______   /  _/ ___// __ \   / __ \___  / /_  / /___  ____ _/ /____  _____
| | /| / / / __ \/ __  / __ \ | /| / / ___/   / / \__ \/ / / /  / / / / _ \/ __ \/ / __ \/ __ `/ __/ _ \/ ___/
| |/ |/ / / / / / /_/ / /_/ / |/ |/ (__  )  _/ / ___/ / /_/ /  / /_/ /  __/ /_/ / / /_/ / /_/ / /_/  __/ /    
|__/|__/_/_/ /_/\__,_/\____/|__/|__/____/  /___//____/\____/  /_____/\___/_.___/_/\____/\__,_/\__/\___/_/     
                                                                                        -By itsNileshHere                                                                                                  
"@

Write-Host $asciiArt -ForegroundColor Cyan
Start-Sleep -Milliseconds 1000
Write-Host "Starting Windows ISO Debloater Script..." -ForegroundColor Green
Start-Sleep -Milliseconds 800
Write-Host "`n*Important Notes: " -ForegroundColor Yellow
Write-Host "  1. Some prompts will appear during the process."
Write-Host "  2. Administrative privileges are required to run this script."
Write-Host "  3. Review the script beforehand to understand its actions."
Write-Host "  4. To whitelist a package, open the script and comment out the corresponding Packagename."
Write-Host "  5. Select the ISO to proceed."
Start-Sleep -Milliseconds 800

$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
$scriptDirectory = "$PSScriptRoot"
$logFilePath = Join-Path -Path $scriptDirectory -ChildPath 'script_log.txt'         # Log File Path
$transcript = "$env:TEMP\transcript_$(Get-Random).txt"                              # Start Transcript
Start-Transcript $transcript -Append -ErrorAction SilentlyContinue 2>&1 | Out-Null

# Get system information
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$logEntry = @"
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Script started
- Launched As: $((Get-CimInstance Win32_Process -Filter "ProcessId = $PID").CommandLine)
- Windows Version: $($osInfo.Caption) $($osInfo.Version) (Build $($osInfo.BuildNumber))
- System Architecture: $($osInfo.OSArchitecture)
- Install Date: $([Management.ManagementDateTimeConverter]::ToDateTime($osInfo.InstallDate).ToString())
- System Language: $((Get-Culture).DisplayName)
- Default Language: $((Get-UICulture).DisplayName)
- Windows Directory: $($env:windir)`n
"@

# Initialize log file
$logEntry | Out-File -FilePath $logFilePath -Append

# Function to write logs
function Write-Log {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline=$true)][object]$InputObj, [string]$msg, [switch]$Raw, [string]$Sep = " || ")
    process {
        $content = if ($msg) { $msg } elseif ($null -ne $InputObj) { if ($InputObj -is [string]) { $InputObj } else { $InputObj | Out-String } } else { return }
        if (-not $Raw -and ($content = $content.Trim())) {
            $lines = @($content -split '\n' | Where-Object { $_.Trim() })
            $cut = $lines | Where-Object { $_ -match '^\s*\+\s*(CategoryInfo|FullyQualifiedErrorId)\s*:' } | Select-Object -First 1
            if ($cut) { $lines = $lines[0..($lines.IndexOf($cut) - 1)] }
            if ($lines.Count -gt 1) {
                $processedLines = foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -match '^At\s+(.+)') { "At $($matches[1])" }
                    elseif ($trimmed -match '^\s*\+\s*~+') { continue }  # Skip underline line
                    elseif ($trimmed -match '^\s*\+\s*(.+)') { "+ " + ($matches[1] -replace '\s{2,}', ' ') }
                    elseif ($trimmed -match '^\s*\+?\s*(\w+\w+)\s*:\s*(.+)') { "$($matches[1]): $($matches[2])" }
                    elseif ($trimmed -notmatch '^-{4,}' -and $trimmed) { $trimmed -replace '\s{2,}', ' ' }
                }
                $content = $processedLines -join $Sep
            } else { $content = $content -replace '\s{2,}', ' ' }
        }
        if ($content) { Add-Content -Path "$logFilePath" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $content" }
    }
}

# Function to invoke DISM commands if powershell fails
function Invoke-DismFailsafe {
    param([scriptblock]$PS, [scriptblock]$Dism)
    if ($useDISM -ieq "yes") {
        & $Dism 2>&1 | Write-Log
    } else {
        try { & $PS 2>&1 | Write-Log } catch { & $Dism 2>&1 | Write-Log }
    }
}

# Confirmation Function
function Get-Confirmation { 
    param([string]$Question, [bool]$DefaultValue = $true, [string]$Description = "") 
    $defaultText = if ($DefaultValue) { "Y" } else { "N" }
    $optionsText = if ($DefaultValue) { "Y/n" } else { "y/N" }
    do { 
        Write-Host "$Question" -ForegroundColor Cyan -NoNewline
        if ($Description) { Write-Host " - $Description" -ForegroundColor DarkGray -NoNewline }
        Write-Host " ($optionsText): " -ForegroundColor White -NoNewline
        $answer = Read-Host 
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-Host "Using default: $defaultText" -ForegroundColor Yellow
            return $DefaultValue
        }
        $answer = $answer.ToUpper()
        if ($answer -eq 'Y') { return $true }
        if ($answer -eq 'N') { return $false }
        Write-Warning "Invalid input. Enter 'Y' for Yes, 'N' for No, or Enter for default ($defaultText)."
    } while ($true) 
}

# Parameter Value Validation Function
function Get-ParameterValue {
    param( [string]$ParameterValue, [bool]$DefaultValue, [string]$Question, [string]$Description )
    # If noPrompt is enabled, use default
    if ($noPrompt) {
        if ($ParameterValue -ne "") { return $ParameterValue -eq "yes" }
        else { return $DefaultValue }
    }
    # If noPrompt is null but param was provided, use the provided value
    if ($ParameterValue -ne "") { return $ParameterValue -eq "yes" }
    # If neither noPrompt nor param was provided, prompt the user
    return Get-Confirmation -Question $Question -DefaultValue $DefaultValue -Description $Description
}

# Cleanup Function
function Remove-TempFiles {
    Remove-Item -Path $destinationPath -Recurse -Force 2>&1 | Write-Log
    Remove-Item -Path $installMountDir -Recurse -Force 2>&1 | Write-Log
    Remove-Item -Path "$env:SystemDrive\WIDTemp" -Recurse -Force 2>&1 | Write-Log
    Stop-Transcript 2>&1 | Write-Log
    $content = Get-Content $transcript | Where-Object { $_ -notmatch "^(Windows PowerShell transcript|Start time:|Username:|RunAs User:|Configuration|Host Application:|Process ID:|PS[A-Z]|BuildVersion:|CLRVersion:|WSManStackVersion:|SerializationVersion:|Transcript started|PS C:\\|^\*{10,}|End time:)" -and $_.Trim() }
    Add-Content $logFilePath -Value ("`n" + "="*50 + "`nTerminal Snapshot - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" + "`n" + "="*50 + "`n" + ($content -join "`n"))
    Remove-Item $transcript  -Force 2>&1 | Write-Log
}

# Set Ownership Permissions
function Set-Ownership {
    param([string]$Path, [string[]]$Registry) 
    if ($Path) {
        try {
            $FullPath = [System.IO.Path]::GetFullPath($Path)
            if (-not (Test-Path -Path $FullPath)) { return $true }
            $IsFolder = (Get-Item $FullPath).PSIsContainer
            $Acl = Get-Acl $FullPath
            $Acl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
            $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUser, "FullControl", $(if ($IsFolder) {"ContainerInherit,ObjectInherit"} else {"None"}), "None", "Allow")
            $Acl.SetAccessRule($AccessRule)
            Set-Acl -Path $FullPath -AclObject $Acl
            if ($IsFolder) { Get-ChildItem -Path $FullPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { 
                try { $ChildAcl = Get-Acl $_.FullName
                    $ChildAcl.SetOwner([System.Security.Principal.NTAccount]"Administrators")
                    $ChildAcl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($CurrentUser, "FullControl", "Allow")))
                    Set-Acl -Path $_.FullName -AclObject $ChildAcl }
                catch {}
            }}
            Write-Log -msg "Set ownership for: $FullPath"
            return $true
        } catch { Write-Log -msg "Failed to own path: $Path - $($_.Exception.Message)"; return $false }
    }
    if ($Registry) {
        try {
            $sid = (New-Object System.Security.Principal.NTAccount("BUILTIN\Administrators")).Translate([System.Security.Principal.SecurityIdentifier])
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule("Administrators", "FullControl", "ContainerInherit", "None", "Allow")
            foreach ($keyPath in $Registry) {
                try {
                    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
                    if ($key) { $acl = $key.GetAccessControl()
                        $acl.SetOwner($sid)
                        $key.SetAccessControl($acl)
                        $key.Close()
                        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($keyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
                        if ($key) { $acl = $key.GetAccessControl()
                            $acl.SetAccessRule($rule)
                            $key.SetAccessControl($acl)
                            $key.Close()
                            Write-Log -msg "Set ownership for registry: $keyPath"
                        }
                    } else { Write-Log -msg "Unable to open reg-key: $keyPath" }
                } catch {}
            }
            return $true
        } catch { Write-Log -msg "Failed to own reg-key: $($_.Exception.Message)"; return $false }
    }
    return $false
}

# Force Remove Function
function Set-OwnAndRemove {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        $FullPath = [System.IO.Path]::GetFullPath($Path)
        if (-not (Test-Path -Path $FullPath)) { return $true }
        try {
            $ownershipResult = Set-Ownership -Path $Path
            if (-not $ownershipResult) { throw "ACL method failed" }
            Remove-Item -Path $FullPath -Force -Recurse -ErrorAction Stop
            Write-Log -msg "Removed with ACL: $FullPath"
            return $true
        } catch {
            Write-Log -msg "ACL method failed for: $FullPath"
            try {
                $IsFolder = (Get-Item $FullPath -ErrorAction Stop).PSIsContainer
                $CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                if($IsFolder) { takeown /F "$FullPath" /R /D Y 2>&1 | Write-Log }
                else { takeown /F "$FullPath" /A 2>&1 | Write-Log }
                foreach ($Perm in @("*S-1-5-32-544:F", "System:F", "Administrators:F", "$CurrentUser`:F")) {
                    try {
                        if($IsFolder) { icacls "$FullPath" /grant:R "$Perm" /T /C 2>&1 | Write-Log }
                        else { icacls "$FullPath" /grant:R "$Perm" 2>&1 | Write-Log }
                        if ($LASTEXITCODE -eq 0) { break }
                    } catch { continue }
                }
                Remove-Item -Path $FullPath -Force -Recurse -ErrorAction Stop
                Write-Log -msg "Removed with icacls: $FullPath"
                return $true
            } catch { Write-Log -msg "Failed to remove: $FullPath - $($_.Exception.Message)"; return $false }
        }
    } catch { Write-Log -msg "Error processing path: $Path - $($_.Exception.Message)"; return $false }
}

# Image Info Function
function Get-WimDetails {
    param ( [Parameter(Mandatory = $true)][string]$MountPath )
    try {
        $out = dism /Image:$MountPath /Get-Intl /English | Out-String
        Write-Log -msg "DISM Output for Get-WimDetails:`n$out"
        $buildMatch = [regex]::Match($out, "Image Version: \d+\.\d+\.(\d+)\.\d+")
        $langMatch = [regex]::Match($out, "(?i)Default\s+system\s+UI\s+language\s*:\s*([a-z]{2}-[A-Z]{2})")
        [PSCustomObject]@{
            BuildNumber = if ($buildMatch.Success) { $buildMatch.Groups[1].Value } else { $null }
            Language = if ($langMatch.Success) { $langMatch.Groups[1].Value } else { $null }
        }
    }
    catch {
        Write-Host "Failed to get WIM info: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Get Image Index Function
function Get-ImageIndex {
    param ( [Parameter(Mandatory = $true)][string]$ImagePath )
    try {
        $out = & dism.exe /get-wiminfo /wimfile:$ImagePath /english 2>$null
        Write-Log -msg "DISM Output for Get-ImageIndex:`n$out"
        if ($LASTEXITCODE -ne 0) { throw "DISM failed to read image file: $ImagePath" }
        $images = @()
        $indexPattern = "Index\s*:\s*(\d+)"
        $namePattern = "Name\s*:\s*(.+)"
        for ($i = 0; $i -lt $out.Count; $i++) {
            if ($out[$i] -match $indexPattern) {
                $index = $matches[1]
                for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $out.Count); $j++) {
                    if ($out[$j] -match $namePattern) {
                        $name = $matches[1].Trim()
                        $images += [PSCustomObject]@{
                            Index = [int]$index
                            ImageName = $name
                        }
                        break
                    }
                }
            }
        }
        return $images
    }
    catch {
        Write-Log -msg "Failed to get image information: $($_.Exception.Message)"
        return $null
    }
}

# Auto-detect Windows Edition from ImageName
function Get-AutoDetectedEdition {
    param (
        [Parameter(Mandatory = $true)][array]$ImageList,
        [Parameter(Mandatory = $false)][string]$PreferredEdition = ""
    )
    
    if ($ImageList.Count -eq 0) {
        Write-Log -msg "No images found for auto-detection"
        return $null
    }
    
    # Priority order: Pro > Enterprise > Home > LTSC
    $priorityOrder = @("Pro", "Enterprise", "Home", "LTSC")
    
    # If preferred edition is specified, try to find it first
    if ($PreferredEdition -and $PreferredEdition -ne "auto") {
        $preferredMatch = $ImageList | Where-Object { 
            $_.ImageName -match $PreferredEdition -or 
            $_.ImageName -like "*$PreferredEdition*" 
        } | Select-Object -First 1
        
        if ($preferredMatch) {
            Write-Log -msg "Found preferred edition: $($preferredMatch.ImageName)"
            return $preferredMatch
        }
    }
    
    # Try to find editions in priority order
    foreach ($edition in $priorityOrder) {
        $match = $ImageList | Where-Object { 
            $_.ImageName -match $edition -or 
            $_.ImageName -like "*$edition*" 
        } | Select-Object -First 1
        
        if ($match) {
            Write-Log -msg "Auto-detected edition: $($match.ImageName)"
            return $match
        }
    }
    
    # If no match found, return the first image
    Write-Log -msg "No specific edition found, using first image: $($ImageList[0].ImageName)"
    return $ImageList[0]
}

# Extract edition name from ImageName for better matching
function Get-EditionFromImageName {
    param ( [Parameter(Mandatory = $true)][string]$ImageName )
    
    $ImageNameLower = $ImageName.ToLower()
    
    # Check for LTSC first (most specific)
    if ($ImageNameLower -match "ltsc|long term servicing channel") {
        return "LTSC"
    }
    # Check for Enterprise
    elseif ($ImageNameLower -match "enterprise") {
        return "Enterprise"
    }
    # Check for Pro
    elseif ($ImageNameLower -match "pro|professional") {
        return "Pro"
    }
    # Check for Home
    elseif ($ImageNameLower -match "home") {
        return "Home"
    }
    
    # Return original if no match
    return $ImageName
}

# Oscdimg Path
$OscdimgPath = "$env:SystemDrive\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
$Oscdimg = Join-Path -Path $OscdimgPath -ChildPath 'oscdimg.exe'

# Autounattend.xml Path
$autounattendXmlPath = Join-Path -Path $scriptDirectory -ChildPath "Autounattend.xml"

# Download Autounattend.xml if not exists
if (-not (Test-Path $autounattendXmlPath)) {
    $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest "https://itsnileshhere.github.io/Windows-ISO-Debloater/autounattend.xml" -OutFile $autounattendXmlPath -UseBasicParsing }
    catch { Write-Log -msg "Warning: Unable to download Autounattend.xml" }
    finally { $ProgressPreference = 'Continue' }
}

# Mount ISO Dialog
function Select-ISOFile {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    $dialog.Filter = "ISO files (*.iso)|*.iso"
    $dialog.Title = "Select Windows ISO File"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    } else {
        return $null
    }
}

if ($isoPath) {$isoFilePath = $isoPath}     # If ISO path is provided as parameter
else {$isoFilePath = Select-ISOFile}        # Prompt user to select ISO file
if ($null -eq $isoFilePath) {
    Write-Host "No file selected. Exiting Script" -ForegroundColor Red
    Write-Log -msg "No file selected"
    Pause
    Exit
}

Write-Host "`nSelected ISO file: " -NoNewline -ForegroundColor Cyan; Write-Host "$isoFilePath"
Write-Log -msg "ISO Path: $isoFilePath"

# Mounting ISO File
Write-Host "`n[INFO] Mounting ISO file..." -ForegroundColor Cyan
[Console]::Out.Flush()
$mountResult = Mount-DiskImage -ImagePath "$isoFilePath" -PassThru
if ($mountResult) {
    $sourceDriveLetter = ($mountResult | Get-Volume).DriveLetter
    if ($sourceDriveLetter) {
        Write-Host "[OK] ISO mounted to drive: $sourceDriveLetter`:" -ForegroundColor Green
        [Console]::Out.Flush()
        Write-Log -msg "Mounted ISO file to drive: $sourceDriveLetter`:"
    }
}
else {
    Write-Host "[FAILED] Failed to mount the ISO file." -ForegroundColor Red
    [Console]::Out.Flush()
    Write-Log -msg "Failed to mount the ISO file."
    Pause
    Exit
}

$sourceDrive = "${sourceDriveLetter}:\"                             # Source Drive of ISO
$destinationPath = "$env:SystemDrive\WIDTemp\winlite"               # Destination Path
$installMountDir = "$env:SystemDrive\WIDTemp\mountdir\installWIM"   # Mount Directory

# Copy Files
Write-Host "`n[INFO] Copying files from ISO..." -ForegroundColor Cyan
Write-Host "  Source: $sourceDrive" -ForegroundColor Yellow
Write-Host "  Destination: $destinationPath" -ForegroundColor Yellow
[Console]::Out.Flush()
Write-Log -msg "Copying files from $sourceDrive to $destinationPath"
try {
    if (-not (Test-Path $destinationPath)) { 
        Write-Host "  → Creating destination directory..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        New-Item -ItemType Directory -Path $destinationPath -Force -EA Stop | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    Write-Log -msg "Starting file copy operation..."
    Write-Host "  → Copying files (this may take a while)..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    
    # Using Robocopy to copy files
    $robocopyOutput = & robocopy.exe $sourceDrive $destinationPath /E /COPY:DAT /R:3 /W:5 /MT:8 /NFL /NDL /NP 2>&1
    $robocopyExitCode = $LASTEXITCODE
    $robocopyOutput | Write-Log
    if ($robocopyExitCode -le 7) { 
        Write-Host "  → Copy completed successfully [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
        Write-Log -msg "Copy completed (Exit: $robocopyExitCode)"
        Write-Host "  → Removing read-only attributes..." -ForegroundColor Yellow -NoNewline
        [Console]::Out.Flush()
        Write-Log -msg "Removing read-only attributes..."
        Get-ChildItem -Path $destinationPath -Recurse | ForEach-Object { $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) } | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    else { throw "Robocopy failed: $robocopyExitCode" }
} catch { 
    Write-Host " [FAILED]" -ForegroundColor Red
    [Console]::Out.Flush()
    Write-Log -msg "Copy failed: $($_.Exception.Message)"; throw 
}

Write-Host "  → Unmounting ISO..." -ForegroundColor Yellow -NoNewline
[Console]::Out.Flush()
try { 
    if (Test-Path $isoFilePath) { 
        Dismount-DiskImage -ImagePath $isoFilePath -EA Stop | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
}
catch { 
    Write-Host " [WARNING]" -ForegroundColor Yellow
    [Console]::Out.Flush()
    Write-Log -msg "Dismount failed: $($_.Exception.Message)" 
}

# Check files availability
$installWimPath = Join-Path $destinationPath "sources\install.wim"
$installEsdPath = Join-Path $destinationPath "sources\install.esd"
New-Item -ItemType Directory -Path $installMountDir 2>&1 | Write-Log

# Handling install.wim and install.esd
if (-not (Test-Path $installWimPath)) {
    Write-Host "`n[INFO] install.wim not found. Searching for install.esd..." -ForegroundColor Cyan
    [Console]::Out.Flush()
    if (Test-Path $installEsdPath) {
        Write-Host "[OK] install.esd found at $installEsdPath" -ForegroundColor Green
        [Console]::Out.Flush()
        Write-Log -msg "install.esd found. Converting..."
        Write-Host "`n[INFO] Getting image details from install.esd..." -ForegroundColor Cyan
        [Console]::Out.Flush()
        try {
            # Get image info from install.esd
            $esdInfo = Get-ImageIndex -ImagePath $installEsdPath
            if (-not $esdInfo) { 
                Write-Host "Error: Could not retrieve image info from WIM file" -ForegroundColor Red
                Remove-TempFiles
                Pause
                Exit
            }
            # Print image details from install.esd
            foreach ($image in $esdInfo) {
                Write-Host "$($image.Index). $($image.ImageName)"
            }
            # Handle auto-detection or manual selection
            if ($winEdition -ieq "auto") {
                Write-Host "`nAuto-detecting Windows Edition..." -ForegroundColor Cyan
                $detectedImage = Get-AutoDetectedEdition -ImageList $esdInfo
                if ($detectedImage) {
                    $sourceIndex = $detectedImage.Index
                    $winEdition = Get-EditionFromImageName -ImageName $detectedImage.ImageName
                    Write-Host "Auto-detected: $($detectedImage.ImageName) -> Using Edition: $winEdition" -ForegroundColor Green
                    Write-Log -msg "Auto-detected edition: $winEdition from image: $($detectedImage.ImageName)"
                } else {
                    $sourceIndex = 1
                    Write-Host "Auto-detection failed, using first image (Index 1)" -ForegroundColor Yellow
                    Write-Log -msg "Auto-detection failed, using index 1"
                }
            }
            elseif ($winEdition) {
                # Try exact match first
                $matchedImage = $esdInfo | Where-Object { $_.ImageName -ieq $winEdition }
                if (-not $matchedImage) {
                    # Try partial match
                    $matchedImage = $esdInfo | Where-Object { 
                        $_.ImageName -match $winEdition -or 
                        $_.ImageName -like "*$winEdition*" 
                    } | Select-Object -First 1
                }
                if ($matchedImage) { 
                    $sourceIndex = $matchedImage.Index
                    Write-Host "Matched edition: $($matchedImage.ImageName)" -ForegroundColor Green
                    Write-Log -msg "Matched edition: $($matchedImage.ImageName)"
                }
                else { 
                    $sourceIndex = 1
                    Write-Host "Edition '$winEdition' not found, using first image (Index 1)" -ForegroundColor Yellow
                    Write-Log -msg "Edition '$winEdition' not found, using index 1"
                }
            }
            else { 
                $sourceIndex = Read-Host -Prompt "`nEnter the index to convert and mount" 
            }
            # Check if the index is valid, print selected "ImageIndex - ImageName"
            $selectedImage = $esdInfo | Where-Object { $_.Index -eq [int]$sourceIndex }
            if ($selectedImage) {
                Write-Host "`n[INFO] Converting and mounting image..." -ForegroundColor Cyan
                Write-Host "  Image: $sourceIndex. $($selectedImage.ImageName)" -ForegroundColor Yellow
                [Console]::Out.Flush()
                Write-Log -msg "Converting and Mounting image: $sourceIndex. $($selectedImage.ImageName)"
            }

            # Convert ESD to WIM
            Write-Host "  → Converting ESD to WIM (this may take a while)..." -ForegroundColor Yellow
            [Console]::Out.Flush()
            Invoke-DismFailsafe {
                Export-WindowsImage -SourceImagePath $installEsdPath -SourceIndex $sourceIndex -DestinationImagePath $installWimPath -CompressionType Maximum -CheckIntegrity
            } {
                dism /Export-Image /SourceImageFile:$installEsdPath /SourceIndex:$sourceIndex /DestinationImageFile:$installWimPath /Compress:max /CheckIntegrity
            }
            Write-Host "  → ESD conversion completed [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
            
            # Remove the ESD file after conversion
            Write-Host "  → Removing ESD file..." -ForegroundColor Yellow -NoNewline
            [Console]::Out.Flush()
            Remove-Item $installEsdPath -Force
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
            
            # Mount the converted WIM with SourceIndex 1
            Write-Host "  → Mounting converted WIM image..." -ForegroundColor Yellow
            [Console]::Out.Flush()
            Invoke-DismFailsafe {
                Mount-WindowsImage -ImagePath $installWimPath -Index 1 -Path $installMountDir
            } {
                dism /mount-image /imagefile:$installWimPath /index:1 /mountdir:$installMountDir
            }
            Write-Host "  → Image mounted successfully [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
            $sourceIndex = 1  # After conversion, the new WIM will have only one image
        }
        catch {
            Write-Host "Failed to convert or mount the ESD image: $_" -ForegroundColor Red
            Write-Log -msg "Failed to mount image: $_"
            Pause
            Exit
        }
    }
    else {
        Write-Host "Neither install.wim nor install.esd found. Make sure to mount the correct ISO" -ForegroundColor Red
        Write-Log -msg "Neither install.wim nor install.esd found"
        Pause
        Exit
    }
}
else {
    Write-Host "`nDetails for image: " -NoNewline -ForegroundColor Cyan; Write-Host "$installWimPath"
    Write-Log -msg "Getting image info"
    try {
        # Get image info from install.wim
        $wimInfo = Get-ImageIndex -ImagePath $installWimPath
        if (-not $wimInfo) { 
            Write-Host "Error: Could not retrieve image info from WIM file" -ForegroundColor Red
            Remove-TempFiles
            Pause
            Exit
        }
        # Print image details from install.wim
        foreach ($image in $wimInfo) {
            Write-Host "$($image.Index). $($image.ImageName)"
        }
        # Handle auto-detection or manual selection
        if ($winEdition -ieq "auto") {
            Write-Host "`nAuto-detecting Windows Edition..." -ForegroundColor Cyan
            $detectedImage = Get-AutoDetectedEdition -ImageList $wimInfo
            if ($detectedImage) {
                $sourceIndex = $detectedImage.Index
                $winEdition = Get-EditionFromImageName -ImageName $detectedImage.ImageName
                Write-Host "Auto-detected: $($detectedImage.ImageName) -> Using Edition: $winEdition" -ForegroundColor Green
                Write-Log -msg "Auto-detected edition: $winEdition from image: $($detectedImage.ImageName)"
            } else {
                $sourceIndex = 1
                Write-Host "Auto-detection failed, using first image (Index 1)" -ForegroundColor Yellow
                Write-Log -msg "Auto-detection failed, using index 1"
            }
        }
        elseif ($winEdition) {
            # Try exact match first
            $matchedImage = $wimInfo | Where-Object { $_.ImageName -ieq $winEdition }
            if (-not $matchedImage) {
                # Try partial match
                $matchedImage = $wimInfo | Where-Object { 
                    $_.ImageName -match $winEdition -or 
                    $_.ImageName -like "*$winEdition*" 
                } | Select-Object -First 1
            }
            if ($matchedImage) { 
                $sourceIndex = $matchedImage.Index
                Write-Host "Matched edition: $($matchedImage.ImageName)" -ForegroundColor Green
                Write-Log -msg "Matched edition: $($matchedImage.ImageName)"
            }
            else { 
                $sourceIndex = 1
                Write-Host "Edition '$winEdition' not found, using first image (Index 1)" -ForegroundColor Yellow
                Write-Log -msg "Edition '$winEdition' not found, using index 1"
            }
        }
        else { 
            $sourceIndex = Read-Host -Prompt "`nEnter the index to mount" 
        }
        # Check if the index is valid, print selected "ImageIndex - ImageName"
        $selectedImage = $wimInfo | Where-Object { $_.Index -eq [int]$sourceIndex }
        if ($selectedImage) {
            Write-Host "`n[INFO] Mounting Windows image..." -ForegroundColor Cyan
            Write-Host "  Image: $sourceIndex. $($selectedImage.ImageName)" -ForegroundColor Yellow
            [Console]::Out.Flush()
            Write-Log -msg "Mounting image: $sourceIndex. $($selectedImage.ImageName)"
        }

        Write-Host "  → Mounting image (this may take a while)..." -ForegroundColor Yellow
        [Console]::Out.Flush()
        Invoke-DismFailsafe {
            Mount-WindowsImage -ImagePath $installWimPath -Index $sourceIndex -Path $installMountDir
        } {
            dism /mount-image /imagefile:$installWimPath /index:$sourceIndex /mountdir:$installMountDir
        }
        Write-Host "  → Image mounted successfully [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    catch {
        Write-Host "Failed to mount the image: $_" -ForegroundColor Red
        Write-Log -msg "Failed to mount image: $_"
        Pause
        Exit
    }
}

# Check if wim-mount was successful
if (-not (Test-Path "$installMountDir\Windows")) {
    Write-Host "[FAILED] Error while mounting image. Try again." -ForegroundColor Red
    [Console]::Out.Flush()
    Write-Log -msg "Mounted image not found. Exiting"
    Remove-TempFiles
    Pause
    Exit 
}

Write-Host "[OK] Image mounted successfully" -ForegroundColor Green
[Console]::Out.Flush()

# Resolve Image Info
Write-Host "`n[INFO] Analyzing mounted image..." -ForegroundColor Cyan
[Console]::Out.Flush()
$WimDetails = Get-WimDetails -MountPath $installMountDir
if (-not $WimDetails -or -not $WimDetails.BuildNumber -or -not $WimDetails.Language) {
    Write-Host "[FAILED] Error: Could not retrieve WIM information from mounted path" -ForegroundColor Red
    [Console]::Out.Flush()
    Remove-TempFiles
    Pause
    Exit
}
$langCode = $WimDetails.Language; Write-Log -msg "Detected Language: $langCode"
$buildNumber = $WimDetails.BuildNumber; Write-Log -msg "Detected Build Number: $buildNumber"
Write-Host "  → Language: $langCode" -ForegroundColor Yellow
Write-Host "  → Build Number: $buildNumber" -ForegroundColor Yellow
[Console]::Out.Flush()

Write-Host
$DoAppxRemove = Get-ParameterValue -ParameterValue $AppxRemove -DefaultValue $true -Question "Remove unnecessary packages?" -Description "Recommended: Removes bloatware apps"
$DoCapabilitiesRemove = Get-ParameterValue -ParameterValue $CapabilitiesRemove -DefaultValue $true -Question "Remove unnecessary features?" -Description "Recommended: Removes optional Windows features"
$DoOnedriveRemove = Get-ParameterValue -ParameterValue $OnedriveRemove -DefaultValue $true -Question "Remove OneDrive?" -Description "Optional: Completely removes OneDrive"
$DoEDGERemove = Get-ParameterValue -ParameterValue $EDGERemove -DefaultValue $true -Question "Remove Microsoft Edge?" -Description "Optional: Removes Edge browser"
$DoAIRemove = Get-ParameterValue -ParameterValue $AIRemove -DefaultValue $true -Question "Remove AI Components?" -Description "Optional: Removes everything related to AI"
$DoDefenderRemove = Get-ParameterValue -ParameterValue $DefenderRemove -DefaultValue $false -Question "Remove Windows Defender?" -Description "Optional: Removes Windows Defender Antivirus (Compatible with LTSC)"
$DoTPMBypass = Get-ParameterValue -ParameterValue $TPMBypass -DefaultValue $false -Question "Bypass TPM check?" -Description "Only if needed for older hardware"
$DoUserFoldersEnable = Get-ParameterValue -ParameterValue $UserFoldersEnable -DefaultValue $true -Question "Enable user folders?" -Description "Recommended: Enables Desktop, Documents, etc."
$DoESDConvert = Get-ParameterValue -ParameterValue $ESDConvert -DefaultValue $false -Question "Compress the ISO?" -Description "Recommended but slow: Reduces ISO file size"
$DoUseOscdimg = Get-ParameterValue -ParameterValue $useOscdimg -DefaultValue $true -Question "Use Oscdimg for ISO creation?" -Description "Recommended: Oscdimg is more reliable"

# Comment out the package don't wanna remove
$appxPatternsToRemove = @(
    "Microsoft.Microsoft3DViewer*",             # 3DViewer
    "Microsoft.WindowsAlarms*",                 # Alarms
    "Microsoft.BingNews*",                      # Bing News
    "Microsoft.BingWeather*",                   # Bing Weather
    "Clipchamp.Clipchamp*",                     # Clipchamp
    "Microsoft.549981C3F5F10*",                 # Cortana
    "Microsoft.Windows.DevHome*",               # DevHome
    "MicrosoftCorporationII.MicrosoftFamily*",  # Family
    "Microsoft.WindowsFeedbackHub*",            # FeedbackHub
    "Microsoft.GetHelp*",                       # GetHelp
    "Microsoft.Getstarted*",                    # GetStarted
    "Microsoft.WindowsCommunicationsapps*",     # Mail
    "Microsoft.WindowsMaps*",                   # Maps
    "Microsoft.MixedReality.Portal*",           # MixedReality
    "Microsoft.ZuneMusic*",                     # Music
    "Microsoft.MicrosoftOfficeHub*",            # OfficeHub
    "Microsoft.Office.OneNote*",                # OneNote
    "Microsoft.OutlookForWindows*",             # Outlook
    "Microsoft.MSPaint*",                       # Paint3D(Windows10)
    "Microsoft.People*",                        # People
    "Microsoft.YourPhone*",                     # Phone
    "Microsoft.PowerAutomateDesktop*",          # PowerAutomate
    "MicrosoftCorporationII.QuickAssist*",      # QuickAssist
    "Microsoft.SkypeApp*",                      # Skype
    "Microsoft.MicrosoftSolitaireCollection*",  # SolitaireCollection
    # "Microsoft.WindowsSoundRecorder*",          # SoundRecorder
    "MicrosoftTeams*",                          # Teams_old
    "MSTeams*",                                 # Teams
    "Microsoft.Windows.Teams*",                 # Teams
    "Microsoft.Todos*",                         # Todos
    "Microsoft.ZuneVideo*",                     # Video
    "Microsoft.Wallet*",                        # Wallet
    "Microsoft.GamingApp*",                     # Xbox
    "Microsoft.XboxApp*",                       # Xbox(Win10)
    "Microsoft.XboxGameOverlay*",               # XboxGameOverlay
    "Microsoft.XboxGamingOverlay*",             # XboxGamingOverlay
    "Microsoft.XboxSpeechToTextOverlay*",       # XboxSpeechToTextOverlay
    "Microsoft.Xbox.TCUI*",                     # XboxTCUI
    # "Microsoft.SecHealthUI*",                   # Windows Security
    "MicrosoftWindows.CrossDevice*",            # CrossDevice
    "Microsoft.Windows.PeopleExperienceHost*",  # PeopleExperienceHost
    "Windows.CBSPreview*",                      # CBS Preview
    "Microsoft.BingSearch*",                    # Bing Search
    "Microsoft.WindowsStore*",                 # Microsoft Store
    "Microsoft.WindowsCamera*",                 # Camera
    "Microsoft.WindowsSoundRecorder*",          # Sound Recorder
    "Microsoft.WindowsTerminal*",               # Windows Terminal
    "Microsoft.WindowsTerminalPreview*",       # Windows Terminal Preview
    "Microsoft.Windows.Photos*",                # Photos
    "Microsoft.ScreenSketch*",                  # Snip & Sketch
    "Microsoft.ScreenSketchMain*",              # Snip & Sketch (alternative)
    "Microsoft.WindowsRemoteDesktop*",          # Remote Desktop
    "Microsoft.DesktopAppInstaller*",           # App Installer
    "Microsoft.WindowsWebExperiencePack*",      # Web Experience Pack
    "Microsoft.MicrosoftEdgeUpdate*",            # Edge Update
    "Microsoft.Services.Store.Engagement*",      # Store Engagement
    "Microsoft.StorePurchaseApp*",               # Store Purchase App
    "Microsoft.WindowsStorePurchaseApp*",        # Windows Store Purchase App
    "Microsoft.BingTranslator*",                # Bing Translator
    "Microsoft.Windows.PrintQueue*",            # Print Queue
    "Microsoft.Windows.InkWorkSpace*",          # Ink Workspace
    "Microsoft.Windows.ParentalControls*",      # Parental Controls
    "Microsoft.Windows.ReadingList*",           # Reading List
    "Microsoft.Windows.SecureAssessmentBrowser*", # Secure Assessment Browser
    "Microsoft.Windows.Search.Cortana*",        # Cortana Search
    "Microsoft.Windows.TouchKeyboard*",         # Touch Keyboard
    "Microsoft.Windows.WifiSense*",             # WiFi Sense
    "Microsoft.Windows.AssignedAccessLockApp*", # Assigned Access Lock App
    "Microsoft.Windows.XboxGameCallableUI*",    # Xbox Game Callable UI
    "Microsoft.XboxIdentityProvider*",           # Xbox Identity Provider
    "Microsoft.XboxGameSpeechWindow*"           # Xbox Game Speech Window

$capabilitiesToRemove = @(
    "Browser.InternetExplorer*",
    "Internet-Explorer*",
    "App.StepsRecorder*",
    "Language.Handwriting~~~$langCode*",
    "Language.OCR~~~$langCode*",
    "Language.Speech~~~$langCode*",
    "Language.TextToSpeech~~~$langCode*",
    "Microsoft.Windows.WordPad*",
    "MathRecognizer*",
    "Media.WindowsMediaPlayer*",
    "Microsoft.Windows.PowerShell.ISE*"
)

$windowsPackagesToRemove = @(
    "Microsoft-Windows-InternetExplorer-Optional-Package*",
    "Microsoft-Windows-LanguageFeatures-Handwriting-$langCode-Package*",
    "Microsoft-Windows-LanguageFeatures-OCR-$langCode-Package*",
    "Microsoft-Windows-LanguageFeatures-Speech-$langCode-Package*",
    "Microsoft-Windows-LanguageFeatures-TextToSpeech-$langCode-Package*",
    "Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package*",
    "Microsoft-Windows-WordPad-FoD-Package*",
    "Microsoft-Windows-MediaPlayer-Package*",
    "Microsoft-Windows-TabletPCMath-Package*",
    "Microsoft-Windows-StepsRecorder-Package*"
)

function Remove-Packages {
    param( [string[]]$Patterns, [string]$SectionTitle, [string]$PackageType, [string]$MountPath, [int]$StartIndex = 1, [int]$TotalCount, [int]$StatusColumn )
    
    # Package configurations
    $config = @{
        'AppX' = @{
            GetCommand = { Get-ProvisionedAppxPackage -Path $MountPath }
            FilterProperty = 'PackageName'
            RemoveCommand = { param($item) Remove-ProvisionedAppxPackage -Path $MountPath -PackageName $item.PackageName }
            LogPrefix = 'AppX package'
        }
        'Capability' = @{
            GetCommand = { Get-WindowsCapability -Path $MountPath }
            FilterProperty = 'Name'
            RemoveCommand = { param($item) Remove-WindowsCapability -Path $MountPath -Name $item.Name }
            LogPrefix = 'capability'
        }
        'WindowsPackage' = @{
            GetCommand = { Get-WindowsPackage -Path $MountPath }
            FilterProperty = 'PackageName'
            RemoveCommand = { param($item) Remove-WindowsPackage -Path $MountPath -PackageName $item.PackageName }
            LogPrefix = 'Windows package'
        }
    }
    if ($SectionTitle) { Write-Host "`n$SectionTitle" -ForegroundColor Cyan; Write-Log -msg $SectionTitle }
    
    # Validate Package Type
    $cfg = $config[$PackageType]
    $filterProp = $cfg.FilterProperty
    
    for ($i = 0; $i -lt $Patterns.Count; $i++) {
        $pattern = $Patterns[$i]
        $displayName = $pattern.TrimEnd('*')
        $counter = "[{0}/{1}]" -f ($StartIndex + $i), $TotalCount

        # Display real-time progress: "Removing [package]..."
        Write-Host "`n$counter Removing $displayName..." -ForegroundColor Yellow -NoNewline
        [Console]::Out.Flush()  # Force immediate output
        
        try {
            $items = & $cfg.GetCommand | Where-Object { $_.$filterProp -like $pattern }
            $itemsRemoved = 0
            
            if ($items.Count -gt 0) {
                foreach ($item in $items) {
                    $itemName = $item.$filterProp
                    Write-Host "`n    → Removing $itemName..." -ForegroundColor Cyan -NoNewline
                    [Console]::Out.Flush()  # Force immediate output
                    
                    try {
                        & $cfg.RemoveCommand $item 2>&1 | Write-Log
                        $itemsRemoved++
                        Write-Host " [OK]" -ForegroundColor Green
                        [Console]::Out.Flush()
                    }
                    catch {
                        Write-Host " [FAILED]" -ForegroundColor Red
                        [Console]::Out.Flush()
                        $itemName = $item.$filterProp
                        Write-Log -msg "Removing $($cfg.LogPrefix) $itemName failed: $_"
                    }
                }
                Write-Host "$counter $displayName - Removed $itemsRemoved item(s)" -ForegroundColor Green
            } else {
                Write-Host " [NOT FOUND]" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host " [ERROR]" -ForegroundColor Red
            Write-Log -msg "Failed to remove $PackageType matching '$pattern': $_"
        }
    }
}

$allPatterns = $appxPatternsToRemove + $capabilitiesToRemove + $windowsPackagesToRemove
$maxLength = ($allPatterns | ForEach-Object { $_.TrimEnd('*').Length } | Measure-Object -Maximum).Maximum
$statusColumn = $maxLength + 18

if ($DoAppxRemove) {
    # Remove AppX Packages
    Remove-Packages -Patterns $appxPatternsToRemove -SectionTitle "Removing provisioned Packages:" -PackageType "AppX" -MountPath $installMountDir -TotalCount $appxPatternsToRemove.Count -StatusColumn $statusColumn
} else {
    Write-Log -msg "Skipped Package Removal"
}

if ($DoCapabilitiesRemove) {
    # Remove Capabilities and Windows Packages
    $capabilitiesAndPackagesTotal = $capabilitiesToRemove.Count + $windowsPackagesToRemove.Count
    Remove-Packages -Patterns $capabilitiesToRemove -SectionTitle "Removing Unnecessary Windows Features:" -PackageType "Capability" -MountPath $installMountDir -TotalCount $capabilitiesAndPackagesTotal -StatusColumn $statusColumn
    Remove-Packages -Patterns $windowsPackagesToRemove -SectionTitle "" -PackageType "WindowsPackage" -MountPath $installMountDir -StartIndex ($capabilitiesToRemove.Count + 1) -TotalCount $capabilitiesAndPackagesTotal -StatusColumn $statusColumn
} else {
    Write-Log -msg "Skipped Features Removal"
}

# # Remove Recall (Have conflict with Explorer)
# Write-Host "`nRemoving Recall..."
# Write-Log -msg "Removing Recall"
# dism /image:$installMountDir /Disable-Feature /FeatureName:'Recall' /Remove 2>&1 | Write-Log
# Write-Host "Done"

# # Remove OutlookPWA
# Write-Host "`nRemoving Outlook..." -ForegroundColor Cyan
# Write-Log -msg "Removing OutlookPWA"
# Get-ChildItem "$installMountDir\Windows\WinSxS\amd64_microsoft-windows-outlookpwa*" -Directory | ForEach-Object { Set-OwnAndRemove -Path $_.FullName } 2>&1 | Write-Log
# Write-Host "Done" -ForegroundColor Green

# Setting Permissions
function Enable-Privilege {
    param([ValidateSet('SeAssignPrimaryTokenPrivilege', 'SeAuditPrivilege', 'SeBackupPrivilege', 'SeChangeNotifyPrivilege', 'SeCreateGlobalPrivilege', 'SeCreatePagefilePrivilege', 'SeCreatePermanentPrivilege', 'SeCreateSymbolicLinkPrivilege', 'SeCreateTokenPrivilege', 'SeDebugPrivilege', 'SeEnableDelegationPrivilege', 'SeImpersonatePrivilege', 'SeIncreaseBasePriorityPrivilege', 'SeIncreaseQuotaPrivilege', 'SeIncreaseWorkingSetPrivilege', 'SeLoadDriverPrivilege', 'SeLockMemoryPrivilege', 'SeMachineAccountPrivilege', 'SeManageVolumePrivilege', 'SeProfileSingleProcessPrivilege', 'SeRelabelPrivilege', 'SeRemoteShutdownPrivilege', 'SeRestorePrivilege', 'SeSecurityPrivilege', 'SeShutdownPrivilege', 'SeSyncAgentPrivilege', 'SeSystemEnvironmentPrivilege', 'SeSystemProfilePrivilege', 'SeSystemtimePrivilege', 'SeTakeOwnershipPrivilege', 'SeTcbPrivilege', 'SeTimeZonePrivilege', 'SeTrustedCredManAccessPrivilege', 'SeUndockPrivilege', 'SeUnsolicitedInputPrivilege')]$Privilege, $ProcessId = $pid, [Switch]$Disable)
    $def = @'
    using System;using System.Runtime.InteropServices;public class AdjPriv{[DllImport("advapi32.dll",ExactSpelling=true,SetLastError=true)]internal static extern bool AdjustTokenPrivileges(IntPtr htok,bool disall,ref TokPriv1Luid newst,int len,IntPtr prev,IntPtr relen);[DllImport("advapi32.dll",ExactSpelling=true,SetLastError=true)]internal static extern bool OpenProcessToken(IntPtr h,int acc,ref IntPtr phtok);[DllImport("advapi32.dll",SetLastError=true)]internal static extern bool LookupPrivilegeValue(string host,string name,ref long pluid);[StructLayout(LayoutKind.Sequential,Pack=1)]internal struct TokPriv1Luid{public int Count;public long Luid;public int Attr;}public static bool EnablePrivilege(long processHandle,string privilege,bool disable){var tp=new TokPriv1Luid();tp.Count=1;tp.Attr=disable?0:2;IntPtr htok=IntPtr.Zero;if(!OpenProcessToken(new IntPtr(processHandle),0x28,ref htok))return false;if(!LookupPrivilegeValue(null,privilege,ref tp.Luid))return false;return AdjustTokenPrivileges(htok,false,ref tp,0,IntPtr.Zero,IntPtr.Zero);}}
'@
    (Add-Type $def -PassThru -EA SilentlyContinue)[0]::EnablePrivilege((Get-Process -id $ProcessId).Handle, $Privilege, $Disable)
}
Enable-Privilege SeTakeOwnershipPrivilege | Out-Null

if ($DoOnedriveRemove) {
    # Remove OneDrive
    Write-Host ("`n[INFO] Removing OneDrive...") -ForegroundColor Cyan
    Write-Log -msg "Defining OneDrive Setup file paths"
    $oneDriveSetupPath1 = Join-Path -Path $installMountDir -ChildPath 'Windows\System32\OneDriveSetup.exe'
    $oneDriveSetupPath2 = Join-Path -Path $installMountDir -ChildPath 'Windows\SysWOW64\OneDriveSetup.exe'
    # $oneDriveSetupPath3 = (Join-Path -Path $installMountDir -ChildPath 'Windows\WinSxS\*microsoft-windows-onedrive-setup*\OneDriveSetup.exe' | Get-Item -ErrorAction SilentlyContinue).FullName
    # $oneDriveSetupPath4 = (Get-ChildItem "$installMountDir\Windows\WinSxS\amd64_microsoft-windows-onedrive-setup*" -Directory).FullName
    $oneDriveShortcut = Join-Path -Path $installMountDir -ChildPath 'Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'

    Write-Log -msg "Removing OneDrive"
    
    Write-Host "  → Removing OneDriveSetup.exe (System32)..." -ForegroundColor Yellow -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path $oneDriveSetupPath1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    Write-Host "  → Removing OneDriveSetup.exe (SysWOW64)..." -ForegroundColor Yellow -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path $oneDriveSetupPath2 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    Write-Host "  → Removing OneDrive shortcut..." -ForegroundColor Yellow -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path $oneDriveShortcut | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    # $oneDriveSetupPath3 | Where-Object { $_ } | ForEach-Object { Set-OwnAndRemove -Path $_ } 2>&1 | Write-Log
    # $oneDriveSetupPath4 | Where-Object { $_ } | ForEach-Object { Set-OwnAndRemove -Path $_ } 2>&1 | Write-Log

    Write-Host ("[OK] OneDrive Removed") -ForegroundColor Green
    Write-Log -msg "OneDrive removed successfully"
} else {
    Write-Log -msg "OneDrive removal skipped"
}

if ($DoEDGERemove) {
    # Remove EDGE
    Write-Host ("`n[INFO] Removing EDGE...") -ForegroundColor Cyan
    Write-Log -msg "Removing EDGE"
    
    # Edge Patterns
    $EDGEpatterns = @(
        "Microsoft.MicrosoftEdge.Stable*",
        "Microsoft.MicrosoftEdgeDevToolsClient*", 
        "Microsoft.Win32WebViewHost*",
        "MicrosoftWindows.Client.WebExperience*"
    )

    # Remove Edge Packages
    Write-Host "  → Removing Edge packages..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    foreach ($pattern in $EDGEpatterns) {
        $matchedPackages = Get-ProvisionedAppxPackage -Path $installMountDir | 
        Where-Object { $_.PackageName -like $pattern }
        foreach ($package in $matchedPackages) {
            Write-Host "    → Removing $($package.PackageName)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            try {
                Invoke-DismFailsafe {Remove-ProvisionedAppxPackage -Path $installMountDir -PackageName $package.PackageName} {dism /image:$installMountDir /Remove-ProvisionedAppxPackage /PackageName:$($package.PackageName)}
                Write-Host " [OK]" -ForegroundColor Green
                [Console]::Out.Flush()
            } catch {
                Write-Host " [FAILED]" -ForegroundColor Red
                [Console]::Out.Flush()
            }
        }
    }

    # Modifying reg keys
    Write-Host "  → Modifying Edge registry..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    try {
        reg load HKLM\zSOFTWARE "$installMountDir\Windows\System32\config\SOFTWARE" 2>&1 | Write-Log
        reg load HKLM\zSYSTEM "$installMountDir\Windows\System32\config\SYSTEM" 2>&1 | Write-Log
        reg load HKLM\zNTUSER "$installMountDir\Users\Default\ntuser.dat" 2>&1 | Write-Log
        reg load HKLM\zDEFAULT "$installMountDir\Windows\System32\config\default" 2>&1 | Write-Log
          
        # Registry operations - delete operations
        $edgeDeleteRegistry = @(
            "HKLM\zSOFTWARE\Microsoft\EdgeUpdate",
            "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
            "HKLM\zDEFAULT\Software\Microsoft\EdgeUpdate",
            "HKLM\zNTUSER\Software\Microsoft\EdgeUpdate",
            "HKLM\zSOFTWARE\Microsoft\Active Setup\Installed Components\{9459C573-B17A-45AE-9F64-1857B5D58CEE}",
            "HKLM\zSOFTWARE\WOW6432Node\Microsoft\Edge",
            "HKLM\zSOFTWARE\WOW6432Node\Microsoft\EdgeUpdate",
            "HKLM\zSYSTEM\CurrentControlSet\Services\edgeupdate",
            "HKLM\zSYSTEM\ControlSet001\Services\edgeupdate",
            "HKLM\zSYSTEM\CurrentControlSet\Services\edgeupdatem",
            "HKLM\zSYSTEM\ControlSet001\Services\edgeupdatem",
            "HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge",
            "HKLM\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
        )
        
        foreach ($regKey in $edgeDeleteRegistry) {
            Write-Host "    → Removing $regKey..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            reg delete $regKey /f 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
        
        # Registry operations - add operations
        $edgeAddRegistry = @(
            @{Key="HKLM\zSOFTWARE\Microsoft\MicrosoftEdge\Main"; Value="AllowPrelaunch"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\MicrosoftEdge\Main"; Value="AllowPrelaunch"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zNTUSER\Software\Microsoft\MicrosoftEdge\Main"; Value="AllowPrelaunch"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zNTUSER\Software\Policies\Microsoft\MicrosoftEdge\Main"; Value="AllowPrelaunch"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Microsoft\MicrosoftEdge\TabPreloader"; Value="AllowTabPreloading"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader"; Value="AllowTabPreloading"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zNTUSER\Software\Microsoft\MicrosoftEdge\TabPreloader"; Value="AllowTabPreloading"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zNTUSER\Software\Policies\Microsoft\MicrosoftEdge\TabPreloader"; Value="AllowTabPreloading"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\EdgeUpdate"; Value="UpdateDefault"; Type="REG_DWORD"; Data="0"}
        )
        
        foreach ($reg in $edgeAddRegistry) {
            Write-Host "    → Modifying $($reg.Key)\$($reg.Value)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
        
        # Disable Edge updates and installation
        Write-Host "    → Disabling Edge updates and installation..." -ForegroundColor Cyan
        [Console]::Out.Flush()
        $registryKeys = @(
            "HKLM\zSOFTWARE\Microsoft\EdgeUpdate",
            "HKLM\zSOFTWARE\Policies\Microsoft\EdgeUpdate",
            "HKLM\zSOFTWARE\WOW6432Node\Microsoft\EdgeUpdate",
            "HKLM\zNTUSER\Software\Microsoft\EdgeUpdate",
            "HKLM\zNTUSER\Software\Policies\Microsoft\EdgeUpdate"
        )
        foreach ($key in $registryKeys) {
            Write-Host "      → Modifying $key..." -ForegroundColor Cyan
            [Console]::Out.Flush()
            reg add "$key" /v "DoNotUpdateToEdgeWithChromium" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
            reg add "$key" /v "UpdaterExperimentationAndConfigurationServiceControl" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
            reg add "$key" /v "InstallDefault" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
            Write-Host "      → $key [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
    }
    catch {
        Write-Log -msg "Error modifying registry: $_"
    }
    finally {
        # Always unload registry hives regardless of errors
        reg unload HKLM\zSOFTWARE 2>&1 | Write-Log
        reg unload HKLM\zSYSTEM 2>&1 | Write-Log
        reg unload HKLM\zNTUSER 2>&1 | Write-Log
        reg unload HKLM\zDEFAULT 2>&1 | Write-Log
    }

    # Remove EDGE files
    Write-Host "  → Removing Edge files..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $edgePaths = @(
        "$installMountDir\Program Files\Microsoft\Edge",
        "$installMountDir\Program Files\Microsoft\EdgeCore",
        "$installMountDir\Program Files\Microsoft\EdgeUpdate",
        "$installMountDir\Program Files\Microsoft\EdgeWebView",
        "$installMountDir\Program Files (x86)\Microsoft\Edge",
        "$installMountDir\Program Files (x86)\Microsoft\EdgeCore",
        "$installMountDir\Program Files (x86)\Microsoft\EdgeUpdate",
        "$installMountDir\Program Files (x86)\Microsoft\EdgeWebView",
        "$installMountDir\ProgramData\Microsoft\EdgeUpdate"
    )
    
    foreach ($edgePath in $edgePaths) {
        if (Test-Path $edgePath) {
            Write-Host "    → Removing $edgePath..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            Remove-Item -Path $edgePath -Recurse -Force 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
    }
    Get-ChildItem "$installMountDir\ProgramData\Microsoft\Windows\AppRepository\Packages\Microsoft.MicrosoftEdge.Stable*" -Directory | ForEach-Object { Set-OwnAndRemove -Path $_.FullName } 2>&1 | Write-Log
    Get-ChildItem "$installMountDir\ProgramData\Microsoft\Windows\AppRepository\Packages\Microsoft.MicrosoftEdgeDevToolsClient*" -Directory | ForEach-Object { Set-OwnAndRemove -Path $_.FullName } 2>&1 | Write-Log
    # Get-ChildItem "$installMountDir\Windows\WinSxS\*microsoft-edge-webview*" -Directory | ForEach-Object { Set-OwnAndRemove -Path $_.FullName } 2>&1 | Write-Log
    Set-OwnAndRemove -Path (Join-Path -Path $installMountDir -ChildPath 'Windows\System32\Microsoft-Edge-WebView') | Out-Null
    Set-OwnAndRemove -Path (Join-Path -Path $installMountDir -ChildPath 'Windows\SystemApps\Microsoft.Win32WebViewHost*' | Get-Item -ErrorAction SilentlyContinue).FullName | Out-Null

    # Removing EDGE-Task
    Get-ChildItem -Path "$installMountDir\Windows\System32\Tasks\MicrosoftEdge*" | Where-Object { $_ } | ForEach-Object { Set-OwnAndRemove -Path $_ } 2>&1 | Write-Log
    
    # For Windows 10 (Legacy EDGE)
    if ($buildNumber -lt 22000) {
        Get-ChildItem -Path "$installMountDir\Windows\SystemApps\Microsoft.MicrosoftEdge*" | Where-Object { $_ } | ForEach-Object { Set-OwnAndRemove -Path $_ } 2>&1 | Write-Log
    }
    
    Write-Host ("[OK] EDGE has been removed") -ForegroundColor Green
    Write-Log -msg "Microsoft Edge removal completed"
} else {
    Write-Log -msg "Edge removal cancelled"
}

if ($DoAIRemove) {
    # Remove AI components
    Write-Host ("`n[INFO] Removing AI components...") -ForegroundColor Cyan
    Write-Log -msg "Removing AI components"
    
    # Remove AI Packages
    Write-Host "  → Removing AI packages..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $AIpatterns = @(
        "Microsoft.Windows.Copilot*",
        "Microsoft.Copilot*"
    )
    foreach ($pattern in $AIpatterns) {
        $matchedPackages = Get-ProvisionedAppxPackage -Path $installMountDir | 
        Where-Object { $_.PackageName -like $pattern }
        foreach ($package in $matchedPackages) {
            Write-Host "    → Removing $($package.PackageName)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            try {
                Invoke-DismFailsafe {Remove-ProvisionedAppxPackage -Path $installMountDir -PackageName $package.PackageName} {dism /image:$installMountDir /Remove-ProvisionedAppxPackage /PackageName:$($package.PackageName)}
                Write-Host " [OK]" -ForegroundColor Green
                [Console]::Out.Flush()
            } catch {
                Write-Host " [FAILED]" -ForegroundColor Red
                [Console]::Out.Flush()
            }
        }
    }

    # Disable AI DLLs
    Write-Host "  → Removing AI DLLs..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $dllfiles = @('System32', 'SysWOW64') | ForEach-Object {
        Join-Path $installMountDir "Windows\$_\Windows.AI.MachineLearning.dll"
        Join-Path $installMountDir "Windows\$_\Windows.AI.MachineLearning.Preview.dll"
    }
    $dllfiles | Where-Object { Test-Path $_ } | ForEach-Object {
        Write-Host "    → Removing $_..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        Set-Ownership -Path $_ | Out-Null
        Rename-Item $_ ($_ + ".bak") -Force 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }

    # Modifying reg keys
    Write-Host "  → Modifying AI registry..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    try {
        reg load HKLM\zSOFTWARE "$installMountDir\Windows\System32\config\SOFTWARE" 2>&1 | Write-Log

        # Registry operations
        $aiRegistry = @(
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Value="TurnOffWindowsCopilot"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Edge"; Value="HubsSidebarEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer"; Value="DisableSearchBoxSuggestions"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\WindowsNotepad"; Value="DisableAIFeatures"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"; Value="DisableCocreator"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"; Value="DisableImageCreator"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Value="LetAppsAccessSystemAIModels"; Type="REG_DWORD"; Data="2"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Value="LetAppsAccessGenerativeAI"; Type="REG_DWORD"; Data="2"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI"; Value="Value"; Type="REG_SZ"; Data="Deny"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Edge"; Value="CopilotPageContext"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Edge"; Value="CopilotCDPPageContext"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Value="DisableClickToDo"; Type="REG_DWORD"; Data="1"}
        )
        
        foreach ($reg in $aiRegistry) {
            Write-Host "    → Modifying $($reg.Key)\$($reg.Value)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }

        # Disable Recall on first logon
        if ($buildNumber -ge 22000) {
            Write-Host "    → Disabling Recall..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v "DisableRecall" /t REG_SZ /d "dism.exe /online /disable-feature /FeatureName:recall" /f 2>&1 | Write-Log
            reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI" /v "DisableAIDataAnalysis" /t REG_DWORD /d 1 /f 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
    }
    catch {
        Write-Log -msg "Error modifying registry: $_"
    }
    finally {
        # Always unload registry hives regardless of errors
        reg unload HKLM\zSOFTWARE 2>&1 | Write-Log
    }
    Write-Host ("[OK] AI Components removed") -ForegroundColor Green
    Write-Log -msg "AI Components removal completed"
} else {
    Write-Log -msg "AI Components removal skipped"
}

if ($DoDefenderRemove) {
    # Remove Windows Defender (Compatible with LTSC)
    Write-Host ("`n[INFO] Removing Windows Defender...") -ForegroundColor Cyan
    Write-Log -msg "Removing Windows Defender"
    
    # Detect LTSC by checking for Windows Defender packages
    $isLTSC = $false
    try {
        $defenderPackages = Get-WindowsPackage -Path $installMountDir | Where-Object { $_.PackageName -like "*Windows-Defender*" }
        if ($defenderPackages.Count -eq 0) {
            $isLTSC = $true
            Write-Log -msg "LTSC detected: No Windows Defender packages found"
        }
    } catch {
        Write-Log -msg "LTSC detection: Could not check packages"
    }
    
    # Remove Windows Defender packages (if available)
    if (-not $isLTSC) {
        Write-Host "  → Removing Windows Defender packages..." -ForegroundColor Yellow
        [Console]::Out.Flush()
        $defenderPackages = Get-WindowsPackage -Path $installMountDir | Where-Object { 
            $_.PackageName -like "*Windows-Defender*" -or 
            $_.PackageName -like "*Defender*" -or
            $_.PackageName -like "*Antimalware*"
        }
        
        foreach ($package in $defenderPackages) {
            Write-Host "    → Removing $($package.PackageName)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            try {
                Write-Log -msg "Removing package: $($package.PackageName)"
                Invoke-DismFailsafe {
                    Remove-WindowsPackage -Path $installMountDir -PackageName $package.PackageName -ErrorAction Stop
                } {
                    dism /image:$installMountDir /Remove-Package /PackageName:$($package.PackageName) /NoRestart
                }
                Write-Host " [OK]" -ForegroundColor Green
                [Console]::Out.Flush()
            } catch {
                Write-Host " [FAILED]" -ForegroundColor Red
                [Console]::Out.Flush()
                Write-Log -msg "Failed to remove Defender package $($package.PackageName): $_"
            }
        }
    }
    
    # Disable Windows Defender services and registry (works for both standard and LTSC)
    Write-Host "  → Disabling Windows Defender services and registry..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    try {
        reg load HKLM\zSOFTWARE "$installMountDir\Windows\System32\config\SOFTWARE" 2>&1 | Write-Log
        reg load HKLM\zSYSTEM "$installMountDir\Windows\System32\config\SYSTEM" 2>&1 | Write-Log
        reg load HKLM\zNTUSER "$installMountDir\Users\Default\ntuser.dat" 2>&1 | Write-Log
        
        # Disable Windows Defender via Group Policy
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiVirus" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableRealtimeMonitoring" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableOnAccessProtection" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableScanOnRealtimeEnable" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Spynet" /v "SpynetReporting" /t REG_DWORD /d "0" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Spynet" /v "SubmitSamplesConsent" /t REG_DWORD /d "2" /f 2>&1 | Write-Log
        
        # Disable Windows Defender via registry (for compatibility)
        reg add "HKLM\zSOFTWARE\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Microsoft\Windows Defender\Real-Time Protection" /v "DisableRealtimeMonitoring" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        
        # Disable Windows Defender Services
        reg add "HKLM\zSYSTEM\CurrentControlSet\Services\WinDefend" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\CurrentControlSet\Services\WinDefend" /v "Enabled" /t REG_DWORD /d "0" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\ControlSet001\Services\WinDefend" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\ControlSet001\Services\WinDefend" /v "Enabled" /t REG_DWORD /d "0" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\CurrentControlSet\Services\SecurityHealthService" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\ControlSet001\Services\SecurityHealthService" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\CurrentControlSet\Services\WdNisSvc" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\ControlSet001\Services\WdNisSvc" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\CurrentControlSet\Services\Sense" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        reg add "HKLM\zSYSTEM\ControlSet001\Services\Sense" /v "Start" /t REG_DWORD /d "4" /f 2>&1 | Write-Log
        
        # Disable Windows Defender in Windows Security Center
        reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "DisableWindowsSecurityCenter" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
        reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellServiceObjects\{FD6905CE-952F-41F1-9A9F-EAC49C3C6104}" /v "Start" /t REG_DWORD /d "0" /f 2>&1 | Write-Log
        
        # Disable Windows Defender Scheduled Tasks
        reg delete "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f 2>&1 | Write-Log
        reg delete "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f 2>&1 | Write-Log
        
        # Remove Windows Defender files (if available)
        Write-Host "  → Removing Windows Defender files..." -ForegroundColor Yellow
        [Console]::Out.Flush()
        $defenderPaths = @(
            "$installMountDir\Program Files\Windows Defender",
            "$installMountDir\Program Files (x86)\Windows Defender",
            "$installMountDir\ProgramData\Microsoft\Windows Defender",
            "$installMountDir\Windows\System32\WindowsPowerShell\v1.0\Modules\WindowsDefender"
        )
        
        foreach ($defPath in $defenderPaths) {
            if (Test-Path $defPath) {
                Write-Host "    → Removing $defPath..." -ForegroundColor Cyan -NoNewline
                [Console]::Out.Flush()
                try {
                    Set-OwnAndRemove -Path $defPath | Out-Null
                    Write-Host " [OK]" -ForegroundColor Green
                    [Console]::Out.Flush()
                    Write-Log -msg "Removed Defender path: $defPath"
                } catch {
                    Write-Host " [FAILED]" -ForegroundColor Red
                    [Console]::Out.Flush()
                    Write-Log -msg "Could not remove Defender path: $defPath"
                }
            }
        }
        
        Write-Host ("[OK] Windows Defender removed") -ForegroundColor Green
        Write-Log -msg "Windows Defender removal completed"
    }
    catch {
        Write-Log -msg "Error modifying registry for Defender removal: $_"
        Write-Host "  Warning: Some Defender settings may not have been applied" -ForegroundColor Yellow
    }
    finally {
        # Always unload registry hives regardless of errors
        reg unload HKLM\zSOFTWARE 2>&1 | Write-Log
        reg unload HKLM\zSYSTEM 2>&1 | Write-Log
        reg unload HKLM\zNTUSER 2>&1 | Write-Log
    }
} else {
    Write-Log -msg "Windows Defender removal skipped"
}

# Registry Tweaks
Write-Host ("`n[INFO] Loading Registry...") -ForegroundColor Cyan
Write-Log -msg "Loading registry"
reg load HKLM\zCOMPONENTS "$installMountDir\Windows\System32\config\COMPONENTS" 2>&1 | Write-Log
reg load HKLM\zDEFAULT "$installMountDir\Windows\System32\config\default" 2>&1 | Write-Log
reg load HKLM\zNTUSER "$installMountDir\Users\Default\ntuser.dat" 2>&1 | Write-Log
reg load HKLM\zSOFTWARE "$installMountDir\Windows\System32\config\SOFTWARE" 2>&1 | Write-Log
reg load HKLM\zSYSTEM "$installMountDir\Windows\System32\config\SYSTEM" 2>&1 | Write-Log

# Setting Permissions
Set-Ownership -Registry @("zSOFTWARE\Microsoft\Windows\CurrentVersion\Communications", "zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks", "zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows", "zSOFTWARE\Microsoft\WindowsRuntime\Server\Windows.Gaming.GameBar.Internal.PresenceWriterServer")

Write-Host ("[OK] Registry loaded") -ForegroundColor Green

# Function to apply registry tweaks with real-time display
function Apply-RegistryTweaks {
    param (
        [string]$SectionName,
        [array]$RegistryOperations
    )
    
    Write-Host "  → $SectionName..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    
    foreach ($op in $RegistryOperations) {
        $displayKey = if ($op.Value) { "$($op.Key)\$($op.Value)" } else { $op.Key }
        Write-Host "    → Modifying $displayKey..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        
        try {
            if ($op.Type -eq "DELETE") {
                reg delete $op.Key /f 2>&1 | Write-Log
            } elseif ($op.Type -eq "CREATE") {
                reg add $op.Key /f 2>&1 | Write-Log
            } else {
                reg add $op.Key /v $op.Value /t $op.Type /d $op.Data /f 2>&1 | Write-Log
            }
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        } catch {
            Write-Host " [FAILED]" -ForegroundColor Red
            [Console]::Out.Flush()
            Write-Log -msg "Failed to modify registry: $displayKey - $_"
        }
    }
    
    Write-Host "  → $SectionName [DONE]" -ForegroundColor Green
    [Console]::Out.Flush()
}

# Modify registry settings
Write-Host ("`nPerforming Registry Tweaks...") -ForegroundColor Cyan

# Disable Sponsored Apps
$sponsoredAppsRegistry = @(
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="OemPreInstalledAppsEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="PreInstalledAppsEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SilentInstalledAppsEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent"; Value="DisableWindowsConsumerFeatures"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start"; Value="ConfigureStartPins"; Type="REG_SZ"; Data='{\"pinnedList\": [{}]}'},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContentEnabled"; Type="REG_SZ"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContentEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-310093Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-338388Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-338389Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-338393Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-353694Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-353696Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SubscribedContent-338387Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="ContentDeliveryAllowed"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="PreInstalledAppsEverEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SoftLandingEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Value="SystemPaneSuggestionsEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions"; Value=""; Type="DELETE"; Data=""},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps"; Value=""; Type="DELETE"; Data=""}
)
Apply-RegistryTweaks -SectionName "Disabling Sponsored Apps" -RegistryOperations $sponsoredAppsRegistry

# Disable Telemetry
$telemetryRegistry = @(
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection"; Value="AllowTelemetry"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Personalization\Settings"; Value="AcceptedPrivacyPolicy"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy"; Value="TailoredExperiencesWithDiagnosticDataEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Value="HasAccepted"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\InputPersonalization"; Value="RestrictImplicitInkCollection"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\InputPersonalization"; Value="RestrictImplicitTextCollection"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore"; Value="HarvestContacts"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Value="Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice"; Value="Start"; Type="REG_DWORD"; Data="4"}
)
Apply-RegistryTweaks -SectionName "Disabling Telemetry" -RegistryOperations $telemetryRegistry

# Disable Mouse Acceleration
$mouseAccelRegistry = @(
    @{Key="HKLM\zNTUSER\Control Panel\Mouse"; Value="MouseSpeed"; Type="REG_SZ"; Data="0"},
    @{Key="HKLM\zNTUSER\Control Panel\Mouse"; Value="MouseThreshold1"; Type="REG_SZ"; Data="0"},
    @{Key="HKLM\zNTUSER\Control Panel\Mouse"; Value="MouseThreshold2"; Type="REG_SZ"; Data="0"}
)
Apply-RegistryTweaks -SectionName "Disabling Mouse Acceleration" -RegistryOperations $mouseAccelRegistry

# Disable Meet Now icon
$meetNowRegistry = @(
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Value="HideSCAMeetNow"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Value="AllowOnlineTips"; Type="REG_DWORD"; Data="0"}
)
Apply-RegistryTweaks -SectionName "Disabling Meet Now" -RegistryOperations $meetNowRegistry

# Disable Ads and Stuffs
$adsRegistry = @(
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Value="Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent"; Value="DisableConsumerAccountStateContent"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent"; Value="DisableCloudOptimizedContent"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Value="Start_IrisRecommendations"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Value="EnableFeeds"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Value="{2cc5ca98-6485-489a-920e-b3e88a6ccce3}"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Search"; Value="AllowCortana"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\Control Panel\Desktop"; Value="MenuShowDelay"; Type="REG_SZ"; Data="200"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\MRT"; Value="DontOfferThroughWUAU"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Teams"; Value="DisableInstallation"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail"; Value="PreventRun"; Type="REG_DWORD"; Data="1"}
)
Apply-RegistryTweaks -SectionName "Disabling Ads and Stuffs" -RegistryOperations $adsRegistry

# Disable Bitlocker
$bitlockerRegistry = @(
    @{Key="HKLM\zSYSTEM\ControlSet001\Control\BitLocker"; Value="PreventDeviceEncryption"; Type="REG_DWORD"; Data="1"}
)
Apply-RegistryTweaks -SectionName "Disabling Bitlocker Encryption" -RegistryOperations $bitlockerRegistry

# Disable OneDrive Stuffs
$oneDriveStuffsRegistry = @(
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run"; Value="OneDriveSetup"; Type="DELETE"; Data=""},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive"; Value="DisableLibrariesDefaultSaveToOneDrive"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive"; Value="DisableFileSyncNGSC"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\OneDrive"; Value="KFMBlockOptIn"; Type="REG_DWORD"; Data="1"}
)
Apply-RegistryTweaks -SectionName "Removing OneDrive Junks" -RegistryOperations $oneDriveStuffsRegistry

# Disable GameDVR
$gameDVRRegistry = @(
    @{Key="HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR"; Value="AppCaptureEnabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zNTUSER\System\GameConfigStore"; Value="GameDVR_Enabled"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\GameDVR"; Value="AllowGameDVR"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSYSTEM\ControlSet001\Services\BcastDVRUserService"; Value="Start"; Type="REG_DWORD"; Data="4"},
    @{Key="HKLM\zSYSTEM\ControlSet001\Services\GameBarPresenceWriter"; Value="Start"; Type="REG_DWORD"; Data="4"}
)
Apply-RegistryTweaks -SectionName "Disabling GameDVR and Components" -RegistryOperations $gameDVRRegistry

# Remove Gamebar Popup
# Courtesy: https://pastebin.com/EAABLssA by aveyo
$gamebarPopupRegistry = @(
    @{Key="HKLM\zNTUSER\Software\Microsoft\GameBar"; Value="AutoGameModeEnabled"; Type="REG_DWORD"; Data="0"}
)
Apply-RegistryTweaks -SectionName "Removing Gamebar Popup" -RegistryOperations $gamebarPopupRegistry
# Rest added as post install script. Somehow, implementing it directly on the image was causing corruption

# # Configure GameBarFTServer (NA)
# $packageKey = "HKLM\zSOFTWARE\Classes\PackagedCom\ClassIndex\{FD06603A-2BDF-4BB1-B7DF-5DC68F353601}"
# $app = (Get-Item "Registry::$packageKey").PSChildName
# reg add "HKLM\zSOFTWARE\Classes\PackagedCom\Package\$app\Server\0" /v "Executable" /t REG_SZ /d "systray.exe" /f 2>&1 | Write-Log

# Enabling Local Account Creation
$oobeRegistry = @(
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\OOBE"; Value="DisablePrivacyExperience"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"; Value="BypassNRO"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"; Value="BypassNROGatherOptions"; Type="REG_DWORD"; Data="1"}
)
Apply-RegistryTweaks -SectionName "Tweaking OOBE Settings" -RegistryOperations $oobeRegistry

# Check if Autounattend.xml exists before copying
Write-Host "  → Copying Autounattend.xml..." -ForegroundColor Yellow -NoNewline
[Console]::Out.Flush()
if (Test-Path -Path $autounattendXmlPath) {
    Write-Log -msg "Copying Autounattend.xml"
    Copy-Item -Path $autounattendXmlPath -Destination $destinationPath -Force
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
} else {
    Write-Host " [NOT FOUND]" -ForegroundColor Yellow
    [Console]::Out.Flush()
    Write-Warning "Autounattend.xml not found at $autounattendXmlPath"
    Write-Log -msg "Warning: Autounattend.xml not found at $autounattendXmlPath"
}

# Prevents Dev Home Installation
$uselessJunksRegistry = @(
    @{Key="HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate"; Value=""; Type="DELETE"; Data=""},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate"; Value="workCompleted"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"; Value=""; Type="DELETE"; Data=""},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate"; Value="workCompleted"; Type="REG_DWORD"; Data="1"},
    @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Communications"; Value="ConfigureChatAutoInstall"; Type="REG_DWORD"; Data="0"},
    @{Key="HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Value="ChatIcon"; Type="REG_DWORD"; Data="3"}
)
Apply-RegistryTweaks -SectionName "Disabling useless junks" -RegistryOperations $uselessJunksRegistry

# Disable Scheduled Tasks
Write-Host "  → Disabling Scheduled Tasks..." -ForegroundColor Yellow
[Console]::Out.Flush()
$win24H2 = (Get-ItemProperty -Path 'Registry::HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion -eq '24H2'

if ($win24H2) {
    # Customer Experience Improvement Program
    Write-Host "    → Removing Customer Experience Improvement Program tasks..." -ForegroundColor Cyan
    [Console]::Out.Flush()
    $ceipTasks = @(
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{780E487D-C62F-4B55-AF84-0E38116AFE07}",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{FD607F42-4541-418A-B812-05C32EBA8626}",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{E4FED5BC-D567-4044-9642-2EDADF7DE108}"
    )
    foreach ($task in $ceipTasks) {
        Write-Host "      → Removing $task..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg delete $task /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    Write-Host "      → Removing CEIP task folder..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Customer Experience Improvement Program" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    # Program Data Updater
    Write-Host "    → Removing Program Data Updater..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    reg delete "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{E292525C-72F1-482C-8F35-C513FAA98DAE}" /f 2>&1 | Write-Log
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Application Experience\ProgramDataUpdater" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    # Application Compatibility Appraiser
    Write-Host "    → Removing Compatibility Appraiser tasks..." -ForegroundColor Cyan
    [Console]::Out.Flush()
    $appraiserTasks = @(
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{3047C197-66F1-4523-BA92-6C955FEF9E4E}",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{A0C71CB8-E8F0-498A-901D-4EDA09E07FF4}"
    )
    foreach ($task in $appraiserTasks) {
        Write-Host "      → Removing $task..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg delete $task /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    Write-Host "      → Removing Compatibility Appraiser task folder..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
}
else {
    # Customer Experience Improvement Program
    Write-Host "    → Removing Customer Experience Improvement Program tasks..." -ForegroundColor Cyan
    [Console]::Out.Flush()
    $ceipTasks = @(
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{4738DE7A-BCC1-4E2D-B1B0-CADB044BFA81}",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{6FAC31FA-4A85-4E64-BFD5-2154FF4594B3}",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{FC931F16-B50A-472E-B061-B6F79A71EF59}"
    )
    foreach ($task in $ceipTasks) {
        Write-Host "      → Removing $task..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg delete $task /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    Write-Host "      → Removing CEIP task folder..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Customer Experience Improvement Program" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    # Program Data Updater
    Write-Host "    → Removing Program Data Updater..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    reg delete "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0671EB05-7D95-4153-A32B-1426B9FE61DB}" /f 2>&1 | Write-Log
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Application Experience\ProgramDataUpdater" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    
    # Application Compatibility Appraiser
    Write-Host "    → Removing Compatibility Appraiser..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    reg delete "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\{0600DD45-FAF2-4131-A006-0B17509B9F78}" /f 2>&1 | Write-Log
    Set-OwnAndRemove -Path "$installMountDir\Windows\System32\Tasks\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
}

# Common scheduled tasks registry entries
Write-Host "    → Removing common scheduled task registry entries..." -ForegroundColor Cyan
[Console]::Out.Flush()
$commonTasks = @(
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Application Experience\PcaPatchDbTask",
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Application Experience\MareBackup",
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Autochk\Proxy",
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
)
foreach ($task in $commonTasks) {
    Write-Host "      → Removing $task..." -ForegroundColor Cyan -NoNewline
    [Console]::Out.Flush()
    reg delete $task /f 2>&1 | Write-Log
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
}
Write-Host "  → Disabling Scheduled Tasks [DONE]" -ForegroundColor Green
[Console]::Out.Flush()

# Disable TPM CHeck
if ($DoTPMBypass) {
    Write-Host ("`n[INFO] Disabling TPM Check...") -ForegroundColor Cyan
    Write-Log -msg "Disabling TPM Check"
    
    Write-Host "  → Modifying TPM bypass registry..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $tpmRegistry = @(
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassTPMCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassSecureBootCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassStorageCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassCPUCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassRAMCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassDiskCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\LabConfig"; Value="BypassProductKeyCheck"; Type="REG_DWORD"; Data="1"},
        @{Key="HKLM\zSYSTEM\Setup\MoSetup"; Value="AllowUpgradesWithUnsupportedTPMOrCPU"; Type="REG_DWORD"; Data="1"}
    )
    
    foreach ($reg in $tpmRegistry) {
        Write-Host "    → Modifying $($reg.Key)\$($reg.Value)..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    
    # Disable Unsupported Hardware Watermark
    Write-Host "  → Disabling Unsupported Hardware Watermark..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $watermarkRegistry = @(
        @{Key="HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV1"; Type="REG_DWORD"; Data="0"},
        @{Key="HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV2"; Type="REG_DWORD"; Data="0"},
        @{Key="HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV1"; Type="REG_DWORD"; Data="0"},
        @{Key="HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV2"; Type="REG_DWORD"; Data="0"},
        @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Value="HideUnsupportedHardwareNotifications"; Type="REG_DWORD"; Data="1"}
    )
    
    foreach ($reg in $watermarkRegistry) {
        Write-Host "    → Modifying $($reg.Key)\$($reg.Value)..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    
    # Clear upgrade failure records
    Write-Host "  → Clearing upgrade failure records..." -ForegroundColor Yellow
    [Console]::Out.Flush()
    $upgradeRecords = @(
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared",
        "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators"
    )
    
    foreach ($record in $upgradeRecords) {
        Write-Host "    → Removing $record..." -ForegroundColor Cyan -NoNewline
        [Console]::Out.Flush()
        reg delete $record /f 2>&1 | Write-Log
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
    }
    
    # Simulate meeting requirements
    Write-Host "  → Simulating meeting requirements..." -ForegroundColor Yellow -NoNewline
    [Console]::Out.Flush()
    reg add "HKLM\zSOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk" /v "HwReqChkVars" /t REG_MULTI_SZ /d "SQ_SecureBootCapable=TRUE\0SQ_SecureBootEnabled=TRUE\0SQ_TpmVersion=2\0SQ_RamMB=8192" /f 2>&1 | Write-Log
    reg add "HKLM\zNTUSER\Software\Microsoft\PCHC" /v "UpgradeEligibility" /t REG_DWORD /d "1" /f 2>&1 | Write-Log
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()

    # Remove appraiserres.dll and replace with blank file
    Write-Host "  → Removing appraiserres.dll..." -ForegroundColor Yellow -NoNewline
    [Console]::Out.Flush()
    $apprdllPath = Join-Path -Path $destinationPath -ChildPath "sources\appraiserres.dll"
    Set-OwnAndRemove -Path "$apprdllPath" | Out-Null
    New-Item -Path $apprdllPath -ItemType File -Force 2>&1 | Write-Log
    Write-Host " [OK]" -ForegroundColor Green
    [Console]::Out.Flush()
    try {
        $ProgressPreference = 'SilentlyContinue'
        Write-Host "  → Mounting boot.wim for TPM bypass..." -ForegroundColor Yellow -NoNewline
        [Console]::Out.Flush()
        $bootWimPath = Join-Path $destinationPath "sources\boot.wim"
        $bootMountDir = "$env:SystemDrive\WIDTemp\mountdir\bootWIM"
        New-Item -ItemType Directory -Path $bootMountDir 2>&1 | Write-Log
        Invoke-DismFailsafe {Mount-WindowsImage -ImagePath $bootWimPath -Index 2 -Path $bootMountDir}{ {dism /mount-image /imagefile:$bootWimPath /index:2 /mountdir:$bootMountDir}}
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()

        Write-Host "  → Modifying boot.wim registry..." -ForegroundColor Yellow
        [Console]::Out.Flush()
        reg load HKLM\xDEFAULT "$bootMountDir\Windows\System32\config\default" 2>&1 | Write-Log
        reg load HKLM\xNTUSER "$bootMountDir\Users\Default\ntuser.dat" 2>&1 | Write-Log
        reg load HKLM\xSYSTEM "$bootMountDir\Windows\System32\config\SYSTEM" 2>&1 | Write-Log
        reg load HKLM\xSOFTWARE "$bootMountDir\Windows\System32\config\SOFTWARE" 2>&1 | Write-Log

        $bootTpmRegistry = @(
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassTPMCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassSecureBootCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassStorageCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassCPUCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassRAMCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassDiskCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\LabConfig"; Value="BypassProductKeyCheck"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSYSTEM\Setup\MoSetup"; Value="AllowUpgradesWithUnsupportedTPMOrCPU"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xDEFAULT\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV1"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\xDEFAULT\Control Panel\UnsupportedHardwareNotificationCache"; Value="SV2"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\xSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Value="HideUnsupportedHardwareNotifications"; Type="REG_DWORD"; Data="1"},
            @{Key="HKLM\xSOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk"; Value="HwReqChkVars"; Type="REG_MULTI_SZ"; Data="SQ_SecureBootCapable=TRUE\0SQ_SecureBootEnabled=TRUE\0SQ_TpmVersion=2\0SQ_RamMB=8192"},
            @{Key="HKLM\xNTUSER\Software\Microsoft\PCHC"; Value="UpgradeEligibility"; Type="REG_DWORD"; Data="1"}
        )
        
        foreach ($reg in $bootTpmRegistry) {
            Write-Host "    → Modifying $($reg.Key)\$($reg.Value)..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }

        reg unload HKLM\xDEFAULT 2>&1 | Write-Log
        reg unload HKLM\xNTUSER 2>&1 | Write-Log
        reg unload HKLM\xSYSTEM 2>&1 | Write-Log
        reg unload HKLM\xSOFTWARE 2>&1 | Write-Log

        Write-Host "  → Saving boot.wim..." -ForegroundColor Yellow -NoNewline
        [Console]::Out.Flush()
        Invoke-DismFailsafe {Dismount-WindowsImage -Path $bootMountDir -Save} {dism /unmount-image /mountdir:$bootMountDir /commit}
        Write-Host " [OK]" -ForegroundColor Green
        [Console]::Out.Flush()
        Write-Host ("[OK] TPM Bypass Successful") -ForegroundColor Green
        Write-Log -msg "Successfully modified boot.wim for TPM Bypass"
    }
    catch {
        Write-Host " [FAILED]" -ForegroundColor Red
        [Console]::Out.Flush()
        Write-Log -msg "Failed to mount boot.wim: $_"
    }
    finally {
        $ProgressPreference = 'Continue'
    }
}
else {
    Write-Log -msg "TPM Bypass cancelled"
}

# Bring back user folders
if ($buildNumber -ge 22000) {
    if ($DoUserFoldersEnable) {
        Write-Host ("`n[INFO] Restoring User Folders...") -ForegroundColor Cyan
        Write-Log -msg "Restoring User Folders"

        Write-Host "  → Enabling user folders..." -ForegroundColor Yellow
        [Console]::Out.Flush()
        $userFoldersRegistry = @(
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{d3162b92-9365-467a-956b-92703aca08af}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{088e3905-0323-4b02-9826-5d99428e115f}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{24ad3ad4-a569-4530-98e1-ab02f9417aa8}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}"; Value=""; Type="CREATE"; Data=""},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{d3162b92-9365-467a-956b-92703aca08af}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{088e3905-0323-4b02-9826-5d99428e115f}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{24ad3ad4-a569-4530-98e1-ab02f9417aa8}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}"; Value="HideIfEnabled"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{d3162b92-9365-467a-956b-92703aca08af}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{088e3905-0323-4b02-9826-5d99428e115f}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{3dfdf296-dbec-4fb4-81d1-6a3438bcf4de}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{24ad3ad4-a569-4530-98e1-ab02f9417aa8}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"},
            @{Key="HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{f86fa3ab-70d2-4fc7-9c99-fcbf05467f3a}"; Value="HiddenByDefault"; Type="REG_DWORD"; Data="0"}
        )
        
        foreach ($reg in $userFoldersRegistry) {
            $displayKey = if ($reg.Value) { "$($reg.Key)\$($reg.Value)" } else { $reg.Key }
            Write-Host "    → Modifying $displayKey..." -ForegroundColor Cyan -NoNewline
            [Console]::Out.Flush()
            if ($reg.Type -eq "CREATE") {
                reg add $reg.Key /f 2>&1 | Write-Log
            } else {
                reg add $reg.Key /v $reg.Value /t $reg.Type /d $reg.Data /f 2>&1 | Write-Log
            }
            Write-Host " [OK]" -ForegroundColor Green
            [Console]::Out.Flush()
        }
        
        Write-Host ("[OK] User Folders Restored") -ForegroundColor Green
        Write-Log -msg "User folders restored successfully"
    } else {
        Write-Log -msg "User folders restoration cancelled"
    }
}

# Unload Registry (Critical: Must unload before unmounting to prevent corruption)
Write-Host ("`n[INFO] Unloading Registry...") -ForegroundColor Cyan
[Console]::Out.Flush()
Write-Log -msg "Unloading registry hives"

# Function to safely unload registry hive
function Unload-RegistryHive {
    param([string]$HiveName)
    $attempts = 0
    $maxAttempts = 3
    while ($attempts -lt $maxAttempts) {
        try {
            $result = reg unload $HiveName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -msg "Successfully unloaded registry hive: $HiveName"
                return $true
            } else {
                $attempts++
                if ($attempts -lt $maxAttempts) {
                    Write-Log -msg "Retry $attempts/$maxAttempts unloading $HiveName"
                    Start-Sleep -Seconds 1
                }
            }
        } catch {
            $attempts++
            if ($attempts -lt $maxAttempts) {
                Write-Log -msg "Error unloading $HiveName, retrying..."
                Start-Sleep -Seconds 1
            }
        }
    }
    Write-Log -msg "Warning: Failed to unload registry hive: $HiveName after $maxAttempts attempts"
    return $false
}

# Unload registry hives in reverse order (important for COMPONENTS)
Unload-RegistryHive "HKLM\zCOMPONENTS" | Out-Null
Unload-RegistryHive "HKLM\zDEFAULT" | Out-Null
Unload-RegistryHive "HKLM\zNTUSER" | Out-Null
Unload-RegistryHive "HKLM\zSOFTWARE" | Out-Null
Unload-RegistryHive "HKLM\zSYSTEM" | Out-Null

Write-Host ("[OK] Registry unloaded successfully") -ForegroundColor Green
[Console]::Out.Flush()

# Unmounting and cleaning up the image
Write-Host ("`n[INFO] Cleaning up image...") -ForegroundColor Cyan
Write-Log -msg "Cleaning up image"
Invoke-DismFailsafe {Repair-WindowsImage -Path $installMountDir -StartComponentCleanup -ResetBase} {dism /image:$installMountDir /Cleanup-Image /StartComponentCleanup /ResetBase}

Write-Host ("`n[INFO] Unmounting and Exporting image...") -ForegroundColor Cyan
Write-Log -msg "Unmounting image"
try {
    Invoke-DismFailsafe {Dismount-WindowsImage -Path $installMountDir -Save} {dism /unmount-image /mountdir:$installMountDir /commit}
    Write-Log -msg "Image unmounted successfully"
}
catch {
    Write-Host "`n`nFailed to Unmount the Image. Check Logs for more info." -ForegroundColor Red
    Write-Host "Close all the Folders opened in the mountdir to complete the Script."
    Write-Host "Run the following code in Powershell(as admin) to unmount the broken image: "
    Write-Host "Dismount-WindowsImage -Path $installMountDir -Discard" -ForegroundColor Yellow
    Write-Log -msg "Failed to unmount image: $_"
    Pause
    Exit
}

Write-Log -msg "Exporting image"
$tempWimPath = "$destinationPath\sources\install_temp.wim"
$exportSuccess = $false

if ($DoESDConvert) {
    Write-Host ("`n[INFO] Compressing image to esd...") -ForegroundColor Cyan
    Write-Log -msg "Compressing image to esd"
    try {        
        $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Export-Image /SourceImageFile:`"$destinationPath\sources\install.wim`" /SourceIndex:$sourceIndex /DestinationImageFile:`"$tempWimPath`" /Compress:Recovery /CheckIntegrity" -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -eq 0 -and (Test-Path $tempWimPath)) {
            $exportSuccess = $true
            Write-Host ("[OK] Compression completed") -ForegroundColor Green
            Write-Log -msg "Compression completed"
        } else {
            Write-Host "Compression failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            Write-Log -msg "Compression failed with exit code: $($process.ExitCode)"
        }
    } catch {
        Write-Host "Compression failed with error: $_" -ForegroundColor Red
        Write-Log -msg "Compression failed with error: $_"
    }
}
else {
    Write-Host ("`n[INFO] Exporting image to wim...") -ForegroundColor Cyan
    Write-Log -msg "Exporting image to wim"
    try {
        Invoke-DismFailsafe {Export-WindowsImage -SourceImagePath "$destinationPath\sources\install.wim" -SourceIndex $sourceIndex -DestinationImagePath $tempWimPath -CompressionType Maximum -CheckIntegrity} {dism /Export-Image /SourceImageFile:$destinationPath\sources\install.wim /SourceIndex:$sourceIndex /DestinationImageFile:$tempWimPath /compress:max}
        if (Test-Path $tempWimPath) {
            $exportSuccess = $true
            Write-Host ("[OK] Export completed successfully") -ForegroundColor Green
            Write-Log -msg "Export completed successfully"
        } else {
            Write-Host "Export failed - temp WIM not found" -ForegroundColor Red
            Write-Log -msg "Export failed - temp WIM not found"
        }
    } catch {
        Write-Host "Export failed with error: $_" -ForegroundColor Red
        Write-Log -msg "Export failed with error: $_"
    }
}

if ($exportSuccess) {
    Remove-Item -Path "$destinationPath\sources\install.wim" -Force
    Move-Item -Path $tempWimPath -Destination "$destinationPath\sources\install.wim" -Force
   
    if (-not (Test-Path "$destinationPath\sources\install.wim")) {
        Write-Host "Error: Unable to create the WIM file. Check logs for details." -ForegroundColor Red
        Write-Log -msg "Final install.wim missing"
        Pause
        Exit
    } else {
        Write-Log -msg "WIM file successfully replaced"
    }
} else {
    Write-Host "Error: Unable to export modified WIM file. Check logs for details." -ForegroundColor Red
    Write-Log -msg "WIM export failed, original WIM file preserved"
    Pause
    Exit
}

# Verify the WIM file is accessible and valid
try {
    $wimPath = Get-WindowsImage -ImagePath "$destinationPath\sources\install.wim" -ErrorAction Stop
    if ($wimPath) {
        Write-Host ("[OK] WIM file validation successful: $($wimPath.Count) images found") -ForegroundColor Green
        Write-Log -msg "WIM validation passed: $($wimPath.Count) images found"
        
        # Force a filesystem sync to ensure all changes are written to disk
        [System.IO.File]::OpenWrite("$destinationPath\sources\install.wim").Close()
        # Add a small delay to ensure file operations are complete
        Start-Sleep -Seconds 3
    } else {
        Write-Warning "WIM file validation returned no images"
        Write-Log -msg "WIM validation warning: No images returned"
    }
} catch {
    Write-Host "Error: WIM file validation failed - $($_)" -ForegroundColor Red
    Write-Log -msg "WIM validation failed: $_"
}

Write-Log -msg "Checking required files"
if ($outputISO) {
    $ISOFileName = ($ISOFileName -replace '[<>:"/\\|?*\x00-\x1F\s]', '').Trim()
    $ISOFileName = [System.IO.Path]::GetFileNameWithoutExtension($outputISO)
} else {
    do {
        $ISOFileName = Read-Host -Prompt "`nEnter the name for the ISO file (without extension)"

        # Remove invalid characters
        $ISOFileName = ($ISOFileName -replace '[<>:"/\\|?*\x00-\x1F\s]', '').Trim()
        if ([string]::IsNullOrWhiteSpace($ISOFileName)) {
            Write-Warning "Filename is empty or invalid. Please enter a valid name."
        }
    } while ([string]::IsNullOrWhiteSpace($ISOFileName))
}
$ISOFile = Join-Path -Path $scriptDirectory -ChildPath "$ISOFileName.iso"
Write-Log -msg "ISO file name set to: $ISOFileName.iso"

if ($DoUseOscdimg) {
    if (-not (Test-Path -Path $Oscdimg)) {
        Write-Log -msg "Oscdimg.exe not found at '$Oscdimg'"
        Write-Host "`nOscdimg.exe not found at '$Oscdimg'." -ForegroundColor Red
        Write-Host "`nTrying to Download oscdimg.exe..." -ForegroundColor Cyan

        # Function to check internet connection
        function Test-InternetConnection {
            param (
                [int]$maxAttempts = 3,
                [int]$retryDelay = 5,
                [string]$hostname = "1.1.1.1", # Cloudflare DNS
                [int]$port = 53,
                [int]$timeout = 5000
            )
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    $client = [Net.Sockets.TcpClient]::new()
                    if ($client.ConnectAsync($hostname, $port).Wait($timeout)) {
                        $client.Close(); return $true
                    }
                    $client.Close()
                } catch {}
                Write-Host "Internet connection not available, Trying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
            }  
            Write-Host "`nInternet connection not available after $maxAttempts attempts." -ForegroundColor Red
            Write-Host "A working internet connection is required to download oscdimg.exe."
            Write-Host "Check your connection and try again."

            while ($true) {
                $internetChoice = Read-Host -Prompt "`nPress 't' to try again or 'q' to quit"
                switch ($internetChoice.ToLower()) {
                    't' { return Test-InternetConnection @PSBoundParameters }
                    'q' {
                        Remove-TempFiles
                        Exit
                    }
                    default { Write-Host "Invalid input. Enter 't' or 'q'." }
                }
            }
        }
        
        Test-InternetConnection

        # Downloading Oscdimg.exe
        # Courtesy: https://github.com/p0w3rsh3ll/ADK
        $ADKfolder = "$scriptDirectory\ADKDownload"
        $CabFileName = "5d984200acbde182fd99cbfbe9bad133.cab"
        $ExtractedFileName = "fil720cc132fbb53f3bed2e525eb77bdbc1"

        New-Item -ItemType Directory -Path $OscdimgPath -Force 2>&1 | Write-Log
        New-Item -ItemType Directory -Path $ADKfolder -Force 2>&1 | Write-Log
        
        # Resolve the URL
        $RedirectResponse = Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2290227" -MaximumRedirection 0 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($RedirectResponse.StatusCode -eq 302) {
            $BaseURL = $RedirectResponse.Headers.Location.TrimEnd('/') + "/"
            $CabURL = "$BaseURL`Installers/$CabFileName"
            $CabFilePath = "$ADKfolder\$CabFileName"
        
            Write-Log -msg "Downloading CAB file from: $CabURL"
            Invoke-WebRequest -Uri $CabURL -OutFile $CabFilePath -UseBasicParsing
        
            # Extract the CAB file
            Write-Log -msg "Extracting CAB file..."
            expand.exe -F:* $CabFilePath $ADKfolder 2>&1 | Write-Log
        
            # Move the required file
            $ExtractedFilePath = "$ADKfolder\$ExtractedFileName"
            $FinalFilePath = "$OscdimgPath\oscdimg.exe"
        
            if (Test-Path $ExtractedFilePath) {
                Move-Item -Path $ExtractedFilePath -Destination $FinalFilePath -Force 2>&1 | Write-Log
                Write-Host "Oscdimg.exe downloaded successfully" -ForegroundColor Green
                Write-Log -msg "Oscdimg.exe successfully placed in: $OscdimgPath"
            }
            else {
                Write-Log -msg "Error: Extracted file not found!"
            }
        }
        else {
            Write-Host "Error: Failed to download Oscdimg.exe" -ForegroundColor Red
            Write-Log -msg "Failed to resolve ADK download link. HTTP Status: $($RedirectResponse.StatusCode)"
            Remove-TempFiles
            Pause
            Exit
        }
    }

    # Generate ISO
    Write-Host ("`n[INFO] Generating ISO...") -ForegroundColor Cyan
    Write-Log -msg "Generating ISO using OSCDIMG"
    try {
        $etfsbootPath = "$destinationPath\boot\etfsboot.com"
        $efisysPath = "$destinationPath\efi\Microsoft\boot\efisys.bin"
        $bootData = "2#p0,e,b`"$etfsbootPath`"#pEF,e,b`"$efisysPath`""
        Write-Log -msg "Boot data set: $bootData"
        
        $oscdimgArgs = @(
            "-bootdata:$bootData",
            "-m",               # Ignore maximum size limit
            "-o",               # Optimize for space
            "-h",               # Show hidden files
            "-u2",              # UDF 2.0
            "-udfver102",       # UDF version 1.02
            "-l$ISOFileName",   # Set volume label
            "`"$destinationPath`"",
            "`"$ISOFile`""
        )
        
        Write-Log -msg "OSCDIMG command: $Oscdimg $($oscdimgArgs -join ' ')"
        $oscdimgProcess = Start-Process -FilePath "$Oscdimg" -ArgumentList $oscdimgArgs -PassThru -Wait -NoNewWindow
        
        if ($oscdimgProcess.ExitCode -eq 0) {
            Write-Host ("[OK] ISO creation successful") -ForegroundColor Green
            Write-Log -msg "ISO successfully created with exit code 0"
        } else {
            Write-Warning "ISO creation finished with errors"
            Write-Log -msg "OSCDIMG exited with code: $($oscdimgProcess.ExitCode)"
        }
    }
    catch {
        Write-Log -msg "Failed to generate ISO with exit code: $_"
    }
}
else {
    Write-Host "`n[INFO] Preparing ISO creation..." -ForegroundColor Cyan
    Write-Log -msg "Preparing ISO creation"

    # ISOWriter class
    # More Here: https://learn.microsoft.com/en-us/windows/win32/api/_imapi/
    if (!('ISOWriter' -as [Type])) {
        Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        using System.Runtime.InteropServices.ComTypes;

        public class ISOWriter {
            [DllImport("shlwapi.dll", CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = false)]
            private static extern void SHCreateStreamOnFileEx(string fileName, uint mode, uint attributes, bool create, IStream streamNull, out IStream stream);
            public static bool Create(string filePath, ref object imageStream, int blockSize, int totalBlocks) {IStream resultStream = (IStream)imageStream, imageFile; SHCreateStreamOnFileEx(filePath, 0x1001, 0x80, true, null, out imageFile); const int bufferSize = 1024; int remainingBlocks = totalBlocks;
                while (remainingBlocks > 0) { int blocksToWrite = Math.Min(remainingBlocks, bufferSize); resultStream.CopyTo(imageFile, blocksToWrite * blockSize, IntPtr.Zero, IntPtr.Zero); remainingBlocks -= blocksToWrite;}
                imageFile.Commit(0);
                return true;}
        }
'@
    }

    try {
        $comObjects = @()

        # Initialize boot configuration
        $bootStream = New-Object -ComObject ADODB.Stream -Property @{ Type = 1 }
        $comObjects += $bootStream
        $bootStream.Open()
        $bootStream.LoadFromFile("$destinationPath\efi\Microsoft\boot\efisys.bin")
        # $bootStream.LoadFromFile("$destinationPath\efi\Microsoft\boot\efisys_noprompt.bin")

        # Configure boot and filesystem
        $bootOptions = New-Object -ComObject IMAPI2FS.BootOptions -Property @{
            PlatformId = 0xEF
            Manufacturer = "Microsoft"
            Emulation = 0
        }
        $comObjects += $bootOptions
        $bootOptions.AssignBootImage($bootStream)

        $FSImage = New-Object -ComObject IMAPI2FS.MsftFileSystemImage -Property @{
            FileSystemsToCreate = 4
            UDFRevision = 0x102
            FreeMediaBlocks = 0
            VolumeName = $ISOFileName
        }
        $comObjects += $FSImage
        
        Write-Log -msg "Creating ISO structure"
        $FSImage.Root.AddTree($destinationPath, $false)
        $FSImage.BootImageOptions = $bootOptions
        
        Write-Host "[INFO] Generating ISO..." -ForegroundColor Cyan
        Write-Log -msg "Generating ISO using ISOWriter"
        $resultImage = $FSImage.CreateResultImage()
        $comObjects += $resultImage

        [ISOWriter]::Create($ISOFile, [ref]$resultImage.ImageStream, $resultImage.BlockSize, $resultImage.TotalBlocks) | Out-Null
        
        if ((Get-Item $ISOFile).Length -eq ($resultImage.BlockSize * $resultImage.TotalBlocks)) {
            Write-Log -msg "ISO successfully created at: $ISOFile"
        }
    }
    catch {
        Write-Log -msg "ISO creation failed: $_" -Type Error
    }
    finally {
        foreach ($obj in $comObjects) {
            if ($obj) { 
                while ([Runtime.InteropServices.Marshal]::ReleaseComObject($obj) -gt 0) { }
            }
        }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Write-Host "[OK] ISO creation successful" -ForegroundColor Green
    }
}

# ISO verification
if (Test-Path -Path $ISOFile) {
    try {
        $verifyMntResult = Mount-DiskImage -ImagePath "$ISOFile" -PassThru
        $verifyDrive = ($verifyMntResult | Get-Volume).DriveLetter
        $isoMountPoint = "${verifyDrive}:\"
        $reqFiles = @("sources\boot.wim", "boot\bcd", "boot\boot.sdi", "bootmgr", "bootmgr.efi", "efi\microsoft\boot\efisys.bin")
        # Check for either install.wim or install.esd
        $installWimPath = Join-Path $isoMountPoint "sources\install.wim"
        $installEsdPath = Join-Path $isoMountPoint "sources\install.esd"
        if (-not (Test-Path $installWimPath) -and -not (Test-Path $installEsdPath)) {
            $reqFiles += "sources\install.wim (or install.esd)"
        }
        $missingFiles = $reqFiles | Where-Object { -not (Test-Path (Join-Path $isoMountPoint $_)) }

        Dismount-DiskImage -ImagePath "$ISOFile" 2>&1 | Write-Log

        if ($missingFiles) {
            Write-Host "`nError: Created ISO is missing critical files" -ForegroundColor Red
            Write-Log -msg "ISO verification failed - missing files: $($missingFiles -join ', ')"
        }
        else {
            Write-Host "`nScript Completed. Can find the ISO in `"$scriptDirectory`"" -ForegroundColor Green
            Write-Log -msg "ISO verification successful"
        }
    }
    catch {
        Write-Warning "`nUnable to verify ISO integrity"
        Write-Log -msg "Failed to verify ISO: $_"
    }
} else {
    Write-Host "`nError: ISO file wasn't created" -ForegroundColor Red
    Write-Log -msg "ISO file wasn't created"
}

# Remove temporary files
Write-Log -msg "Removing temporary files"
try {
    Remove-TempFiles
}
catch {
    Write-Log -msg "Failed to remove temporary files: $_"
}
finally {
    Write-Log -msg "Script completed"
}

Write-Host
Pause