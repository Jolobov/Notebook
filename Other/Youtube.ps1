# ===================================================================
#                      USER CONFIGURATION BLOCK
# ===================================================================
# Modify the values in this section to customize the script's behavior.
# Do not change the variable names, only the values after the '=' sign.
#--------------------------------------------------------------------

# --- Installation Settings ---
[array]$AppsToInstall = @("pwsh", "yt-dlp", "ffmpeg", "mutagen", "nano")
[string]$CheckInternetHost = "google.com"
[bool]$UpdateScoop = $false
[bool]$UpdateApps = $false

# --- Download Settings ---
[string]$playlistDownloadFolder = Join-Path $HOME "Downloads"
[string]$playlistEditor = "notepad.exe"
[string]$downloadArchiveFile = Join-Path $playlistDownloadFolder "downloaded_archive.txt" # Set to $null or "" to disable

# --- Proxy Settings (Optional) ---
[string]$ProxyAddress = "127.0.0.1"
[string]$ProxyPort = "2080"
[string]$ProxyProtocol = "http" # e.g., http, https, socks5

# --- Parallel Download Settings ---
[int]$parallelJobLimit = 2

# --- Advanced yt-dlp Settings (Modify with caution) ---
[array]$ytDlpBaseArgs = @(
    "--format", "(bestvideo[vcodec^=avc1][height<=1080])+(bestaudio[acodec^=opus]/bestaudio)"
    "--force-ipv4"
    "--no-overwrites"
    "--concurrent-fragments", "5"
    "--output", "%(upload_date)s - %(uploader)s - %(title)s.%(ext)s"
    "--merge-output-format", "mp4"
    "--sponsorblock-remove", "default"
    "--match-filters", "!is_live"
    # --- ADDED: Suppress progress bar output ---
    # "--no-progress"
    # ------------------------------------------
    # Note: --download-archive is added dynamically if $downloadArchiveFile is set
)

# ===================================================================
#                  END OF USER CONFIGURATION BLOCK
# ===================================================================

# --- Script Initialization ---
$playlistFilePath = Join-Path $playlistDownloadFolder "playlist.txt"

#region Helper Functions

function Write-HostColored($Message, $Color, $NewLine = $true) {
    if ($NewLine) { Write-Host $Message -ForegroundColor $Color }
    else { Write-Host $Message -ForegroundColor $Color -NoNewline }
}

# --- Corrected Invoke-InDirectory (Accepts ArgumentList) ---
function Invoke-InDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$false)][array]$ArgumentList
    )
    $originalLocation = $PWD
    $locationChanged = $false
    Write-Verbose "Attempting to change directory to '$Path'"
    $output = $null
    try {
        Push-Location -LiteralPath $Path -ErrorAction Stop
        $locationChanged = $true
        Write-HostColored "Changed directory to '$Path' for operation." "Cyan"
        # Execute the script block and capture its output
        if ($PSBoundParameters.ContainsKey('ArgumentList')) {
             # Pass arguments if provided
             $output = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        } else {
             # Execute without arguments if none provided
             $output = Invoke-Command -ScriptBlock $ScriptBlock
        }
    } catch {
        Write-HostColored "Error during operation in directory '$Path': $($_.Exception.Message)" "Red"
    } finally {
        if ($locationChanged) {
            try { Pop-Location -ErrorAction SilentlyContinue; Write-HostColored "Returned to original directory ($($originalLocation.Path))." "Cyan" }
            catch { Write-HostColored "Error returning to original directory ($($originalLocation.Path)): $($_.Exception.Message)" "Yellow" }
        }
    }
    # Return the output captured from the script block
    return $output
}

function Test-UrlFormat {
    param([string]$Url)
    # Basic check for absolute URI structure
    return [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$null)
}

# --- Sub-Methods for Playlist Logic ---

