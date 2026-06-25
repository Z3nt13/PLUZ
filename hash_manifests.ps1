$ScriptDir = $PSScriptRoot
$PayloadsDir = Join-Path $ScriptDir "payloads"

Write-Host "[ENGINE] Executing localized verification hash mapping matrix..." -ForegroundColor Cyan

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

foreach ($JsonFile in @("Z3nT1s-PLUZ.json", "Z3nT1s-Hosted-PLUZ.json")) {
    $ManifestPath = Join-Path $ScriptDir $JsonFile
    if (Test-Path $ManifestPath) {
        $Data = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        
        foreach ($Payload in $Data.payloads) {
            if ($Payload.filename -eq "KstuffLite_vB.1.07.elf") { $Payload.filename = "KstuffLite_v1.07B.elf" }
            $TargetBinary = Join-Path $PayloadsDir $Payload.filename
            
            if (-not (Test-Path $TargetBinary) -and ($Payload.filename -eq "KstuffLite_v1.07B.elf")) {
                $FallbackBinary = Join-Path $PayloadsDir "KstuffLite_vB.1.07.elf"
                if (Test-Path $FallbackBinary) { Rename-Item -Path $FallbackBinary -NewName "KstuffLite_v1.07B.elf" -Force }
            }

            if (Test-Path $TargetBinary) {
                $HashValue = (Get-FileHash $TargetBinary -Algorithm SHA256).Hash.ToLower()
                $Payload.checksum = $HashValue
            }
        }
        
        # Build strict ordered re-serialization
        $OrderedPayloads = @()
        foreach ($p in $Data.payloads) {
            $OrderedPayloads += [ordered]@{
                name = $p.name
                filename = $p.filename
                url = $p.url
                source = $p.source
                description = $p.description
                last_update = $p.last_update
                version = $p.version
                checksum = $p.checksum
            }
        }
        $OutputData = [ordered]@{ name = $Data.name; payloads = $OrderedPayloads }
        ConvertTo-CleanJson $OutputData | Set-Content $ManifestPath -Encoding UTF8
        Write-Host "  [SUCCESS] Sorted fields and updated signatures for $JsonFile" -ForegroundColor Green
    }
}
