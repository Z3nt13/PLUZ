$ScriptDir = $PSScriptRoot
$PayloadsDir = Join-Path $ScriptDir "payloads"
$Today = (Get-Date).ToString("dd.MM.yyyy")

# --- Load Environment Settings ---
$EnvPath = Join-Path $ScriptDir ".env"
if (Test-Path $EnvPath) {
    Get-Content $EnvPath | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } | ForEach-Object {
        $Key, $Value = $_ -split '=', 2
        $Key = $Key.Trim()
        $Value = $Value.Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($Key, $Value)
    }
}

$GH_USER   = $env:GH_USER
$GH_REPO   = $env:GH_REPO
$GH_BRANCH = if ($env:GH_BRANCH) { $env:GH_BRANCH } else { "main" }
$GH_TOKEN  = $env:GH_TOKEN

if (-not (Test-Path $PayloadsDir)) { New-Item -ItemType Directory $PayloadsDir | Out-Null }

$Headers = @{ "User-Agent" = "PowerShell-Payload-Manager" }
if ($GH_TOKEN -and $GH_TOKEN.Trim() -ne "") { $Headers["Authorization"] = "Bearer $GH_TOKEN" }

$ApiCache = @{}

function Get-GitHubReleaseByChannel($Owner, $Repo, $Channel, $Headers) {
    $CacheKey = "$Owner/$Repo/$Channel"
    if ($ApiCache.ContainsKey($CacheKey)) { return $ApiCache[$CacheKey] }
    
    $ApiUrl = "https://api.github.com/repos/$Owner/$Repo/releases"
    try {
        $Releases = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -Method Get -ErrorAction Stop
        $SelectedRelease = $null
        
        switch ($Channel.ToLower()) {
            "alpha" { $SelectedRelease = $Releases | Where-Object { $_.prerelease -and $_.tag_name -like "*alpha*" } | Select-Object -First 1 }
            "beta"  { $SelectedRelease = $Releases | Where-Object { $_.prerelease -and $_.tag_name -like "*beta*" } | Select-Object -First 1 }
            default { $SelectedRelease = $Releases | Where-Object { -not $_.prerelease -and -not $_.draft } | Select-Object -First 1 }
        }
        
        # Fallback to absolute latest if channel filter yields empty
        if (-not $SelectedRelease -and $Releases.Count -gt 0) { $SelectedRelease = $Releases[0] }
        
        $ApiCache[$CacheKey] = $SelectedRelease
        return $SelectedRelease
    } catch {
        return $null
    }
}

function ConvertTo-CleanJson($InputObject) {
    $RawJson = $InputObject | ConvertTo-Json -Depth 10
    $CleanLines = [System.Collections.Generic.List[String]]::new()
    foreach ($Line in ($RawJson -split "`r`n")) {
        $Trimmed = $Line.TrimStart()
        $LeadCount = $Line.Length - $Trimmed.Length
        $NewLead = "  " * [Math]::Floor($LeadCount / 4)
        if ($Line -match '^\s*[}\]]') { $NewLead = "  " * [Math]::Max(0, ([Math]::Floor($LeadCount / 4))) }
        $CleanLines.Add($NewLead + $Trimmed)
    }
    return ($CleanLines -join "`r`n")
}

# --- Target Processing ---
$UpstreamPath = Join-Path $ScriptDir "Z3nT1s-PLUZ.json"
$HostedPath   = Join-Path $ScriptDir "Z3nT1s-PLUZ-Hosted.json"

if (-not (Test-Path $UpstreamPath)) { exit 1 }

$ManifestData = Get-Content $UpstreamPath -Raw | ConvertFrom-Json
$HostedManifestData = if (Test-Path $HostedPath) { Get-Content $HostedPath -Raw | ConvertFrom-Json } else { $null }

$ChangesDetected = $false
$UpdatedList = [System.Collections.Generic.List[String]]::new()

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "       Scanning Repositories for Payload Updates    " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