function Ensure-DirectoryExists {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-HostColored "Directory '$Path' not found. Creating..." "Yellow"
        try {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-HostColored "Directory created successfully." "Green"
            return $true
        } catch {
            Write-HostColored "Failed to create directory '$Path': $($_.Exception.Message)" "Red"
            return $false
        }
    }
    return $true # Directory already exists
}

function Ensure-PlaylistFileExists {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-HostColored "Playlist file '$Path' not found. Creating empty file..." "Yellow"
        try {
            @"
# Add video URLs here, one per line. Lines starting with # are ignored.
# Example: https://www.youtube.com/watch?v=dQw4w9WgXcQ
"@ | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
            Write-HostColored "Empty playlist file created. Please edit it." "Green"
        } catch {
            Write-HostColored "Failed to create playlist file '$Path': $($_.Exception.Message)" "Red"
            return $false
        }
    }
     return $true # File exists or was created
}

function Invoke-PlaylistEditor {
    param(
        [Parameter(Mandatory=$true)][string]$EditorPath,
        [Parameter(Mandatory=$true)][string]$FilePath
    )
    Write-HostColored "`nOpening playlist file '$FilePath' with $EditorPath for editing..." "Yellow"
    Write-Host "Please add/edit the video URLs, save the file, and close the editor."
    try {
        if (-not (Get-Command $EditorPath -ErrorAction SilentlyContinue)) { throw "Editor '$EditorPath' not found or not in PATH." }
        Start-Process $EditorPath -ArgumentList $FilePath -Wait -ErrorAction Stop
        Write-HostColored "Editor closed." "Green"
        return $true # Assume user wants to proceed after closing editor
    } catch {
        Write-HostColored "Error interacting with editor '$EditorPath': $($_.Exception.Message)" "Red"
        $proceed = Read-Host "Press Enter to attempt download with current playlist content, or type 'N' then Enter to cancel."
        if ($proceed -match '^(n|no)$') {
             Write-HostColored "Playlist editing/download cancelled by user." "Magenta"
             return $false # User cancelled
        }
        return $true # User wants to proceed despite editor error
    }
}

function Confirm-DownloadAction {
    param([Parameter(Mandatory=$true)][string]$Mode) # 'Sequential' or 'Parallel'
    $confirm = Read-Host "`nReady to start $Mode downloading from playlist? (yes/no)"
    if ($confirm -match '^(y|yes)$') {
        return $true
    } else {
        Write-HostColored "$Mode playlist download cancelled by user." "Magenta"
        return $false
    }
}

function Get-PlaylistUrls {
    param([Parameter(Mandatory=$true)][string]$Path)
    Write-HostColored "`nReading URLs from playlist file '$Path'..." "Yellow"
    $validUrls = [System.Collections.Generic.List[string]]::new()
    $invalidUrls = [System.Collections.Generic.List[string]]::new()
    try {
        $lines = Get-Content $Path -ErrorAction Stop
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) { continue }

            if (Test-UrlFormat -Url $trimmedLine) {
                $validUrls.Add($trimmedLine)
            } else {
                Write-HostColored "Invalid URL format found in playlist: $trimmedLine" "Yellow"
                $invalidUrls.Add($trimmedLine + " (Invalid Format)") # Add marker
            }
        }
        Write-HostColored "Found $($validUrls.Count) valid URL(s) and $($invalidUrls.Count) invalid line(s)." "Green"
        return [PSCustomObject]@{
            ValidUrls = $validUrls.ToArray()
            InvalidUrls = $invalidUrls.ToArray() # Contains invalid format URLs
        }
    } catch {
        Write-HostColored "An error occurred reading playlist file '$Path': $($_.Exception.Message)" "Red"
        return [PSCustomObject]@{ ValidUrls = @(); InvalidUrls = @() }
    }
}

