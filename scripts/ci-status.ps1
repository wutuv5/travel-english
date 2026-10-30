param([long]$RunId = 0, [switch]$Download, [switch]$Dispatch)
$ErrorActionPreference = 'Stop'
# Credentials stay in memory and are never printed or persisted.
$credentialLines = "protocol=https`nhost=github.com`n`n" | git -c http.https://github.com.proxy= credential fill
$credentialMap = @{}
foreach ($entry in $credentialLines) {
    $pair = $entry -split '=', 2
    if ($pair.Length -eq 2) { $credentialMap[$pair[0]] = $pair[1] }
}
if (!$credentialMap['password']) { throw 'No GitHub credential available' }
$requestHeaders = @{
    Authorization = "Bearer $($credentialMap['password'])"
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}
$repoApi = 'https://api.github.com/repos/wutuv5/travel-english'
if ($Dispatch) {
    Invoke-RestMethod -Method Post -Uri "$repoApi/actions/workflows/ios-validation.yml/dispatches" -Headers $requestHeaders -Body '{"ref":"main"}' -ContentType 'application/json'
    Write-Output 'Workflow dispatch submitted'
}
if ($RunId -eq 0) {
    $latest = Invoke-RestMethod "$repoApi/actions/workflows/ios-validation.yml/runs?per_page=1" -Headers $requestHeaders
    if (!$latest.workflow_runs) { throw 'No workflow runs found' }
    $RunId = $latest.workflow_runs[0].id
}
if ($RunId -lt 1) { throw 'Invalid run ID' }
$run = Invoke-RestMethod "$repoApi/actions/runs/$RunId" -Headers $requestHeaders
$jobs = Invoke-RestMethod "$repoApi/actions/runs/$RunId/jobs" -Headers $requestHeaders
$run | Select-Object id, status, conclusion, html_url | ConvertTo-Json -Compress
foreach ($job in $jobs.jobs) {
    $job | Select-Object id, name, status, conclusion | ConvertTo-Json -Compress
    $job.steps | Select-Object name, status, conclusion | ConvertTo-Json -Compress
    if ($job.conclusion -eq 'failure') {
        $checkId = ($job.check_run_url -split '/')[-1]
        $annotations = Invoke-RestMethod "$repoApi/check-runs/$checkId/annotations" -Headers $requestHeaders
        $annotations | Select-Object path, start_line, message | ConvertTo-Json -Compress
    }
}
if ($run.status -eq 'completed') {
    $artifacts = Invoke-RestMethod "$repoApi/actions/runs/$RunId/artifacts" -Headers $requestHeaders
    $artifacts.artifacts | Select-Object id, name, size_in_bytes, expired | ConvertTo-Json -Compress
    if ($Download) {
        $targetDir = Join-Path $PSScriptRoot "../build/runs/$RunId"
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        foreach ($artifact in $artifacts.artifacts) {
            if ($artifact.expired) { continue }
            $archivePath = Join-Path $targetDir "$($artifact.id).zip"
            Invoke-WebRequest "$repoApi/actions/artifacts/$($artifact.id)/zip" -Headers $requestHeaders -OutFile $archivePath
            $extractPath = Join-Path $targetDir "$($artifact.id)"
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
            foreach ($ipa in (Get-ChildItem -LiteralPath $extractPath -Filter '*.ipa')) {
                $expected = ((Get-Content -LiteralPath "$($ipa.FullName).sha256").Trim() -split '\s+')[0]
                $actual = (Get-FileHash -LiteralPath $ipa.FullName -Algorithm SHA256).Hash
                if ($expected -ne $actual) { throw 'IPA checksum mismatch' }
                Write-Output "Verified IPA: $($ipa.FullName)"
                Write-Output "SHA256: $actual"
            }
        }
    }
}
