#requires -Version 5.1
[CmdletBinding()]
param([string]$ExpectedUserSid='',[switch]$LibraryOnly,[switch]$NoPopup,[switch]$DemoWarning,[string[]]$ExpectedApplicationId=@())
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:IdentityExpected=@('OpenAI.Codex_2p2nqsd0c76g0!App','OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT')
# Known duplicate Start-menu alias; it is not accepted as a target process.
$script:IdentityAliases=@('com.openai.codex')
function Get-IdentityAssessment([object[]]$Entries,[string[]]$Required=$ExpectedApplicationId) {
    $issues=[Collections.Generic.List[string]]::new()
    $ids=@($Entries|ForEach-Object{[string]$_.AppID})
    $knownInstalled=@($script:IdentityExpected|Where-Object {$ids -contains $_})
    if($Required.Count -eq 0 -and $knownInstalled.Count -eq 0){$issues.Add('Desteklenen Codex veya ChatGPT uygulama kimliği bulunamadı.')}
    foreach($expected in $Required){
        if($ids -notcontains $expected){$issues.Add('Beklenen uygulama kimliği bulunamadı: '+$expected)}
    }
    foreach($entry in $Entries){
        if(([string]$entry.Name -match '(?i)\b(ChatGPT|Codex)\b' -or [string]$entry.AppID -match '(?i)^OpenAI\.(Codex|ChatGPT)') -and
            $script:IdentityExpected -notcontains [string]$entry.AppID -and $script:IdentityAliases -notcontains [string]$entry.AppID){
            $issues.Add('Yeni veya tanınmayan uygulama kimliği: '+$entry.Name+' — '+$entry.AppID)
        }
    }
    [pscustomobject]@{Healthy=($issues.Count -eq 0);Issues=@($issues);Expected=$script:IdentityExpected;KnownAliases=$script:IdentityAliases}
}
function Show-IdentityAlert([string]$Text,[bool]$Demo=$false) {
    $title=if($Demo){'Codex kilit koruması — UYARI GÖRÜNÜRLÜK TESTİ'}else{'Codex / ChatGPT — Kilit koruması kontrol edilmeli'}
    $helper=Join-Path $PSScriptRoot 'IdentityAlert.exe'
    if(-not [IO.File]::Exists($helper)){throw 'IdentityAlert.exe is missing; warning state retained for retry.'}
    $arguments=@([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Text)),[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($title)))
    # This is the visible warning explicitly requested by the user. It is a GUI
    # executable with no console and displays no authentication or settings UI.
    $process=Start-Process -FilePath $helper -ArgumentList $arguments -WindowStyle Normal -PassThru
    try{$process.WaitForExit();if($process.ExitCode -ne 0){throw ('Warning GUI failed: '+$process.ExitCode)}}finally{$process.Dispose()}
}
function Write-IdentityState([string]$Path,$Value) {
    $temporary=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
    } finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
if($LibraryOnly){return}
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSid -and $ExpectedUserSid -ne $sid){throw 'Wrong Windows user; identity check refused.'}
if($DemoWarning){
    Show-IdentityAlert "BU BİR GÖRÜNÜRLÜK TESTİDİR.`r`n`r`nŞu anda uygulama kimliği değiştiği iddia edilmiyor.`r`n`r`nGerçek bir değişiklik saptanırsa bu pencerede hangi kimliğin bulunamadığı ve kilit korumasının hangi nedenle doğrulanamadığı yazacak." $true
    return
}
$stateDir=Join-Path $env:LOCALAPPDATA 'CodexLockGuard'
$null=[IO.Directory]::CreateDirectory($stateDir)
$statusFile=Join-Path $stateDir 'identity-status.json'
$installationFile=Join-Path $stateDir 'installation.json'
if($ExpectedApplicationId.Count -eq 0 -and [IO.File]::Exists($installationFile)){
    $installation=Get-Content -Raw -LiteralPath $installationFile|ConvertFrom-Json
    if($installation.PSObject.Properties['ExpectedApplicationIds']){$ExpectedApplicationId=@($installation.ExpectedApplicationIds)}
}
$previous=$null
if([IO.File]::Exists($statusFile)){try{$previous=Get-Content -Raw -LiteralPath $statusFile|ConvertFrom-Json}catch{}}
try {
    $assessment=Get-IdentityAssessment @(Get-StartApps)
    if(-not $assessment.Healthy){
        # Start menu registration may briefly lag package activation/update.
        Start-Sleep -Seconds 3
        $assessment=Get-IdentityAssessment @(Get-StartApps)
    }
} catch {$assessment=[pscustomobject]@{Healthy=$false;Issues=@('Uygulama kimliği denetimi tamamlanamadı: '+$_.Exception.Message);Expected=$script:IdentityExpected;KnownAliases=$script:IdentityAliases}}
$signature=if($assessment.Healthy){''}else{(@($assessment.Issues)|Sort-Object) -join "`n"}
$alreadyShown=$previous -and $previous.Signature -eq $signature -and $previous.AcknowledgedAt
$record=[pscustomobject]@{CheckedAt=[DateTimeOffset]::Now.ToString('o');UserSid=$sid;Healthy=$assessment.Healthy;Issues=@($assessment.Issues);Signature=$signature;WarningRequested=[bool]$alreadyShown;AcknowledgedAt=if($alreadyShown){$previous.AcknowledgedAt}else{$null};Expected=$script:IdentityExpected;KnownAliases=$script:IdentityAliases;DetectionScope='Current-user Start menu AUMIDs, known package/name candidates; no automatic trust of replacements'}
if(-not $assessment.Healthy -and -not $NoPopup -and -not $alreadyShown){$record.WarningRequested=$true}
Write-IdentityState $statusFile $record
if(-not $assessment.Healthy -and -not $NoPopup -and -not $alreadyShown){
    $message="Codex / ChatGPT uygulama tanımı doğrulanamadı.`r`n`r`nUygulama güncellenmiş, kaldırılmış veya kimliği değişmiş olabilir. Otomatik kilit koruması etkilenen uygulama için doğrulanmıyor.`r`n`r`n"+($assessment.Issues -join "`r`n")+"`r`n`r`nCodexLockGuard uygulama tanımını kontrol ettirin. Yeni kimlik otomatik olarak güvenilir kabul edilmedi.`r`n`r`nAyrıntılar: "+$statusFile
    Show-IdentityAlert $message
    $record.AcknowledgedAt=[DateTimeOffset]::Now.ToString('o')
    Write-IdentityState $statusFile $record
}
$record|ConvertTo-Json -Depth 6