# --- Corrected Execute-SequentialDownload (Uses Out-Host) ---
function Execute-SequentialDownload {
    param(
        [Parameter(Mandatory=$true)][array]$Urls,
        [Parameter(Mandatory=$true)][array]$BaseArgs,
        [string]$ArchiveFile # Optional, passed from caller
    )
    $failedUrlsList = [System.Collections.Generic.List[string]]::new()
    $totalVideos = $Urls.Count
    $currentVideoIndex = 0

    Write-HostColored "`nStarting sequential download execution..." "Yellow"

    # Determine arguments ONCE before the loop for clarity
    $localCommandArgs = $BaseArgs
    if (-not [string]::IsNullOrWhiteSpace($ArchiveFile)) {
        $localCommandArgs += @("--download-archive", $ArchiveFile)
    }

    foreach ($currentVideoUrl in $Urls) {
        $currentVideoIndex++
        Write-HostColored "`n[ $($currentVideoIndex) / $($totalVideos) ] Processing URL: $currentVideoUrl" "Cyan"

        # Add the current URL to the base args
        $finalArgs = $localCommandArgs + @($currentVideoUrl)

        Write-Host "Executing command:`n  yt-dlp $($finalArgs -join ' ')"
        $downloadError = $false
        try {
            # --- Use Out-Host to show progress (if not suppressed by --no-progress) ---
            & yt-dlp $finalArgs | Out-Host
            # --- End Out-Host modification ---

            # Check exit code *after* Out-Host
            if ($LASTEXITCODE -ne 0) { Write-HostColored "yt-dlp failed (Exit Code: $LASTEXITCODE) for: ${currentVideoUrl}" "Red"; $downloadError = $true }
        } catch { Write-HostColored "Failed to run yt-dlp for ${currentVideoUrl}: $($_.Exception.Message)" "Red"; $downloadError = $true }

        if ($downloadError) { $failedUrlsList.Add($currentVideoUrl) }
        Write-Host # Blank line
    } # End foreach URL

    Write-HostColored "`nSequential download execution finished." "Green"
    return $failedUrlsList.ToArray() # Return failed URLs
}

# --- Execute-ParallelDownload (ONLY Start/End Markers via Write-Host, No yt-dlp Output) ---
function Execute-ParallelDownload {
    param(
        [Parameter(Mandatory=$true)][array]$Urls,
        [Parameter(Mandatory=$true)][array]$BaseArgs,
        [Parameter(Mandatory=$true)][int]$ThrottleLimit,
        [string]$ArchiveFile # Optional, passed from caller
    )
    $failedUrlsBag = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

    Write-HostColored "`nStarting parallel download execution... Only Start/Finish status will be shown per URL." "Yellow"

    $Urls | ForEach-Object -Parallel {
        $url = $_
        # Access outer scope variables using $using:
        $threadLocalBaseArgs = $using:BaseArgs
        $threadArchiveFile = $using:ArchiveFile
        $localFailedUrlsBag = $using:failedUrlsBag
        # Timestamp and Process/Thread Info
        $timeStamp = "[$(Get-Date -Format 'HH:mm:ss'))]"
        $procInfo = "[PID:$PID Thread:$([System.Threading.Thread]::CurrentThread.ManagedThreadId)]"

        # Prepare arguments for this specific URL
        $commandArgs = $threadLocalBaseArgs
        if (-not [string]::IsNullOrWhiteSpace($threadArchiveFile)) { $commandArgs += @("--download-archive", $threadArchiveFile) }
        $commandArgs += @($url)

        $downloadError = $false
        $exitCode = -1 # Default exit code
        $statusMessage = ""

        # --- Log Start using Write-Host ---
        Write-Host "$timeStamp $procInfo Starting download for: $url" -ForegroundColor Cyan

        try {
            # --- Execute yt-dlp, REDIRECTING ALL its output streams to $null ---
            # We only care about the exit code.
            & yt-dlp $commandArgs *>$null
            $exitCode = $LASTEXITCODE # Capture exit code

            if ($exitCode -ne 0) {
                $downloadError = $true
            }
        } catch {
            # Still log critical launch errors using Write-Host
             Write-Host "$timeStamp $procInfo CRITICAL ERROR launching yt-dlp for $url : $($_.Exception.Message)" -ForegroundColor Red
            $downloadError = $true
            # ExitCode might remain -1 or previous value if launch fails before execution
        } finally {
             # --- Log End using Write-Host ---
             if ($downloadError) {
                 $statusMessage = "FAILED (Exit Code: $exitCode)"
                 Write-Host "$timeStamp $procInfo Finished processing ($statusMessage) for: $url" -ForegroundColor Red
                 $localFailedUrlsBag.Add($url)
             } else {
                 $statusMessage = "SUCCESS (Exit Code: 0)" # Assume 0 if no error
                 Write-Host "$timeStamp $procInfo Finished processing ($statusMessage) for: $url" -ForegroundColor Green
             }
        }
    } -ThrottleLimit $ThrottleLimit

    Write-HostColored "`nParallel download execution finished." "Green"
    return $failedUrlsBag.ToArray()
}


