#requires -Version 5.1
[CmdletBinding()]
param([string]$ExpectedUserSid=([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),[ValidateRange(1,60)][int]$PollSeconds=10,[switch]$PrepareOnly,[switch]$Elevate)
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -ne $ExpectedUserSid){throw 'Wrong Windows account; installation refused.'}
if(-not [Environment]::Is64BitProcess){throw '64-bit Windows PowerShell 5.1 is required.'}
if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'Kurulumu Windows PowerShell 5.1 (powershell.exe) ile çalıştırın.'}
if($Elevate -and -not $PrepareOnly -and -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){
    $literal="'"+$PSCommandPath.Replace("'","''")+"'"
    $command='& '+$literal+' -ExpectedUserSid '''+$sid+''' -PollSeconds '+$PollSeconds
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand '+$encoded) -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    exit $process.ExitCode
}
$knownIds=@('OpenAI.Codex_2p2nqsd0c76g0!App','OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT')
$presentIds=@(Get-StartApps|Where-Object {$knownIds -contains $_.AppID}|ForEach-Object {$_.AppID}|Select-Object -Unique)
if($presentIds.Count -eq 0){throw 'Desteklenen paketli Codex veya ChatGPT uygulaması bulunamadı. Uygulamayı kurup bir kez açın.'}
foreach($required in @('Codex-LockGuard.ps1','Check-AppIdentity.ps1','Build-IdentityAlert.ps1','IdentityAlert.cs','Uninstall.ps1','Protection.ps1')){if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $required))){throw ('Eksik kaynak dosyası: '+$required)}}
. (Join-Path $PSScriptRoot 'Protection.ps1')
$taskName='CodexLockGuard-'+$sid
$identityTaskName='CodexLockGuard-Identity-'+$sid
$installRoot=Join-Path $env:ProgramFiles 'CodexLockGuard'
if([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($installRoot).TrimEnd('\')){throw 'Kurulumu Program Files içinden değil, indirilen kaynak klasöründen çalıştırın.'}
$installedScript=Join-Path $installRoot 'Codex-LockGuard.ps1'
$sourceScript=Join-Path $PSScriptRoot 'Codex-LockGuard.ps1'
$shellFile=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$stateRoot=Join-Path $env:LOCALAPPDATA 'CodexLockGuard'
$receiptPath=Join-Path $stateRoot 'install-result.json'
$query="<QueryList><Query Id='0' Path='Microsoft-Windows-AppModel-Runtime/Admin'><Select Path='Microsoft-Windows-AppModel-Runtime/Admin'>*[System[Provider[@Name='Microsoft-Windows-AppModel-Runtime'] and EventID=201]] and *[EventData[Data[@Name='ApplicationName']='OpenAI.Codex_2p2nqsd0c76g0!App' or Data[@Name='ApplicationName']='OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT']]</Select></Query></QueryList>"
$escape={param($v)[Security.SecurityElement]::Escape([string]$v)}
$argsText='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$installedScript+'" -Mode Run -ExitWhenNoTargets -InitialTargetWaitSeconds 15 -RestartGraceSeconds 0 -PollSeconds '+$PollSeconds+' -ExpectedUserSid "'+$sid+'"'
$taskXml=@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>$sid</Author><Description>CodexLockGuard owned application lifecycle integration v2.1. Matches versionless AUMIDs; no credentials stored.</Description></RegistrationInfo>
  <Triggers>
    <EventTrigger><Enabled>true</Enabled><Subscription>$(& $escape $query)</Subscription><Delay>PT1S</Delay></EventTrigger>
    <LogonTrigger><Enabled>true</Enabled><Delay>PT5S</Delay><UserId>$sid</UserId></LogonTrigger>
  </Triggers>
  <Principals><Principal id="GuardUser"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>false</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Priority>7</Priority><RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions Context="GuardUser"><Exec><Command>$(& $escape $shellFile)</Command><Arguments>$(& $escape $argsText)</Arguments><WorkingDirectory>$(& $escape $installRoot)</WorkingDirectory></Exec></Actions>
</Task>
"@
[xml]$null=$taskXml
$identityQuery="<QueryList><Query Id='0' Path='Microsoft-Windows-AppModel-Runtime/Admin'><Select Path='Microsoft-Windows-AppModel-Runtime/Admin'>*[System[Provider[@Name='Microsoft-Windows-AppModel-Runtime'] and EventID=201]]</Select></Query></QueryList>"
$identityArgs='-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $installRoot 'Check-AppIdentity.ps1')+'" -ExpectedUserSid "'+$sid+'"'
[xml]$identityXml=$taskXml
$ns=[Xml.XmlNamespaceManager]::new($identityXml.NameTable);$ns.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
$identityXml.SelectSingleNode('//t:Description',$ns).InnerText='CodexLockGuard owned identity-change notification v2.1. Checks all packaged-app activations so a changed AUMID cannot silently evade its own narrow trigger.'
$identityXml.SelectSingleNode('//t:Subscription',$ns).InnerText=$identityQuery
$identityXml.SelectSingleNode('//t:RunLevel',$ns).InnerText='LeastPrivilege'
$identityXml.SelectSingleNode('//t:Arguments',$ns).InnerText=$identityArgs
$identityXml.SelectSingleNode('//t:AllowHardTerminate',$ns).InnerText='true'
if($PrepareOnly){[pscustomobject]@{Prepared=$true;TaskName=$taskName;InstallPath=$installedScript;ExpectedApplicationIds=$presentIds;PollSeconds=$PollSeconds;TaskXml=$taskXml;IdentityTaskXml=$identityXml.OuterXml}|ConvertTo-Json -Depth 4;return}
if(-not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))){throw 'Windows administrator UAC approval is required to register this elevated task and protect its script.'}
$null=[IO.Directory]::CreateDirectory($stateRoot)
if(([IO.File]::GetAttributes($stateRoot) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'State directory must not be a reparse point.'}
$receipt=[ordered]@{Started=[DateTimeOffset]::Now.ToString('o');Passed=$false;TaskName=$taskName;IdentityTaskName=$identityTaskName;InstalledScript=$installedScript;Checks=@();FullRealAppCloseReopenTested=$false}
$scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\')
$otherGuard=@($folder.GetTasks(1)|Where-Object {$_.Name -like 'CodexLockGuard-S-*' -and $_.Name -ne $taskName})
if($otherGuard.Count -gt 0){throw 'Başka kullanıcı için bir CodexLockGuard görevi mevcut. Paylaşılan kurulum klasörünü değiştirmeden önce çok kullanıcılı kurulumu inceleyin.'}
$priorTask=@($folder.GetTasks(1)|Where-Object {$_.Name -eq $taskName})|Select-Object -First 1
if($priorTask -and $priorTask.Definition.RegistrationInfo.Description -notlike 'CodexLockGuard owned application lifecycle integration*'){throw 'Task name collision: refusing to replace an unrelated task.'}
$oldTaskXml=if($priorTask){$priorTask.Xml}else{$null}
$oldTaskSddl=if($priorTask){$priorTask.GetSecurityDescriptor(4)}else{$null}
$priorIdentityTask=@($folder.GetTasks(1)|Where-Object {$_.Name -eq $identityTaskName})|Select-Object -First 1
if($priorIdentityTask -and $priorIdentityTask.Definition.RegistrationInfo.Description -notlike 'CodexLockGuard owned identity-change notification*'){throw 'Identity task name collision'}
$oldIdentityXml=if($priorIdentityTask){$priorIdentityTask.Xml}else{$null}
$oldIdentitySddl=if($priorIdentityTask){$priorIdentityTask.GetSecurityDescriptor(4)}else{$null}
$newRegistered=$false
$identityRegistered=$false
$filesChanged=$false
$backupRoot=$null
$oldManifest=$null
$manifestPath=Join-Path $stateRoot 'installation.json'
if(Test-Path -LiteralPath $manifestPath){$oldManifest=[IO.File]::ReadAllText($manifestPath)}
$ownedFiles=@('Codex-LockGuard.ps1','Check-AppIdentity.ps1','Uninstall.ps1','Build-IdentityAlert.ps1','IdentityAlert.cs','Protection.ps1','IdentityAlert.exe')
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('Assertion failed: '+$Name)};$receipt.Checks+=@($Name)}
function Resolve-UserSid([string]$Identity){if($Identity -match '^S-1-'){return $Identity};([Security.Principal.NTAccount]::new($Identity)).Translate([Security.Principal.SecurityIdentifier]).Value}
function Guard-Command([string]$File,[string]$Mode){$output=& $shellFile -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $File -Mode $Mode;if($LASTEXITCODE -ne 0){throw ('Guard command failed: '+$Mode)};($output -join [Environment]::NewLine)|ConvertFrom-Json}
try {
    Assert ((Get-WinEvent -ListLog 'Microsoft-Windows-AppModel-Runtime/Admin').IsEnabled) 'App activation event channel is enabled'
    # No simulated target transitions or destructive behavioral tests during install.
    if(-not [IO.Directory]::Exists($installRoot)){$null=[IO.Directory]::CreateDirectory($installRoot)}
    Assert (([IO.File]::GetAttributes($installRoot) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Install directory is not a junction/reparse point'
    $acl=Get-Acl -LiteralPath $installRoot
    $receipt.InstallDirectoryAcl=$acl.Sddl
    # A fixed protected script is important: do not give a normal user a writable
    # arbitrary command behind a task that already has administrator approval.
    # Read raw SIDs directly. Inherited/retired account entries need not be
    # resolvable to localized account names for their permissions to be audited.
    $sidRules=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $unsafe=@(Get-UnsafeWriteRules $sidRules)
    Assert ($unsafe.Count -eq 0) 'Installed code is not writable by broad unprivileged groups'
    $backupRoot=Join-Path $installRoot ('.rollback-'+[Guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($backupRoot)
    foreach($name in $ownedFiles){$path=Join-Path $installRoot $name;if(Test-Path -LiteralPath $path){if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Installed file must not be a reparse point.'};$fileAcl=Get-Acl -LiteralPath $path;$unsafeFile=@(Get-UnsafeWriteRules ($fileAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])));if($unsafeFile.Count){throw ('Unsafe writable installed file: '+$name)};Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot $name)}}
    if($priorTask){$priorTask.Enabled=$false}
    if($priorIdentityTask){$priorIdentityTask.Enabled=$false}
    $null=Guard-Command $sourceScript Stop
    $stopped=Guard-Command $sourceScript Status
    if($stopped.Running -or $stopped.Backup){throw 'Önceki ayarların geri yüklenmesi tamamlanmadı. Kilidi açın ve kurulumu yeniden deneyin.'}
    $filesChanged=$true
    foreach($name in $ownedFiles|Where-Object {$_ -ne 'IdentityAlert.exe'}){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $installRoot $name) -Force}
    & $shellFile -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $installRoot 'Build-IdentityAlert.ps1')|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Notification helper build failed.'}
    foreach($name in $ownedFiles|Where-Object {$_ -ne 'IdentityAlert.exe'}){Assert ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $installRoot $name)).Hash) ('Installed source matches: '+$name)}
    [pscustomobject]@{TaskName=$taskName;IdentityTaskName=$identityTaskName;InstalledScript=$installedScript;SourceHash=(Get-FileHash -LiteralPath $sourceScript).Hash;UserSid=$sid;LifecycleVersion='2.1';PollSeconds=$PollSeconds;ExpectedApplicationIds=$presentIds}|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8
    $definition=$scheduler.NewTask(0);$definition.XmlText=$taskXml
    # The current user may start/read the fixed task; only administrators/SYSTEM may modify it.
    $sddl='D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGX;;;'+$sid+')'
    $registered=$folder.RegisterTaskDefinition($taskName,$definition,6,$sid,$null,3,$sddl)
    $newRegistered=$true
    Assert ((Resolve-UserSid $registered.Definition.Principal.UserId) -eq $sid -and $registered.Definition.Principal.RunLevel -eq 1) 'Task uses the intended interactive user at highest available privilege'
    Assert ($registered.Definition.Triggers.Count -eq 2 -and $registered.Definition.Settings.MultipleInstances -eq 2) 'Event/logon triggers and duplicate suppression are registered'
    $idDefinition=$scheduler.NewTask(0);$idDefinition.XmlText=$identityXml.OuterXml
    $identityTask=$folder.RegisterTaskDefinition($identityTaskName,$idDefinition,6,$sid,$null,3,$sddl)
    $identityRegistered=$true
    Assert ($identityTask.Definition.Principal.RunLevel -eq 0 -and $identityTask.Definition.Triggers.Item(1).Subscription -eq $identityQuery) 'Independent identity-change detector runs without administrator rights on broad app activation events'
    $null=$identityTask.Run($null)
    $null=$registered.Run($null)
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    do{Start-Sleep -Milliseconds 250;$status=Guard-Command $installedScript Status}until(($status.Running -and $status.Controller.ScriptFile -eq $installedScript -and $status.LastControllerObservation -and $status.LastControllerObservation.ReportingProcessId -eq $status.Controller.ProcessId -and $status.LastControllerObservation.WindowsAdministrator -and ($status.Targets.Count -eq 0 -or $status.Health.ConfigurationMatches)) -or [DateTime]::UtcNow -gt $deadline)
    $receipt.FinalStatus=$status
    Assert ($status.Running -and $status.Controller.ExitWhenNoTargets -and $status.Controller.ScriptFile -eq $installedScript) 'Scheduled task starts installed guard in application-lifetime mode'
    Assert ($status.LastControllerObservation.WindowsAdministrator -and ($status.Targets.Count -eq 0 -or $status.Health.ConfigurationMatches)) 'Scheduled guard has administrator rights; settings verify when target is running'
    $receipt.SourceHash=(Get-FileHash -LiteralPath $sourceScript).Hash
    $receipt.TaskXml=$registered.Xml
    $receipt.FinalStatus=$status
    $receipt.Passed=$true
} catch {
    $receipt.Error=$_.Exception.ToString()
    try {
        if($identityRegistered){$identityTask.Enabled=$false}
        if($newRegistered){$registered.Enabled=$false}
        if($filesChanged){$null=Guard-Command $installedScript Stop;foreach($name in $ownedFiles){$saved=Join-Path $backupRoot $name;$dest=Join-Path $installRoot $name;if(Test-Path -LiteralPath $saved){Copy-Item -LiteralPath $saved -Destination $dest -Force}elseif(Test-Path -LiteralPath $dest){[IO.File]::Delete($dest)}}}
        if($oldManifest){[IO.File]::WriteAllText($manifestPath,$oldManifest)}elseif(Test-Path -LiteralPath $manifestPath){[IO.File]::Delete($manifestPath)}
        if($oldIdentityXml){$null=$folder.RegisterTask($identityTaskName,$oldIdentityXml,6,$sid,$null,3,$oldIdentitySddl)}elseif($identityRegistered){$folder.DeleteTask($identityTaskName,0)}
        if($oldTaskXml){$restored=$folder.RegisterTask($taskName,$oldTaskXml,6,$sid,$null,3,$oldTaskSddl);$null=$restored.Run($null)}elseif($newRegistered){$folder.DeleteTask($taskName,0)}
    } catch {$receipt.RollbackError=$_.Exception.ToString()}
    throw
} finally {$receipt.Completed=[DateTimeOffset]::Now.ToString('o');$receipt|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $receiptPath -Encoding utf8}
$receipt|ConvertTo-Json -Depth 15
