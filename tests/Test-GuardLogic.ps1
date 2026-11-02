#requires -Version 5.1
[CmdletBinding()]
param([switch]$ReadOnlyNative)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$checks=[Collections.Generic.List[string]]::new()
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('Kontrol başarısız: '+$Name)};$checks.Add($Name)}
Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens=$null;$parseErrors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) ('Sözdizimi: '+$_.Name)
}
. (Join-Path $root 'Check-AppIdentity.ps1') -LibraryOnly
$codex=[pscustomobject]@{Name='Codex';AppID='OpenAI.Codex_2p2nqsd0c76g0!App'}
$chatgpt=[pscustomobject]@{Name='ChatGPT';AppID='OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT'}
Assert (Get-IdentityAssessment @($codex)).Healthy 'Yalnız Codex kurulu olabilir'
Assert (Get-IdentityAssessment @($chatgpt)).Healthy 'Yalnız ChatGPT kurulu olabilir'
Assert (Get-IdentityAssessment @($codex,$chatgpt)).Healthy 'İki desteklenen uygulama birlikte tanınır'
Assert (-not (Get-IdentityAssessment @()).Healthy) 'Boş envanter sağlıklı sayılmaz'
Assert (-not (Get-IdentityAssessment @($codex) @($chatgpt.AppID)).Healthy) 'Kurulumda görülen uygulamanın kaybolması uyarılır'
$unknown=[pscustomobject]@{Name='Codex';AppID='OpenAI.Codex_newpublisher!App'}
Assert (-not (Get-IdentityAssessment @($codex,$unknown)).Healthy) 'Eski uygulama dursa da yeni kimlik uyarılır'
$renamed=[pscustomobject]@{Name='Codex';AppID='OpenAI.Codex_2p2nqsd0c76g0!NewApp'}
Assert (-not (Get-IdentityAssessment @($renamed)).Healthy) 'AUMID eki değişimi uyarılır'
$other=[pscustomobject]@{Name='Hesap Makinesi';AppID='Microsoft.WindowsCalculator_example!App'}
Assert (Get-IdentityAssessment @($codex,$other)).Healthy 'İlgisiz uygulama uyarı üretmez'
$alias=[pscustomobject]@{Name='Codex';AppID='com.openai.codex'}
Assert (Get-IdentityAssessment @($codex,$alias)).Healthy 'Bilinen Başlat menüsü kopyası uyarı üretmez'
. (Join-Path $root 'Protection.ps1')
function Rule([string]$Sid,[Security.AccessControl.FileSystemRights]$Rights,[Security.AccessControl.PropagationFlags]$Propagation='None'){
    [pscustomobject]@{IdentityReference=[pscustomobject]@{Value=$Sid};AccessControlType='Allow';FileSystemRights=$Rights;PropagationFlags=$Propagation}
}
Assert (@(Get-UnsafeWriteRules @((Rule 'S-1-5-32-545' 'ReadAndExecute'))).Count -eq 0) 'Users okuma hakkı kurulum güvenliğini bozmaz'
Assert (@(Get-UnsafeWriteRules @((Rule 'S-1-5-32-545' 'Write'))).Count -eq 1) 'Users yazma hakkı reddedilir'
Assert (@(Get-UnsafeWriteRules @((Rule 'S-1-5-11' 'ChangePermissions'))).Count -eq 1) 'Yalnız ACL değiştirme hakkı da reddedilir'
Assert (@(Get-UnsafeWriteRules @((Rule 'S-1-5-18' 'FullControl'),(Rule 'S-1-5-32-544' 'FullControl'),(Rule 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' 'FullControl'))).Count -eq 0) 'SYSTEM, yöneticiler ve TrustedInstaller korunmuş yazarlardır'
Assert (@(Get-UnsafeWriteRules @((Rule 'S-1-3-0' 'FullControl' 'InheritOnly'))).Count -eq 0) 'Yalnız miras şablonu mevcut klasör yazma hakkı sayılmaz'
if($ReadOnlyNative){
    $shellFile=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $output=& $shellFile -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'Install.ps1') -PrepareOnly
    Assert ($LASTEXITCODE -eq 0) 'Kurulum planı salt okunur hazırlanır'
    $plan=($output -join [Environment]::NewLine)|ConvertFrom-Json
    [xml]$taskXml=$plan.TaskXml;[xml]$identityXml=$plan.IdentityTaskXml
    $ns=[Xml.XmlNamespaceManager]::new($taskXml.NameTable);$ns.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
    $argsText=$taskXml.SelectSingleNode('//t:Arguments',$ns).InnerText
    Assert ($argsText -match '-PollSeconds 10' -and $argsText -match '-RestartGraceSeconds 0') 'Görev güncel aralık ve toleransı kullanır'
    Assert ($taskXml.SelectSingleNode('//t:RunLevel',$ns).InnerText -eq 'HighestAvailable') 'Ana görev yükseltilmiş çalışır'
    $idNs=[Xml.XmlNamespaceManager]::new($identityXml.NameTable);$idNs.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
    Assert ($identityXml.SelectSingleNode('//t:RunLevel',$idNs).InnerText -eq 'LeastPrivilege') 'Kimlik denetimi normal yetkiyle çalışır'
    Assert ($taskXml.SelectSingleNode('//t:LogonType',$ns).InnerText -eq 'InteractiveToken') 'Görev parola saklamayan oturum türünü kullanır'
    $query=$taskXml.SelectSingleNode('//t:Subscription',$ns).InnerText
    Assert ($query -notmatch 'WindowsApps|26\.' -and $query -match 'OpenAI.Codex_2p2nqsd0c76g0!App') 'Açılış filtresi sürümlü EXE yoluna bağlı değildir'
    $tempState=Join-Path ([IO.Path]::GetTempPath()) ('codex-lockguard-readonly-'+[Guid]::NewGuid().ToString('N'))
    try{
        $output=& $shellFile -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'Codex-LockGuard.ps1') -Mode Status -StateDirectory $tempState
        Assert ($LASTEXITCODE -eq 0) 'Native C# derlenir ve salt okunur Windows durum çağrısı çalışır'
        $status=($output -join [Environment]::NewLine)|ConvertFrom-Json
        Assert ($status.SessionState -in @('locked','unlocked','unknown')) 'Gerçek WTS oturum durumu çözümlenir'
        Assert (-not $status.Running -and -not $status.Backup) 'Salt okunur kontrolde izleyici/yedek oluşturulmaz'
    }finally{
        # Only an empty directory created by this test; never recurse into user data.
        if([IO.Directory]::Exists($tempState)){[IO.Directory]::Delete($tempState,$false)}
    }
}
[pscustomobject]@{Passed=$true;CheckCount=$checks.Count;Checks=@($checks);ReadOnlyNative=[bool]$ReadOnlyNative;WindowsSettingsChanged=$false;RealInstallerRun=$false}|ConvertTo-Json -Depth 4