function Display-DownloadSummary {
    param([array]$FailedUrls)

    if ($FailedUrls -and $FailedUrls.Count -gt 0) { # Check if array is not null or empty
        Write-HostColored "`n--- Download Summary: $($FailedUrls.Count) URL(s) reported errors ---" "Red"
        $sortedFailedUrls = $FailedUrls | Sort-Object
        foreach ($failedUrl in $sortedFailedUrls) { Write-HostColored "- $failedUrl" "Red" }
        Write-HostColored "Check console output (look for FAILED messages) for details." "Yellow"
    } else {
        Write-HostColored "`nDownload Summary: All processed URLs completed without script-reported errors." "Green"
    }
     Write-Host # Blank line
}

#endregion Helper Functions

# ===================================================================
#                           PART 1: SETUP
# ===================================================================
Clear-Host
Write-HostColored "=======================================" "Cyan"
Write-HostColored "      Scoop & App Setup Script         " "Cyan"
Write-HostColored "=======================================" "Cyan"
Write-Host ""
Write-HostColored "Checking internet connection..." "Yellow" -NewLine $false
$InternetTest = Test-Connection -ComputerName $CheckInternetHost -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $InternetTest) { Write-HostColored " FAILED" "Red"; Write-HostColored "`nNo internet connection detected." "Red"; Read-Host "Press Enter to exit"; exit 1 }
else { Write-HostColored " OK" "Green" }
Write-HostColored "`nChecking Scoop installation..." "Yellow"
$scoopInstalled = $false
if (Get-Command scoop -ErrorAction SilentlyContinue) { Write-HostColored "Scoop is already installed." "Green"; $scoopInstalled = $true }
else {
    Write-HostColored "Scoop is not installed." "Magenta"
    $installScoop = Read-Host "Do you want to install Scoop? (yes/no)"
    if ($installScoop -match '^(y|yes)$') {
        Write-HostColored "`nAttempting to install Scoop..." "Yellow"
        try {
            Write-HostColored "Setting Execution Policy..." "Cyan"; Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Write-HostColored "Downloading and executing installer..." "Cyan"; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression -ErrorAction Stop
            if (Get-Command scoop -ErrorAction SilentlyContinue) { Write-HostColored "Scoop installed successfully!" "Green"; $scoopInstalled = $true }
            else { Write-HostColored "Scoop installation failed." "Red"; Read-Host "Press Enter to exit"; exit 1 }
        } catch { Write-HostColored "`nScoop installation error: $($_.Exception.Message)" "Red"; Read-Host "Press Enter to exit"; exit 1 }
    } else { Write-HostColored "`nSkipping Scoop installation." "Magenta" }
}
if ($scoopInstalled -and $UpdateScoop) {
    Write-HostColored "`nUpdating Scoop (as configured)..." "Yellow"
    scoop update; if ($LASTEXITCODE -ne 0) { Write-HostColored "Scoop update finished with errors." "Yellow" } else { Write-HostColored "Scoop update finished." "Green" }
} elseif ($scoopInstalled) { Write-HostColored "`nSkipping Scoop update as configured." "Magenta" }
if ($scoopInstalled) {
    Write-HostColored "`nChecking/installing required programs..." "Yellow"
    $FailedInstalls = @(); $InstalledCount = 0; $AlreadyInstalledCount = 0; $AppsToUpdateList = @()
    $installedAppsList = try { scoop list | Select-Object -ExpandProperty Name -ErrorAction Stop } catch { Write-HostColored "`nError getting Scoop list: $($_.Exception.Message)" "Red"; @() }
    foreach ($app in $AppsToInstall) {
        Write-HostColored "Checking '$($app)'..." "Cyan" -NewLine $false
        if ($installedAppsList -contains $app) { Write-HostColored " present." "Green"; $AlreadyInstalledCount++; $AppsToUpdateList += $app }
        else {
            Write-Host ""; Write-HostColored "Installing '$($app)'..." "Yellow"; scoop install $app
            if ($LASTEXITCODE -ne 0) { Write-HostColored "Failed to install '$($app)'." "Red"; $FailedInstalls += $app }
            else { Write-HostColored "'$($app)' installed." "Green"; $InstalledCount++; $AppsToUpdateList += $app }
        }
    }
    if ($UpdateApps -and $AppsToUpdateList.Count -gt 0) {
        Write-HostColored "`nChecking app updates ($($AppsToUpdateList -join ', '))..." "Yellow"
        scoop update $AppsToUpdateList; if ($LASTEXITCODE -ne 0) { Write-HostColored "App update finished with errors." "Yellow" } else { Write-HostColored "App updates checked." "Green" }
    } elseif (-not $UpdateApps) { Write-HostColored "`nSkipping app update check as configured." "Magenta" }
    Write-HostColored "`n---------------------------------------" "Cyan"
    Write-HostColored "Installation & Update Summary:" "Cyan"
    Write-HostColored " Checked: $($AppsToInstall.Count) apps. Present: $AlreadyInstalledCount. Newly installed: $InstalledCount." "Cyan"
    if ($UpdateApps -and $AppsToUpdateList.Count -gt 0){ Write-HostColored " Update attempted for: $($AppsToUpdateList.Count) apps." "Cyan"}
    if ($FailedInstalls.Count -gt 0) { Write-HostColored " Failed installs: $($FailedInstalls.Count) ($($FailedInstalls -join ', '))" "Red" }
    else { Write-HostColored " All required apps seem present." "Green" }
    Write-HostColored "---------------------------------------" "Cyan"
} elseif (-not $scoopInstalled) { Write-HostColored "`nCannot manage programs; Scoop not installed/skipped." "Red" }
Read-Host "`nSetup phase complete. Press Enter..."

