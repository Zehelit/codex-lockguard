#requires -Version 5.1
param([string]$ExpectedUserSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),[switch]$Elevate)
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -ne $ExpectedUserSid){throw 'Wrong Windows user'}
if($Elevate -and -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){
    $literal="'"+$PSCommandPath.Replace("'","''")+"'"
    $command='& '+$literal+' -ExpectedUserSid '''+$sid+''''
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    exit $process.ExitCode
}
if(-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){throw 'Run this uninstaller with Windows administrator approval.'}
$scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\');$name='CodexLockGuard-'+$sid
$task=@($folder.GetTasks(1)|Where-Object {$_.Name -eq $name})|Select-Object -First 1
if(-not $task){throw 'Ana görev bulunamadı. Elle başlatılmış süreç/yedek için README kurtarma bölümünü izleyin.'}
$principalUser=$task.Definition.Principal.UserId
$principalSid=if($principalUser -match '^S-1-'){$principalUser}else{([Security.Principal.NTAccount]::new($principalUser)).Translate([Security.Principal.SecurityIdentifier]).Value}
if($task.Definition.RegistrationInfo.Description -notlike 'CodexLockGuard owned application lifecycle integration*' -or $principalSid -ne $sid){throw 'Refusing to remove an unrelated task'}
$task.Enabled=$false
$identityName='CodexLockGuard-Identity-'+$sid
$identityTask=@($folder.GetTasks(1)|Where-Object {$_.Name -eq $identityName})|Select-Object -First 1
if($identityTask){
    if($identityTask.Definition.RegistrationInfo.Description -notlike 'CodexLockGuard owned identity-change notification*'){throw 'Refusing to remove unrelated identity notification task'}
    $identityTask.Enabled=$false
    $folder.DeleteTask($identityName,0)
}
$guardFile=Join-Path $env:ProgramFiles 'CodexLockGuard\Codex-LockGuard.ps1'
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $guardFile -Mode Stop
if($LASTEXITCODE -ne 0){throw 'Restoration failed; task remains disabled and backup is retained'}
$statusOutput=& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $guardFile -Mode Status
if($LASTEXITCODE -ne 0){throw 'Cannot verify restoration; task remains disabled.'}
$status=($statusOutput -join [Environment]::NewLine)|ConvertFrom-Json
if($status.Running -or $status.Backup){throw 'Restoration pending; tasks remain disabled and backup is retained. Unlock Windows and retry.'}
$folder.DeleteTask($name,0)
$manifest=Join-Path $env:LOCALAPPDATA 'CodexLockGuard\installation.json'
if([IO.File]::Exists($manifest)){[IO.File]::Delete($manifest)}
[pscustomobject]@{RemovedTask=$name;SettingsRestored=$true;InstalledFilesRetained=(Split-Path $guardFile)}|ConvertTo-Json
