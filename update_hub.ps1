$ScriptDir = $PSScriptRoot
$PayloadsDir = Join-Path $ScriptDir "payloads"
$Today = (Get-Date).ToString("dd.MM.yyyy")

if (-not (Test-Path $PayloadsDir)) { New-Item -ItemType Directory $PayloadsDir | Out-Null }

$Headers = @{}
if ($env:GITHUB_TOKEN) { $Headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

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

$UpstreamPath = Join-Path $ScriptDir "Z3nT1s-PLUZ.json"
if (-not (Test-Path $UpstreamPath)) { exit 1 }

$ManifestData = Get-Content $UpstreamPath -Raw | ConvertFrom-Json
$ChangesDetected = $false

for ($i = 0; $i -lt $ManifestData.payloads.Count; $i++) {
    $Payload = $ManifestData.payloads[$i]
    
    if ($Payload.source -and ($Payload.source -match "github\.com/([^/]+)/([^/]+?)(?:/|$|$)") -and (-not ($Payload.source -match "tree/main"))) {
        $Owner = $Matches[1]
        $Repo = $Matches[2].Replace(".git","")
        if ($Repo -match "\.github\.io") { continue }
        
        $ApiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
        try {
            $Release = Invoke-RestMethod -Uri $ApiUrl -Headers $Headers -Method Get -ErrorAction Stop
            $LatestVersion = $Release.tag_name
            
            if ($LatestVersion -and ($LatestVersion -ne $Payload.version)) {
                $OriginalExt = [System.IO.Path]::GetExtension($Payload.filename)
                if (-not $OriginalExt) { $OriginalExt = ".elf" }
                
                $Asset = $Release.assets | Where-Object { $_.name -like "*$OriginalExt" } | Select-Object -First 1
                
                if ($Asset) {
                    # Smart Naming Constraint Core
                    $CleanVer = $LatestVersion -replace '^v', ''
                    $NormalizedBase = $Payload.name
                    $TargetFilename = "${NormalizedBase}_v${CleanVer}${OriginalExt}"
                    $TargetFilePath = Join-Path $PayloadsDir $TargetFilename
                    
                    # Run Content Download Core
                    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $TargetFilePath -ErrorAction Stop
                    $NewHash = (Get-FileHash $TargetFilePath -Algorithm SHA256).Hash.ToLower()
                    
                    # Manage Multi-Version Retention Buffer (Max 2 builds allowed per payload identity)
                    $ExistingFiles = Get-ChildItem -Path $PayloadsDir -Filter "${NormalizedBase}_v*${OriginalExt}" | 
                                     Sort-Object LastWriteTime
                    
                    if ($ExistingFiles.Count -gt 2) {
                        for ($j = 0; $j -lt ($ExistingFiles.Count - 2); $j++) {
                            Remove-Item $ExistingFiles[$j].FullName -Force -ErrorAction SilentlyContinue
                        }
                    }
                    
                    # Update Mapping Metadata Arrays
                    $Payload.version = $LatestVersion
                    $Payload.filename = $TargetFilename
                    $Payload.url = $Asset.browser_download_url
                    $Payload.hosted_url = "https://raw.githubusercontent.com/Z3nt13/PLUZ/main/payloads/$TargetFilename"
                    $Payload.checksum = $NewHash
                    $Payload.last_update = $Today
                    
                    $ChangesDetected = $true
                }
            }
        } catch {
            Write-Warning "Skipped compilation processing error on tracking profile: $($Payload.name)"
        }
    }
}

if ($ChangesDetected) {
    $CleanPayloads = [System.Collections.Generic.List[Object]]::new()
    foreach ($p in $ManifestData.payloads) {
        $CleanPayloads.Add([ordered]@{
            name        = $p.name
            filename    = $p.filename
            url         = $p.url
            hosted_url  = $p.hosted_url
            source      = $p.source
            description = $p.description
            last_update = $p.last_update
            version     = $p.version
            checksum    = $p.checksum
        })
    }
    
    $FinalManifest = [ordered]@{
        name     = $ManifestData.name
        payloads = $CleanPayloads
    }
    
    ConvertTo-CleanJson $FinalManifest | Set-Content $UpstreamPath -Encoding UTF8
}