# ===================================================================
#             PART 2: MAIN FUNCTIONALITY (Refactored Calls)
# ===================================================================

#region Main Functions (Single Video Downloads)

# --- Corrected Download-SingleVideo (Uses Out-Host) ---
function Download-SingleVideo {
    param([Parameter(Mandatory=$true)][string]$VideoUrl)
    Write-HostColored "`nStarting download: $VideoUrl" "Yellow"
    # Use global $ytDlpBaseArgs available in local Invoke-Command
    # Add URL for this specific call
    $localArgs = $ytDlpBaseArgs + @($VideoUrl)
    Write-Host "`nExecuting: yt-dlp $($localArgs -join ' ')"
    try {
        # Use Out-Host to show progress (if not suppressed by --no-progress)
        & yt-dlp $localArgs | Out-Host
        # Check exit code *after* Out-Host
        if ($LASTEXITCODE -ne 0) { Write-HostColored "`nyt-dlp failed (Exit Code: $LASTEXITCODE) for: ${VideoUrl}" "Red" }
    } catch { Write-HostColored "`nFailed to run yt-dlp for ${VideoUrl}: $($_.Exception.Message)" "Red" }
    Write-Host
}

# --- Corrected Download-SingleVideoWithProxy (Uses Out-Host) ---
function Download-SingleVideoWithProxy {
    param([Parameter(Mandatory=$true)][string]$VideoUrl)
    # Use global proxy vars & $ytDlpBaseArgs
    $proxyString = ""; if (-not [string]::IsNullOrWhiteSpace($ProxyProtocol)) { $proxyString = "$($ProxyProtocol)://" }; $proxyString += "$($ProxyAddress):$($ProxyPort)"
    Write-HostColored "`nStarting download via proxy ($proxyString): $VideoUrl" "Yellow"
    # Add proxy and URL for this specific call
    $localArgs = $ytDlpBaseArgs + @("--proxy", $proxyString, $VideoUrl)
    Write-Host "`nExecuting: yt-dlp $($localArgs -join ' ')"
    try {
        # Use Out-Host to show progress (if not suppressed by --no-progress)
        & yt-dlp $localArgs | Out-Host
        # Check exit code *after* Out-Host
        if ($LASTEXITCODE -ne 0) { Write-HostColored "`nyt-dlp failed via proxy (Exit Code: $LASTEXITCODE) for: ${VideoUrl}" "Red" }
    } catch { Write-HostColored "`nFailed to run yt-dlp via proxy for ${VideoUrl}: $($_.Exception.Message)" "Red" }
    Write-Host
}
#endregion