for ($i = 0; $i -lt $ManifestData.payloads.Count; $i++) {
    $Payload = $ManifestData.payloads[$i]
    
    if (-not (Get-Member -InputObject $Payload -Name "hosted_url")) { Add-Member -InputObject $Payload -NotePropertyName "hosted_url" -NotePropertyValue "" }
    if (-not (Get-Member -InputObject $Payload -Name "checksum")) { Add-Member -InputObject $Payload -NotePropertyName "checksum" -NotePropertyValue "" }
    if (-not (Get-Member -InputObject $Payload -Name "version")) { Add-Member -InputObject $Payload -NotePropertyName "version" -NotePropertyValue "" }
    if (-not (Get-Member -InputObject $Payload -Name "last_update")) { Add-Member -InputObject $Payload -NotePropertyName "last_update" -NotePropertyValue "" }
    if (-not (Get-Member -InputObject $Payload -Name "channel")) { Add-Member -InputObject $Payload -NotePropertyName "channel" -NotePropertyValue "stable" }

    if ($Payload.source -and ($Payload.source -match "github\.com/([^/]+)/([^/]+?)(?:/|$|$)") -and (-not ($Payload.source -match "tree/main"))) {
        $Owner = $Matches[1]
        $Repo = $Matches[2].Replace(".git","")
        if ($Repo -match "\.github\.io") { continue }
        
        $LatestVersion = $null
        $DownloadUrl = $null
        $OriginalExt = [System.IO.Path]::GetExtension($Payload.filename)
        if (-not $OriginalExt) { $OriginalExt = ".elf" }

        try {
            $Release = Get-GitHubReleaseByChannel -Owner $Owner -Repo $Repo -Channel $Payload.channel -Headers $Headers
            if ($Release) {
                $LatestVersion = $Release.tag_name
                $Asset = $Release.assets | Where-Object { $_.name -like "*.elf" -or $_.name -like "*.bin" -or $_.name -like "*.zip" } | Select-Object -First 1
                if ($Asset) { $DownloadUrl = $Asset.browser_download_url } else { $DownloadUrl = $Release.zipball_url; $OriginalExt = ".zip" }
            }

            if (-not $DownloadUrl) {
                Write-Warning "[SKIP] No valid binary download asset found for $($Payload.name)"
                continue
            }

            $SanitizedVersion = ($LatestVersion -replace '^v', '') -replace '[\\/]', '-'
            $TargetFilename = "$($Payload.name)_v${SanitizedVersion}${OriginalExt}"
            $TargetFilePath = Join-Path $PayloadsDir $TargetFilename

            if (($LatestVersion -and ($LatestVersion -ne $Payload.version)) -or (-not (Test-Path $TargetFilePath))) {
                Write-Host "[FETCH] Downloading $($Payload.name) ($LatestVersion)..." -ForegroundColor Yellow
                
                $TempDownloadPath = Join-Path $PayloadsDir "temp_$TargetFilename"
                Invoke-RestMethod -Uri $DownloadUrl -OutFile $TempDownloadPath -ErrorAction Stop
                
                # Recursive Archive Inspection & Extraction
                if ($DownloadUrl.EndsWith(".zip") -or $OriginalExt -eq ".zip" -or $TempDownloadPath.EndsWith(".zip")) {
                    $ExtractDir = Join-Path $PayloadsDir "temp_extract"
                    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
                    
                    Expand-Archive -Path $TempDownloadPath -DestinationPath $ExtractDir -Force -WarningAction SilentlyContinue | Out-Null
                    
                    # Search recursively inside ZIP folders for .elf or .bin files
                    $ExtractedBinary = Get-ChildItem -Path $ExtractDir -Recurse | Where-Object { $_.Extension -eq ".elf" -or $_.Extension -eq ".bin" } | Select-Object -First 1
                    
                    if ($ExtractedBinary) {
                        $OriginalExt = $ExtractedBinary.Extension
                        $TargetFilename = "$($Payload.name)_v${SanitizedVersion}${OriginalExt}"
                        $TargetFilePath = Join-Path $PayloadsDir $TargetFilename
                        Move-Item -Path $ExtractedBinary.FullName -Destination $TargetFilePath -Force
                    } else {
                        Write-Warning "  └─ [SKIP] ZIP extracted for $($Payload.name) but contains no payload binary (.elf/.bin)."
                        if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
                        if (Test-Path $TempDownloadPath) { Remove-Item $TempDownloadPath -Force }
                        continue
                    }
                    
                    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
                    if (Test-Path $TempDownloadPath) { Remove-Item $TempDownloadPath -Force }
                } else {
                    Move-Item -Path $TempDownloadPath -Destination $TargetFilePath -Force
                }

                # Verify file existence before reading header / hashing
                if (-not (Test-Path $TargetFilePath)) {
                    Write-Warning "  └─ [ERROR] Target binary missing after processing $($Payload.name)."
                    continue
                }

                # Integrity Check: ELF 4-Byte Magic Bytes Validation
                if ($OriginalExt -eq ".elf") {
                    $Bytes = New-Object Byte[] 4
                    $Stream = [System.IO.File]::OpenRead($TargetFilePath)
                    [void]$Stream.Read($Bytes, 0, 4)
                    $Stream.Close()
                    
                    if (([System.BitConverter]::ToString($Bytes)) -ne "7F-45-4C-46") {
                        Remove-Item $TargetFilePath -Force -ErrorAction SilentlyContinue
                        Write-Warning "  └─ [REJECTED] Invalid ELF header for $($Payload.name)"
                        continue
                    }
                }

                # Purge Stale Version Files
                $OldFiles = Get-ChildItem -Path $PayloadsDir | Where-Object { $_.Name -like "$($Payload.name)_v*" -and $_.FullName -ne $TargetFilePath }
                foreach ($OldFile in $OldFiles) {
                    Remove-Item $OldFile.FullName -Force -ErrorAction SilentlyContinue
                }

                $NewHash = (Get-FileHash $TargetFilePath -Algorithm SHA256).Hash.ToLower()
                $HostedUrl = "https://raw.githubusercontent.com/${GH_USER}/${GH_REPO}/${GH_BRANCH}/payloads/$TargetFilename"
                
                $Payload.version = $LatestVersion
                $Payload.filename = $TargetFilename
                
                if ($Payload.url -is [System.Array]) {
                    $Payload.url = @($DownloadUrl, $HostedUrl)
                } else {
                    $Payload.url = $DownloadUrl
                }
                
                $Payload.hosted_url = $HostedUrl
                $Payload.checksum = $NewHash
                $Payload.last_update = $Today
                
                if ($HostedManifestData) {
                    $HostedPayload = $HostedManifestData.payloads | Where-Object { $_.name -eq $Payload.name }
                    if ($HostedPayload) {
                        if (-not (Get-Member -InputObject $HostedPayload -Name "checksum")) { Add-Member -InputObject $HostedPayload -NotePropertyName "checksum" -NotePropertyValue "" }
                        if (-not (Get-Member -InputObject $HostedPayload -Name "version")) { Add-Member -InputObject $HostedPayload -NotePropertyName "version" -NotePropertyValue "" }
                        if (-not (Get-Member -InputObject $HostedPayload -Name "last_update")) { Add-Member -InputObject $HostedPayload -NotePropertyName "last_update" -NotePropertyValue "" }

                        $HostedPayload.version = $LatestVersion
                        $HostedPayload.filename = $TargetFilename
                        if ($HostedPayload.url -is [System.Array]) {
                            $HostedPayload.url = @($HostedUrl, $DownloadUrl)
                        } else {
                            $HostedPayload.url = $HostedUrl
                        }
                        $HostedPayload.checksum = $NewHash
                        $HostedPayload.last_update = $Today
                    }
                }
                
                $ChangesDetected = $true
                $UpdatedList.Add("$($Payload.name) -> $TargetFilename")
                Write-Host "  └─ [SUCCESS] Processed & SHA256 Hashed: $NewHash" -ForegroundColor Green
            } else {
                Write-Host "[OK] $($Payload.name) is up to date ($($Payload.version))." -ForegroundColor Gray
            }
        } catch {
            Write-Warning "[ERROR] Failed processing $($Payload.name): $($_.Exception.Message)"
        }
    }
}