#region Main Functions (Playlist Downloads - Refactored Calls)

function Edit-And-Download-Playlist {
    Write-HostColored "`n--- Playlist Download Mode (Sequential) ---" "Cyan"
    $prevPref = $global:ProgressPreference; $global:ProgressPreference = 'SilentlyContinue' # Suppress inner progress bars

    # Use local scope for archive file path
    $currentArchiveFile = $downloadArchiveFile
    $useArchive = -not [string]::IsNullOrWhiteSpace($currentArchiveFile)

    if (-not (Ensure-DirectoryExists -Path $playlistDownloadFolder)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Ensure-PlaylistFileExists -Path $playlistFilePath)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Invoke-PlaylistEditor -EditorPath $playlistEditor -FilePath $playlistFilePath)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Confirm-DownloadAction -Mode 'Sequential')) { $global:ProgressPreference = $prevPref; return }

    $playlistData = Get-PlaylistUrls -Path $playlistFilePath
    $failedUrls = $playlistData.InvalidUrls # Start with invalid format URLs as failed
    if ($playlistData.ValidUrls.Count -eq 0) {
        Write-HostColored "No valid URLs found in playlist to download." "Magenta"
        Display-DownloadSummary -FailedUrls $failedUrls
        $global:ProgressPreference = $prevPref; return
    }

    $totalStartTime = Get-Date
    # Use ArgumentList to pass variables
    $invokeArgs = @(
        $playlistData.ValidUrls,
        $ytDlpBaseArgs,
        $(if($useArchive) { $currentArchiveFile } else { $null }) # Pass path or $null
    )
    $executionFailedUrls = Invoke-InDirectory -Path $playlistDownloadFolder -ScriptBlock {
        param($Urls, $BaseArgs, $ArchiveFile)
        # Execute-SequentialDownload uses Out-Host
        Execute-SequentialDownload -Urls $Urls -BaseArgs $BaseArgs -ArchiveFile $ArchiveFile
    } -ArgumentList $invokeArgs

    if ($executionFailedUrls) { $failedUrls += $executionFailedUrls }

    $totalEndTime = Get-Date; $totalDuration = $totalEndTime - $totalStartTime
    Write-HostColored "`nTotal Playlist Operation Time (Sequential): $($totalDuration.ToString('g'))" "Cyan"

    # --- Remove archive file (if used) ---
    if ($useArchive -and (Test-Path -Path $currentArchiveFile -PathType Leaf)) {
        Write-HostColored "Attempting to remove download archive file..." "Cyan"
        try {
            Remove-Item -Path $currentArchiveFile -Force -ErrorAction Stop
            Write-HostColored "Removed download archive file: $currentArchiveFile" "Green"
        } catch {
            Write-HostColored "Failed to remove download archive file '$currentArchiveFile': $($_.Exception.Message)" "Yellow"
        }
    }
    # --- END Archive Removal ---

    Display-DownloadSummary -FailedUrls $failedUrls
    $global:ProgressPreference = $prevPref # Restore preference
}

function Edit-And-Download-Playlist-Parallel {
     if ($PSVersionTable.PSVersion.Major -lt 7) { Write-HostColored "Parallel requires PS7+. Use sequential (3)." "Red"; Read-Host "Press Enter"; return }
    Write-HostColored "`n--- Playlist Download Mode (Parallel - PS7+) ---" "Cyan"
     $prevPref = $global:ProgressPreference; $global:ProgressPreference = 'SilentlyContinue'

    # Use local scope for archive file path
    $currentArchiveFile = $downloadArchiveFile
    $useArchive = -not [string]::IsNullOrWhiteSpace($currentArchiveFile)

    if (-not (Ensure-DirectoryExists -Path $playlistDownloadFolder)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Ensure-PlaylistFileExists -Path $playlistFilePath)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Invoke-PlaylistEditor -EditorPath $playlistEditor -FilePath $playlistFilePath)) { $global:ProgressPreference = $prevPref; return }
    if (-not (Confirm-DownloadAction -Mode 'Parallel')) { $global:ProgressPreference = $prevPref; return }

    $playlistData = Get-PlaylistUrls -Path $playlistFilePath
    $failedUrls = $playlistData.InvalidUrls
     if ($playlistData.ValidUrls.Count -eq 0) {
        Write-HostColored "No valid URLs found in playlist to download." "Magenta"
        Display-DownloadSummary -FailedUrls $failedUrls
        $global:ProgressPreference = $prevPref; return
    }

    $totalStartTime = Get-Date
    # Use ArgumentList to pass variables
    $invokeArgs = @(
        $playlistData.ValidUrls,
        $ytDlpBaseArgs,
        $parallelJobLimit,
        $(if($useArchive) { $currentArchiveFile } else { $null }) # Pass path or $null
    )
    $executionFailedUrls = Invoke-InDirectory -Path $playlistDownloadFolder -ScriptBlock {
        param($Urls, $BaseArgs, $ThrottleLimit, $ArchiveFile)
        # Execute-ParallelDownload uses Write-Host with Start/End markers, suppresses yt-dlp output
        Execute-ParallelDownload -Urls $Urls -BaseArgs $BaseArgs -ThrottleLimit $ThrottleLimit -ArchiveFile $ArchiveFile
    } -ArgumentList $invokeArgs

    if ($executionFailedUrls) { $failedUrls += $executionFailedUrls }

    $totalEndTime = Get-Date; $totalDuration = $totalEndTime - $totalStartTime
     Write-HostColored "`nTotal Playlist Operation Time (Parallel): $($totalDuration.ToString('g'))" "Cyan"

    # --- Remove archive file (if used) ---
    if ($useArchive -and (Test-Path -Path $currentArchiveFile -PathType Leaf)) {
        Write-HostColored "Attempting to remove download archive file..." "Cyan"
        try {
            Remove-Item -Path $currentArchiveFile -Force -ErrorAction Stop
            Write-HostColored "Removed download archive file: $currentArchiveFile" "Green"
        } catch {
            Write-HostColored "Failed to remove download archive file '$currentArchiveFile': $($_.Exception.Message)" "Yellow"
        }
    }
    # --- END Archive Removal ---

    Display-DownloadSummary -FailedUrls $failedUrls
    $global:ProgressPreference = $prevPref
}

#endregion