if ($ChangesDetected) {
    # Save Main Manifest
    $CleanPayloads = [System.Collections.Generic.List[Object]]::new()
    foreach ($p in $ManifestData.payloads) {
        $CleanPayloads.Add([ordered]@{
            name        = $p.name
            category    = if (Get-Member -InputObject $p -Name "category") { $p.category } else { "Tools" }
            filename    = if (Get-Member -InputObject $p -Name "filename") { $p.filename } else { "" }
            url         = if (Get-Member -InputObject $p -Name "url") { $p.url } else { "" }
            hosted_url  = if (Get-Member -InputObject $p -Name "hosted_url") { $p.hosted_url } else { "" }
            source      = $p.source
            description = if (Get-Member -InputObject $p -Name "description") { $p.description } else { "" }
            last_update = if (Get-Member -InputObject $p -Name "last_update") { $p.last_update } else { "" }
            version     = if (Get-Member -InputObject $p -Name "version") { $p.version } else { "" }
            checksum    = if (Get-Member -InputObject $p -Name "checksum") { $p.checksum } else { "" }
        })
    }
    ConvertTo-CleanJson ([ordered]@{ name = $ManifestData.name; payloads = $CleanPayloads }) | Set-Content $UpstreamPath -Encoding UTF8

    # Save Hosted Manifest
    if ($HostedManifestData) {
        $CleanHostedPayloads = [System.Collections.Generic.List[Object]]::new()
        foreach ($hp in $HostedManifestData.payloads) {
            $CleanHostedPayloads.Add([ordered]@{
                name        = $hp.name
                category    = if (Get-Member -InputObject $hp -Name "category") { $hp.category } else { "Tools" }
                filename    = if (Get-Member -InputObject $hp -Name "filename") { $hp.filename } else { "" }
                url         = if (Get-Member -InputObject $hp -Name "url") { $hp.url } else { "" }
                source      = $hp.source
                description = if (Get-Member -InputObject $hp -Name "description") { $hp.description } else { "" }
                last_update = if (Get-Member -InputObject $hp -Name "last_update") { $hp.last_update } else { "" }
                version     = if (Get-Member -InputObject $hp -Name "version") { $hp.version } else { "" }
                checksum    = if (Get-Member -InputObject $hp -Name "checksum") { $hp.checksum } else { "" }
            })
        }
        ConvertTo-CleanJson ([ordered]@{ name = $HostedManifestData.name; payloads = $CleanHostedPayloads }) | Set-Content $HostedPath -Encoding UTF8
    }

    Write-Host "`n====================================================" -ForegroundColor Green
    Write-Host " Local Workspace Cleaned & Updated! Run Push_to_GitHub.bat " -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
} else {
    Write-Host "`n[OK] Local workspace is completely up to date." -ForegroundColor Cyan
}