# ===================================================================
#                       USER INTERACTION LOOP
# ===================================================================
do {
    Write-HostColored "`n---------------------------------------" "Cyan"
    Write-HostColored "Select Action:" "Cyan"
    Write-HostColored "1. Download Single Video (Direct)" "White"
    Write-HostColored "2. Download Single Video (via Proxy: $($ProxyProtocol)://$($ProxyAddress):$($ProxyPort))" "White"
    Write-HostColored "3. Download from Playlist (Sequential)" "White"
    Write-HostColored "4. Download from Playlist (Parallel - PS7+)" "White"
    Write-HostColored "5. Open Download Folder ('$playlistDownloadFolder')" "White"
    Write-HostColored "Q. Quit" "White"
    $choice = Read-Host "Enter your choice (1, 2, 3, 4, 5, or Q)"
    switch ($choice) {
        '1' {
            $url = Read-Host "Enter video URL (direct)"
            if ([string]::IsNullOrWhiteSpace($url)) { Write-HostColored "URL empty." "Red" }
            elseif (-not (Test-UrlFormat -Url $url)) { Write-HostColored "Invalid URL format." "Red" }
            else {
                 if (Ensure-DirectoryExists -Path $playlistDownloadFolder) {
                     # Call Invoke-InDirectory, passing the URL via ArgumentList
                     Invoke-InDirectory -Path $playlistDownloadFolder -ScriptBlock {
                         param($VideoUrlToDownload) # Define param block
                         # Call the function which now uses Out-Host internally
                         Download-SingleVideo -VideoUrl $VideoUrlToDownload
                     } -ArgumentList @($url) # Pass the url via ArgumentList
                 }
                 else {
                      Write-HostColored "Downloads folder issue. Downloading here." "Yellow";
                      # Direct call if folder fails. Uses Out-Host via the function.
                      Download-SingleVideo -VideoUrl $url
                 }
            }
        }
        '2' {
            $url = Read-Host "Enter video URL (proxy)"
             if ([string]::IsNullOrWhiteSpace($url)) { Write-HostColored "URL empty." "Red" }
             elseif (-not (Test-UrlFormat -Url $url)) { Write-HostColored "Invalid URL format." "Red" }
             else {
                 if (Ensure-DirectoryExists -Path $playlistDownloadFolder) {
                     # Call Invoke-InDirectory, passing the URL via ArgumentList
                     Invoke-InDirectory -Path $playlistDownloadFolder -ScriptBlock {
                         param($VideoUrlToDownload) # Define param block
                         # Call the function which now uses Out-Host internally
                         Download-SingleVideoWithProxy -VideoUrl $VideoUrlToDownload
                     } -ArgumentList @($url) # Pass the url via ArgumentList
                 }
                 else {
                      Write-HostColored "Downloads folder issue. Downloading here." "Yellow";
                      # Direct call if folder fails. Uses Out-Host via the function.
                      Download-SingleVideoWithProxy -VideoUrl $url
                 }
            }
        }
        '3' { Edit-And-Download-Playlist } # Handles Invoke-InDirectory correctly and removes archive
        '4' { Edit-And-Download-Playlist-Parallel } # Handles Invoke-InDirectory correctly, uses Write-Host markers, suppresses yt-dlp output, removes archive
        '5' {
            Write-HostColored "`nOpening download folder: $playlistDownloadFolder" "Yellow"
            if (Test-Path -Path $playlistDownloadFolder -PathType Container) {
                try { Invoke-Item -Path $playlistDownloadFolder -ErrorAction Stop; Write-HostColored "Folder opened." "Green" }
                catch { Write-HostColored "Failed to open folder: $($_.Exception.Message)" "Red" }
            } else { Write-HostColored "Download folder does not exist." "Red" }
             Write-Host
        }
        'q' { Write-HostColored "Exiting." "Green" }
        default { Write-HostColored "Invalid choice." "Red" }
    }
} while ($choice -ne 'q')

# --- End of Script ---
Write-Host "`nScript operations complete."