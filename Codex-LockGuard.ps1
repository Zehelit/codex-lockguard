#requires -Version 5.1
<#
Manages automatic-lock settings while a selected packaged desktop app is running.
Does NOT request display/system wakefulness, disable a screen saver, change its
timeout, synthesize input, unlock a session, or alter machine-wide policies.
Use -Mode Status first. See README.md for scope, tests and recovery.
#>
[CmdletBinding()]
param(
    [ValidateSet('Status','Run','Start','Stop','Restore','Test','Watchdog')]
    [string]$Mode = 'Status',
    [string[]]$PackageFamily = @('OpenAI.Codex_2p2nqsd0c76g0','OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0'),
    [ValidateRange(1,60)][int]$PollSeconds = 10,
    [ValidateRange(0,300)][int]$RestartGraceSeconds = 0,
    [ValidateRange(0,86400)][int]$RunSeconds = 0,
    [switch]$ExitWhenNoTargets = $true,
    [ValidateRange(0,60)][int]$InitialTargetWaitSeconds = 15,
    [string]$ExpectedUserSid = '',
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'CodexLockGuard'),
    [int]$OwnerProcessId = 0,
    [long]$OwnerStartTicks = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) {
    throw '64-bit Windows PowerShell or PowerShell is required.'
}

if (-not ('CodexLockGuard.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace CodexLockGuard {
    public sealed class Target {
        public int ProcessId; public int ParentProcessId; public string Family;
        public string ApplicationId; public long StartTicks;
    }
    public sealed class DisplayPolicy {
        public string Scheme; public uint ACSeconds; public uint DCSeconds;
    }
    public sealed class ResumePolicy {
        public string Scheme; public uint ACRequirePassword; public uint DCRequirePassword;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        struct Entry {
            public uint Size, Usage, ProcessId; public UIntPtr HeapId;
            public uint ModuleId, Threads, ParentId; public int BasePriority;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=260)] public string ExeFile;
        }
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint id);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32FirstW(IntPtr h,ref Entry e);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool Process32NextW(IntPtr h,ref Entry e);
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint id);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll")] static extern bool ProcessIdToSessionId(uint id,out uint session);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetPackageFamilyName(IntPtr h,ref uint n,StringBuilder name);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetApplicationUserModelId(IntPtr h,ref uint n,StringBuilder name);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr h,out long created,out long exited,out long kernel,out long user);
        [DllImport("user32.dll", SetLastError=true)] static extern bool SystemParametersInfoW(uint action,uint parameter,ref int value,uint flags);
        [DllImport("user32.dll", SetLastError=true)] static extern bool SystemParametersInfoW(uint action,uint parameter,IntPtr value,uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr SendMessageTimeoutW(IntPtr hwnd,uint msg,UIntPtr wp,string lp,uint flags,uint timeout,out UIntPtr result);
        [DllImport("wtsapi32.dll", SetLastError=true)] static extern bool WTSQuerySessionInformationW(IntPtr server,int session,int info,out IntPtr buffer,out int bytes);
        [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr p);
        [DllImport("powrprof.dll")] static extern uint PowerGetActiveScheme(IntPtr root,out IntPtr scheme);
        [DllImport("powrprof.dll")] static extern uint PowerReadACValueIndex(IntPtr root,ref Guid scheme,ref Guid group,ref Guid setting,out uint value);
        [DllImport("powrprof.dll")] static extern uint PowerReadDCValueIndex(IntPtr root,ref Guid scheme,ref Guid group,ref Guid setting,out uint value);
        [DllImport("powrprof.dll")] static extern uint PowerWriteACValueIndex(IntPtr root,ref Guid scheme,ref Guid group,ref Guid setting,uint value);
        [DllImport("powrprof.dll")] static extern uint PowerWriteDCValueIndex(IntPtr root,ref Guid scheme,ref Guid group,ref Guid setting,uint value);
        [DllImport("powrprof.dll")] static extern uint PowerSetActiveScheme(IntPtr root,ref Guid scheme);
        [DllImport("powrprof.dll")] static extern uint PowerSettingAccessCheck(uint access,ref Guid setting);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
        [DllImport("ntdll.dll")] static extern int NtQueryKey(IntPtr key,int info,IntPtr buffer,int length,out int needed);
        public static string RegistryLocation() {
            using(Microsoft.Win32.RegistryKey key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop",false)) {
                if(key==null) return "missing";
                IntPtr handle=key.Handle.DangerousGetHandle();
                int needed;NtQueryKey(handle,3,IntPtr.Zero,0,out needed);
                if(needed<4) return "unknown";
                IntPtr p=Marshal.AllocHGlobal(needed);
                try {int code=NtQueryKey(handle,3,p,needed,out needed);if(code!=0)return "NtQueryKey "+code;return Marshal.PtrToStringUni(IntPtr.Add(p,4),Marshal.ReadInt32(p)/2);}
                finally {Marshal.FreeHGlobal(p);}
            }
        }
        static string Identity(IntPtr h,bool application) {
            uint n=0;
            int code=application ? GetApplicationUserModelId(h,ref n,null) : GetPackageFamilyName(h,ref n,null);
            if(code==15700 || code==15703) return null;
            if(code!=122) throw new Win32Exception(code,"Cannot query process package identity");
            StringBuilder text=new StringBuilder((int)n);
            code=application ? GetApplicationUserModelId(h,ref n,text) : GetPackageFamilyName(h,ref n,text);
            if(code!=0) throw new Win32Exception(code);
            return text.ToString();
        }
        public static Target[] Targets(string[] families,int session) {
            HashSet<string> accepted=new HashSet<string>(families,StringComparer.OrdinalIgnoreCase);
            Dictionary<int,Target> matched=new Dictionary<int,Target>();
            IntPtr snap=CreateToolhelp32Snapshot(2,0);
            if(snap==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                Entry e=new Entry(); e.Size=(uint)Marshal.SizeOf(typeof(Entry));
                if(!Process32FirstW(snap,ref e)) throw new Win32Exception(Marshal.GetLastWin32Error());
                do {
                    uint currentSession;
                    if(!ProcessIdToSessionId(e.ProcessId,out currentSession) || currentSession!=session) continue;
                    IntPtr h=OpenProcess(0x1000,false,e.ProcessId);
                    if(h==IntPtr.Zero) {
                        // An inaccessible likely target must not be mistaken for an app exit.
                        if(String.Equals(e.ExeFile,"ChatGPT.exe",StringComparison.OrdinalIgnoreCase))
                            throw new Win32Exception(Marshal.GetLastWin32Error(),"Cannot inspect a ChatGPT process");
                        continue;
                    }
                    try {
                        string family=Identity(h,false);
                        if(family==null || !accepted.Contains(family)) continue;
                        string application=Identity(h,true);
                        // Package-scoped RuntimeBroker processes can outlive the app.
                        // Verified desktop application IDs; neither contains a package version.
                        string expected=family+(String.Equals(family,"OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0",StringComparison.OrdinalIgnoreCase) ? "!ChatGPT" : "!App");
                        if(!String.Equals(application,expected,StringComparison.OrdinalIgnoreCase)) continue;
                        long created,exited,kernel,user;
                        if(!GetProcessTimes(h,out created,out exited,out kernel,out user))
                            throw new Win32Exception(Marshal.GetLastWin32Error());
                        matched[(int)e.ProcessId]=new Target { ProcessId=(int)e.ProcessId,
                            ParentProcessId=(int)e.ParentId,Family=family,
                            ApplicationId=application,StartTicks=created };
                    } finally { CloseHandle(h); }
                } while(Process32NextW(snap,ref e));
                int error=Marshal.GetLastWin32Error();
                if(error!=18 && error!=0) throw new Win32Exception(error,"Process enumeration failed");
            } finally { CloseHandle(snap); }
            List<Target> roots=new List<Target>();
            foreach(Target t in matched.Values) {
                Target parent;
                if(!matched.TryGetValue(t.ParentProcessId,out parent) || parent.StartTicks>t.StartTicks) roots.Add(t);
            }
            return roots.ToArray();
        }
        public static bool ProcessIdentity(int processId,long expectedTicks) {
            IntPtr h=OpenProcess(0x1000,false,(uint)processId);
            if(h==IntPtr.Zero) {
                int error=Marshal.GetLastWin32Error();
                if(error==87 || error==1168) return false;
                throw new Win32Exception(error,"Cannot verify controller identity");
            }
            try {
                long created,exited,kernel,user;
                if(!GetProcessTimes(h,out created,out exited,out kernel,out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
                // A terminated process object must not be mistaken for a running controller.
                return created==expectedTicks && exited==0;
            } finally { CloseHandle(h); }
        }
        public static int ReadParameter(uint action) {
            int value=0;
            if(!SystemParametersInfoW(action,0,ref value,0)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return value;
        }
        public static void SetScreenSaverPassword(bool required) {
            if(!SystemParametersInfoW(0x77,required ? 1u:0u,IntPtr.Zero,0))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"Cannot change screen saver password requirement");
        }
        public static bool NotifySettings() {
            UIntPtr result;
            return SendMessageTimeoutW(new IntPtr(0xffff),0x1a,UIntPtr.Zero,"Desktop",0x22,100,out result)!=IntPtr.Zero;
        }
        public static string SessionState(int session) {
            IntPtr p; int count;
            if(!WTSQuerySessionInformationW(IntPtr.Zero,session,25,out p,out count)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                if(count<20 || Marshal.ReadInt32(p)!=1 || Marshal.ReadInt32(p,8)!=session)
                    throw new InvalidOperationException("Unexpected WTS session structure");
                int flag=Marshal.ReadInt32(p,16);
                if(flag==0) return "locked";
                if(flag==1) return "unlocked";
                return "unknown";
            } finally { WTSFreeMemory(p); }
        }
        public static string ActiveScheme() {
            IntPtr p; uint code=PowerGetActiveScheme(IntPtr.Zero,out p);
            if(code!=0) throw new Win32Exception((int)code);
            Guid scheme;
            try { scheme=(Guid)Marshal.PtrToStructure(p,typeof(Guid)); } finally { LocalFree(p); }
            return scheme.ToString();
        }
        public static ResumePolicy ResumePassword(string schemeText) {
            Guid scheme=new Guid(String.IsNullOrEmpty(schemeText) ? ActiveScheme() : schemeText);
            Guid group=new Guid("fea3413e-7e05-4911-9a71-700331f1c294");
            Guid setting=new Guid("0e796bdb-100d-47d6-a2d5-f7d2daa51f51");
            uint ac,dc;
            uint code=PowerReadACValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,out ac);
            if(code!=0) throw new Win32Exception((int)code,"Cannot read AC resume-password policy");
            code=PowerReadDCValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,out dc);
            if(code!=0) throw new Win32Exception((int)code,"Cannot read DC resume-password policy");
            return new ResumePolicy {Scheme=scheme.ToString(),ACRequirePassword=ac,DCRequirePassword=dc};
        }
        public static void WriteResumePassword(string schemeText,uint ac,uint dc) {
            Guid scheme=new Guid(schemeText);
            Guid group=new Guid("fea3413e-7e05-4911-9a71-700331f1c294");
            Guid setting=new Guid("0e796bdb-100d-47d6-a2d5-f7d2daa51f51");
            uint code=PowerWriteACValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,ac);
            if(code!=0) throw new Win32Exception((int)code,"Cannot write AC resume-password policy (Win32 "+code+"). CONSOLELOCK may require an elevated administrator token.");
            code=PowerWriteDCValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,dc);
            if(code!=0) throw new Win32Exception((int)code,"Cannot write DC resume-password policy (Win32 "+code+").");
            // Reapply only if this is still the active scheme. Never switch the user's plan.
            if(String.Equals(ActiveScheme(),scheme.ToString(),StringComparison.OrdinalIgnoreCase)) {
                code=PowerSetActiveScheme(IntPtr.Zero,ref scheme);
                if(code!=0) throw new Win32Exception((int)code,"Cannot activate resume-password policy");
            }
            ResumePolicy actual=ResumePassword(scheme.ToString());
            if(actual.ACRequirePassword!=ac || actual.DCRequirePassword!=dc)
                throw new InvalidOperationException("Resume-password write verification failed");
        }
        public static uint ResumeWriteAccess() {
            Guid setting=new Guid("0e796bdb-100d-47d6-a2d5-f7d2daa51f51");
            // POWER_DATA_ACCESSOR: ACCESS_AC_POWER_SETTING_INDEX=0, DC=1.
            uint ac=PowerSettingAccessCheck(0,ref setting);
            return ac!=0 ? ac : PowerSettingAccessCheck(1,ref setting);
        }
        public static DisplayPolicy DisplayTimeouts() {
            Guid scheme=new Guid(ActiveScheme());
            Guid group=new Guid("7516b95f-f776-4464-8c53-06167f40cc99");
            Guid setting=new Guid("3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e");
            uint ac,dc;
            uint code=PowerReadACValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,out ac);
            if(code!=0) throw new Win32Exception((int)code);
            code=PowerReadDCValueIndex(IntPtr.Zero,ref scheme,ref group,ref setting,out dc);
            if(code!=0) throw new Win32Exception((int)code);
            return new DisplayPolicy { Scheme=scheme.ToString(),ACSeconds=ac,DCSeconds=dc };
        }
    }
}
'@
}

$script:UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($ExpectedUserSid -and $ExpectedUserSid -ne $UserSid) { throw 'Wrong Windows user; refusing to manage another user session.' }
$script:SessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$script:ScriptFile = $PSCommandPath
$script:StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
$script:JournalFile = Join-Path $StateDirectory 'settings-backup.json'
$script:ControllerFile = Join-Path $StateDirectory 'controller.json'
$script:LogFile = Join-Path $StateDirectory 'events.jsonl'
$script:HealthFile = Join-Path $StateDirectory 'health.json'
$script:Version = 2
$script:MutexName = "Local\CodexLockGuard-$UserSid"
$script:StopName = "Local\CodexLockGuard-Stop-$UserSid"
$script:SettingSpecs = @(
    @{Path='Control Panel\Desktop';Name='DelayLockInterval';Value=-1;Kind='DWord'},
    @{Path='Control Panel\Desktop';Name='ScreenSaverIsSecure';Value='0';Kind='String'},
    @{Path='Software\Microsoft\Windows NT\CurrentVersion\Winlogon';Name='EnableGoodbye';Value=0;Kind='DWord'}
)

function Initialize-Directory {
    if (-not (Test-Path -LiteralPath $StateDirectory)) { $null = [IO.Directory]::CreateDirectory($StateDirectory) }
    if (([IO.File]::GetAttributes($StateDirectory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'State directory must not be a reparse point.'
    }
}
function Write-AtomicJson($Path,$Value) {
    $temporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[System.Management.Automation.Language.NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Read-Json($Path) {
    # Readers must allow an atomic rename while the controller updates a receipt.
    for ($attempt=0;$attempt -lt 12;$attempt++) {
        if (-not [IO.File]::Exists($Path)) { return $null }
        $stream=$null;$reader=$null
        try {
            $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $reader=[IO.StreamReader]::new($stream)
            return ($reader.ReadToEnd() | ConvertFrom-Json)
        } catch [IO.FileNotFoundException] { return $null }
        catch [IO.IOException] { if($attempt -eq 11){throw};Start-Sleep -Milliseconds 25 }
        finally { if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()} }
    }
}
function Write-Event([string]$Event,$Details) {
    $entry = [ordered]@{Time=[DateTimeOffset]::Now.ToString('o');Event=$Event;ProcessId=$PID;Details=$Details}
    [IO.File]::AppendAllText($LogFile,($entry|ConvertTo-Json -Depth 8 -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}
function Get-RegistryValue([string]$Path,[string]$Name,[bool]$Machine=$false) {
    if (-not $Machine) {
        # Read the explicitly named user hive through Windows' registry provider.
        # This avoids relying on the launching app's per-process HKCU view.
        $arguments=@{hDefKey=[uint32]2147483651;sSubKeyName=($UserSid+'\'+$Path)}
        $listing=Invoke-CimMethod -Namespace root\default -ClassName StdRegProv -MethodName EnumValues -Arguments $arguments
        if ($listing.ReturnValue -in @(2,3) -or ($listing.ReturnValue -eq 0 -and @($listing.sNames) -notcontains $Name)) {
            return [pscustomobject]@{Path=$Path;Name=$Name;Exists=$false;Kind=$null;Value=$null}
        }
        if ($listing.ReturnValue -ne 0) {throw ('Windows registry enumeration failed: '+$listing.ReturnValue+' '+$Path)}
        $index=[Array]::IndexOf([string[]]$listing.sNames,$Name)
        $type=[int]$listing.Types[$index]
        $method= switch($type){1{'GetStringValue'};2{'GetExpandedStringValue'};3{'GetBinaryValue'};4{'GetDWORDValue'};7{'GetMultiStringValue'};11{'GetQWORDValue'};default{throw ('Unsupported registry type: '+$type)}}
        $kind= switch($type){1{'String'};2{'ExpandString'};3{'Binary'};4{'DWord'};7{'MultiString'};11{'QWord'}}
        $arguments.sValueName=$Name
        $read=Invoke-CimMethod -Namespace root\default -ClassName StdRegProv -MethodName $method -Arguments $arguments
        if ($read.ReturnValue -ne 0) {throw ('Windows registry read failed: '+$read.ReturnValue+' '+$Name)}
        $value=if($type -in @(1,2,7)){$read.sValue}else{$read.uValue}
        if($type -eq 4){$value=[BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$value),0)}
        return [pscustomobject]@{Path=$Path;Name=$Name;Exists=$true;Kind=$kind;Value=$value}
    }
    $root = if ($Machine) { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
    $key = $root.OpenSubKey($Path,$false)
    try {
        if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
            return [pscustomobject]@{Path=$Path;Name=$Name;Exists=$false;Kind=$null;Value=$null}
        }
        return [pscustomobject]@{Path=$Path;Name=$Name;Exists=$true;Kind=$key.GetValueKind($Name).ToString();Value=$key.GetValue($Name)}
    } finally { if ($key) { $key.Dispose() } }
}
function Set-RegistryValue($Entry) {
    $arguments=@{hDefKey=[uint32]2147483651;sSubKeyName=($UserSid+'\'+[string]$Entry.Path)}
    if (-not $Entry.Exists) {
        if(-not (Get-RegistryValue $Entry.Path $Entry.Name).Exists){return}
        $arguments.sValueName=[string]$Entry.Name
        $result=Invoke-CimMethod -Namespace root\default -ClassName StdRegProv -MethodName DeleteValue -Arguments $arguments
    } else {
        $created=Invoke-CimMethod -Namespace root\default -ClassName StdRegProv -MethodName CreateKey -Arguments $arguments
        if($created.ReturnValue -ne 0){throw ('Windows registry key creation failed: '+$created.ReturnValue)}
        $arguments.sValueName=[string]$Entry.Name
        $method=switch([string]$Entry.Kind){
            'DWord' {$arguments.uValue=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$Entry.Value),0);'SetDWORDValue'}
            'String' {$arguments.sValue=[string]$Entry.Value;'SetStringValue'}
            'ExpandString' {$arguments.sValue=[string]$Entry.Value;'SetExpandedStringValue'}
            'MultiString' {$arguments.sValue=[string[]]$Entry.Value;'SetMultiStringValue'}
            'Binary' {$arguments.uValue=[byte[]]$Entry.Value;'SetBinaryValue'}
            'QWord' {$arguments.uValue=[uint64]$Entry.Value;'SetQWORDValue'}
            default {throw ('Unsupported backup registry kind: '+$Entry.Kind)}
        }
        $result=Invoke-CimMethod -Namespace root\default -ClassName StdRegProv -MethodName $method -Arguments $arguments
    }
    if($result.ReturnValue -ne 0){throw ('Windows registry write failed: '+$result.ReturnValue+' '+$Entry.Name)}
}
function Get-Blockers {
    $checks = @(
        @{Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System';Name='InactivityTimeoutSecs';Machine=$true},
        @{Path='SOFTWARE\Microsoft\PolicyManager\current\device\DeviceLock';Name='MaxInactivityTimeDeviceLock';Machine=$true},
        @{Path="SOFTWARE\Microsoft\PolicyManager\current\$UserSid\DeviceLock";Name='MaxInactivityTimeDeviceLock';Machine=$true},
        @{Path='Software\Policies\Microsoft\Windows\Control Panel\Desktop';Name='ScreenSaverIsSecure';Machine=$false},
        @{Path='SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51';Name='ACSettingIndex';Machine=$true},
        @{Path='SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51';Name='DCSettingIndex';Machine=$true},
        @{Path='SOFTWARE\Microsoft\PolicyManager\current\device\Power';Name='RequirePasswordWhenComputerWakesPluggedIn';Machine=$true},
        @{Path='SOFTWARE\Microsoft\PolicyManager\current\device\Power';Name='RequirePasswordWhenComputerWakesOnBattery';Machine=$true}
    )
    foreach ($check in $checks) {
        $v=Get-RegistryValue $check.Path $check.Name $check.Machine
        if ($v.Exists -and [long]$v.Value -gt 0) { $v }
    }
}
function Get-Invariants {
    # Read only. No display or screen-saver activation/timeout setter exists here.
    [pscustomobject]@{
        Display=[CodexLockGuard.Native]::DisplayTimeouts()
        ScreenSaverActive=[CodexLockGuard.Native]::ReadParameter(0x10)
        ScreenSaverTimeout=[CodexLockGuard.Native]::ReadParameter(0x0e)
        ScreenSaverRegistry=@('ScreenSaveActive','ScreenSaveTimeOut','SCRNSAVE.EXE' | ForEach-Object {Get-RegistryValue 'Control Panel\Desktop' $_})
    }
}
function Get-Settings {
    [pscustomobject]@{
        Registry=@($SettingSpecs | ForEach-Object {Get-RegistryValue $_.Path $_.Name})
        RuntimeScreenSaverPassword=[CodexLockGuard.Native]::ReadParameter(0x76)
        ResumePassword=Get-ResumePassword
        Invariants=Get-Invariants
    }
}
function Get-ResumePassword([string]$Scheme='') { [CodexLockGuard.Native]::ResumePassword($Scheme) }
function Set-ResumePassword($Plan,[uint32]$AC,[uint32]$DC) { [CodexLockGuard.Native]::WriteResumePassword($Plan.Scheme,$AC,$DC) }
function Get-ResumeWriteAccess { [CodexLockGuard.Native]::ResumeWriteAccess() }
function Get-Targets { @([CodexLockGuard.Native]::Targets($PackageFamily,$SessionId)) }
function Test-ProcessIdentity([int]$ProcessId,[long]$StartTicks) {
    [CodexLockGuard.Native]::ProcessIdentity($ProcessId,$StartTicks)
}
function Enter-GuardMutex {
    $m=[Threading.Mutex]::new($false,$MutexName)
    try { $acquired=$m.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired=$true }
    if (-not $acquired) { $m.Dispose(); throw 'Another guard owns this session. Use -Mode Stop first.' }
    return $m
}
function Get-Shell {
    # Windows component path, independent of Codex and its bundled runtimes.
    Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
function Start-Hidden([string]$Arguments) {
    Start-Process -FilePath (Get-Shell) -ArgumentList $Arguments -WindowStyle Hidden -PassThru
}
function Get-CommonArguments {
    if ($ScriptFile.Contains('"') -or $StateDirectory.Contains('"')) { throw 'Unsupported quote in script/state path.' }
    '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $ScriptFile + '" -StateDirectory "' + $StateDirectory + '"'
}
function Restore-Settings {
    $journal=Read-Json $JournalFile
    if ($null -eq $journal) { return $true }
    if ($journal.UserSid -ne $UserSid -or $journal.Version -notin @(1,2)) { throw 'Unexpected backup owner or format; refusing to restore.' }
    $saved=@($journal.Baseline.Registry)
    if ($saved.Count -ne $SettingSpecs.Count) { throw 'Invalid settings backup: unexpected entry count.' }
    for ($i=0;$i -lt $SettingSpecs.Count;$i++) {
        if ($saved[$i].Path -ne $SettingSpecs[$i].Path -or $saved[$i].Name -ne $SettingSpecs[$i].Name) {
            throw 'Invalid settings backup: unexpected registry target.'
        }
    }
    # Attempt every independent restoration even if one API fails. Keep the journal
    # until ALL readbacks match. v1 recovery never invents a missing power baseline.
    $errors=[Collections.Generic.List[string]]::new()
    $pending=$false
    $desired=[int]$journal.Baseline.RuntimeScreenSaverPassword
    try {
        if ([CodexLockGuard.Native]::ReadParameter(0x76) -ne $desired) {
            if ([CodexLockGuard.Native]::SessionState($SessionId) -ne 'unlocked') { $pending=$true }
            else { [CodexLockGuard.Native]::SetScreenSaverPassword($desired -ne 0) }
        }
    } catch { $errors.Add($_.Exception.Message) }
    foreach ($entry in $journal.Baseline.Registry) {
        try { Set-RegistryValue $entry } catch { $errors.Add($_.Exception.Message) }
    }
    if ($journal.Version -eq 2) {
        foreach ($plan in @($journal.PowerSchemes)) {
            try {
                $null=[Guid]::Parse([string]$plan.Scheme)
                $current=Get-ResumePassword $plan.Scheme
                if ($current.ACRequirePassword -ne $plan.ACRequirePassword -or $current.DCRequirePassword -ne $plan.DCRequirePassword) {
                    Set-ResumePassword $plan ([uint32]$plan.ACRequirePassword) ([uint32]$plan.DCRequirePassword)
                }
            } catch { $errors.Add(('Power scheme '+$plan.Scheme+': '+$_.Exception.Message)) }
        }
    }
    $notified=[CodexLockGuard.Native]::NotifySettings()
    foreach ($entry in $journal.Baseline.Registry) {
        $actual=Get-RegistryValue $entry.Path $entry.Name
        if (($actual|ConvertTo-Json -Compress) -ne ($entry|ConvertTo-Json -Compress)) { $errors.Add(('Restoration readback failed: '+$entry.Name)) }
    }
    if ($errors.Count -gt 0) {
        $journal.Phase='RestoreFailed';Write-AtomicJson $JournalFile $journal
        throw ('Restoration incomplete; backup retained: '+($errors -join '; '))
    }
    if ($pending) {
        $journal.Phase='PendingRestoreAfterUnlock'
        Write-AtomicJson $JournalFile $journal
        Write-Event 'restore_pending_unlock' $null
        return $false
    }
    $restored=Get-Settings
    if (($restored.Registry|ConvertTo-Json -Depth 5 -Compress) -ne ($journal.Baseline.Registry|ConvertTo-Json -Depth 5 -Compress)) {
        throw 'Registry restoration did not match the backup. Backup retained.'
    }
    if ($restored.RuntimeScreenSaverPassword -ne $desired) { throw 'Runtime password requirement restoration failed. Backup retained.' }
    [IO.File]::Delete($JournalFile)
    Write-Event 'restored' @{DisplayAndScreenSaverTimersUnmodified=$true;SettingsBroadcastDelivered=$notified}
    return $true
}
function Get-ConfigurationProblems {
    foreach ($spec in $SettingSpecs) {
        $actual=Get-RegistryValue $spec.Path $spec.Name
        if (-not $actual.Exists -or $actual.Kind -ne $spec.Kind -or [string]$actual.Value -ne [string]$spec.Value) { 'Registry:'+ $spec.Name }
    }
    if ([CodexLockGuard.Native]::ReadParameter(0x76) -ne 0) { 'RuntimeScreenSaverPassword' }
    $power=Get-ResumePassword
    if ($power.ACRequirePassword -ne 0) { 'ResumePassword:AC' }
    if ($power.DCRequirePassword -ne 0) { 'ResumePassword:DC' }
}
function Repair-Settings {
    $journal=Read-Json $JournalFile
    if (-not $journal -or $journal.Version -ne 2 -or $journal.UserSid -ne $UserSid) { throw 'A version 2 backup is required before repair.' }
    $blockers=@(Get-Blockers)
    if ($blockers.Count -gt 0) { throw ('A mandatory lock policy overrides user settings: '+($blockers|ConvertTo-Json -Compress)) }
    $before=Get-Invariants
    $changed=[Collections.Generic.List[string]]::new()
    $power=Get-ResumePassword
    if (@($journal.PowerSchemes | Where-Object { $_.Scheme -eq $power.Scheme }).Count -eq 0) {
        # Persist the NEW plan's ORIGINAL AC/DC values before touching either.
        $journal.PowerSchemes=@($journal.PowerSchemes)+@($power)
        Write-AtomicJson $JournalFile $journal
    }
    $pending=$false
    if ([CodexLockGuard.Native]::ReadParameter(0x76) -ne 0) {
        if ([CodexLockGuard.Native]::SessionState($SessionId) -eq 'unlocked') {
            [CodexLockGuard.Native]::SetScreenSaverPassword($false);$changed.Add('RuntimeScreenSaverPassword')
        } else { $pending=$true }
    }
    foreach ($spec in $SettingSpecs) {
        $actual=Get-RegistryValue $spec.Path $spec.Name
        if (-not $actual.Exists -or $actual.Kind -ne $spec.Kind -or [string]$actual.Value -ne [string]$spec.Value) {
            Set-RegistryValue ([pscustomobject]@{Path=$spec.Path;Name=$spec.Name;Exists=$true;Kind=$spec.Kind;Value=$spec.Value})
            $changed.Add('Registry:'+ $spec.Name)
        }
    }
    if ($power.ACRequirePassword -ne 0 -or $power.DCRequirePassword -ne 0) {
        Set-ResumePassword $power 0 0;$changed.Add('ResumePassword:AC/DC')
    }
    $notified=$null
    if ($changed.Count -gt 0) { $notified=[CodexLockGuard.Native]::NotifySettings() }
    $problems=@(Get-ConfigurationProblems)
    # A concurrent plan switch is handled on the next poll, not misreported as healthy.
    $unexpected=@($problems | Where-Object { -not ($pending -and $_ -eq 'RuntimeScreenSaverPassword') })
    if ($unexpected.Count -gt 0) { throw ('Settings did not verify: '+($unexpected -join ', ')) }
    if ((Get-Invariants|ConvertTo-Json -Depth 7 -Compress) -ne ($before|ConvertTo-Json -Depth 7 -Compress)) {
        throw 'Display/screen-saver configuration changed during repair; cannot claim invariant preservation.'
    }
    $nextPhase=if($pending){'PendingRuntimeAfterUnlock'}else{'Configured'}
    if ($journal.Phase -ne $nextPhase) { $journal.Phase=$nextPhase;Write-AtomicJson $JournalFile $journal }
    if ($changed.Count -gt 0) { Write-Event 'settings_repaired' @{Changes=@($changed);Scheme=$power.Scheme;SettingsBroadcastDelivered=$notified} }
    return (-not $pending)
}
function Apply-Settings {
    if ([IO.File]::Exists($JournalFile)) { throw 'An existing settings backup must be recovered before applying.' }
    $blockers=@(Get-Blockers)
    if ($blockers.Count -gt 0) { throw ('A mandatory lock policy overrides user settings: '+($blockers|ConvertTo-Json -Compress)) }
    $access=Get-ResumeWriteAccess
    if ($access -ne 0) { throw ('CONSOLELOCK write access denied (Win32 '+$access+'). Start with an elevated Windows administrator token; Codex Full Access does not elevate Windows.') }
    $baseline=Get-Settings
    $journal=[pscustomobject]@{Version=2;UserSid=$UserSid;SessionId=$SessionId;OwnerProcessId=$PID;
        OwnerStartTicks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc();
        Phase='Applying';Time=[DateTimeOffset]::Now.ToString('o');Baseline=$baseline;PowerSchemes=@($baseline.ResumePassword)}
    Write-AtomicJson $JournalFile $journal
    try { return (Repair-Settings) }
    catch { $original=$_;try {$null=Restore-Settings}catch{Write-Event 'rollback_failed' $_.Exception.Message};throw $original }
}
function Get-Health($Running,$Targets,$Observation=$null) {
    $session=[CodexLockGuard.Native]::SessionState($SessionId)
    $blockers=@(Get-Blockers)
    $problems=@(Get-ConfigurationProblems)
    $journal=Read-Json $JournalFile
    $state='Stopped'
    if ($Running) {
        if ($blockers.Count -gt 0) { $state='BlockedByPolicy' }
        elseif ($Observation -and $Observation.LastError) { $state='ConfigurationError' }
        elseif ($journal -and $journal.Phase -in @('RestoreFailed','PendingRestoreAfterUnlock')) { $state=$journal.Phase }
        elseif (-not $journal) { $state=if(@($Targets).Count -gt 0){'NotConfigured'}else{'Idle'} }
        elseif ($problems.Count -gt 0) { $state=if($journal.Phase -eq 'PendingRuntimeAfterUnlock'){'PendingRuntimeAfterUnlock'}else{'ConfigurationDrift'} }
        elseif ($journal.Phase -ne 'Configured') { $state=$journal.Phase }
        elseif ($session -eq 'locked') { $state='ConfiguredButSessionLocked' }
        elseif ($session -eq 'unlocked') { $state='ConfiguredAndSessionUnlocked' }
        else { $state='SessionStateUnknown' }
    }
    [pscustomobject]@{Version=2;Time=[DateTimeOffset]::Now.ToString('o');State=$state;SessionState=$session;
        RegistryLocation=[CodexLockGuard.Native]::RegistryLocation();
        ReportingProcessId=$PID;
        WindowsAdministrator=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator));
        ResumePolicyWriteAccessCode=[CodexLockGuard.Native]::ResumeWriteAccess();
        ConfigurationMatches=($problems.Count -eq 0);ConfigurationProblems=$problems;BlockingPolicies=$blockers;
        LockAfterUnlockObserved=($null -ne $Observation -and [bool]$Observation.LockAfterUnlockObserved);
        UnlockedSince=if($Observation){$Observation.UnlockedSince}else{$null};
        ContinuousUnlockedSeconds=if($Observation -and $Observation.UnlockedSince){[Math]::Round(([DateTimeOffset]::Now-[DateTimeOffset]::Parse($Observation.UnlockedSince)).TotalSeconds,1)}else{0};
        LastError=if($Observation){$Observation.LastError}else{$null};
        LockPreventionProven=$false}
}

function Invoke-Watchdog {
    # Wait on the actual parent process object, validating creation time against PID reuse.
    try {
        $owner=[Diagnostics.Process]::GetProcessById($OwnerProcessId)
        try {
            if ($owner.StartTime.ToUniversalTime().ToFileTimeUtc() -eq $OwnerStartTicks) { $owner.WaitForExit() }
        } finally { $owner.Dispose() }
    } catch [ArgumentException] { }
    while ([IO.File]::Exists($JournalFile)) {
        $journal=Read-Json $JournalFile
        if (-not $journal -or $journal.OwnerProcessId -ne $OwnerProcessId -or $journal.OwnerStartTicks -ne $OwnerStartTicks) { return }
        $m=$null
        try {
            $m=Enter-GuardMutex
            if (Restore-Settings) {
                $controller=Read-Json $ControllerFile
                if ($controller -and $controller.ProcessId -eq $OwnerProcessId -and $controller.StartTicks -eq $OwnerStartTicks) {
                    [IO.File]::Delete($ControllerFile)
                }
                $health=Read-Json $HealthFile
                if ($health -and $health.ReportingProcessId -eq $OwnerProcessId) { [IO.File]::Delete($HealthFile) }
                return
            }
        } catch {
            # A replacement controller owns the mutex and will recover the same journal.
            $controller=Read-Json $ControllerFile
            if ($controller -and (Test-ProcessIdentity $controller.ProcessId $controller.StartTicks)) { return }
            Write-Event 'watchdog_retry' $_.Exception.Message
        } finally { if ($m) { $m.ReleaseMutex();$m.Dispose() } }
        Start-Sleep -Seconds 3
    }
}

function Invoke-Run {
    $m=Enter-GuardMutex
    $stop=$null
    try {
        $stop=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$StopName)
        $null=$stop.Reset()
        $started=[DateTime]::UtcNow
        $ticks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc()
        $previous=Read-Json $JournalFile
        if ($previous) {
            $null=Restore-Settings
            $previous=Read-Json $JournalFile
            if ($previous) {
                $previous.OwnerProcessId=$PID;$previous.OwnerStartTicks=$ticks
                Write-AtomicJson $JournalFile $previous
            }
        }
        $wd=Start-Hidden ((Get-CommonArguments)+' -Mode Watchdog -OwnerProcessId '+$PID+' -OwnerStartTicks '+$ticks)
        Write-AtomicJson $ControllerFile ([pscustomobject]@{Version=2;LifecycleVersion='2.1';SessionId=$SessionId;ProcessId=$PID;StartTicks=$ticks;WatchdogProcessId=$wd.Id;PackageFamilies=$PackageFamily;Started=$started.ToString('o');ExitWhenNoTargets=[bool]$ExitWhenNoTargets;InitialTargetWaitSeconds=$InitialTargetWaitSeconds;RestartGraceSeconds=$RestartGraceSeconds;PollSeconds=$PollSeconds;ScriptFile=$ScriptFile})
        Write-Event 'controller_started' @{Families=$PackageFamily;WatchdogProcessId=$wd.Id}
        $lastSeen=$null
        $lastState=''
        $withinGrace=$false
        $lastSession=[CodexLockGuard.Native]::SessionState($SessionId)
        $observation=[pscustomobject]@{LockAfterUnlockObserved=$false;UnlockedSince=$null;LastError=$null}
        if ($lastSession -eq 'unlocked') { $observation.UnlockedSince=[DateTimeOffset]::Now.ToString('o') }
        while (-not $stop.WaitOne(0)) {
            $targets=@()
            try {
                $targets=@(Get-Targets)
                if ($targets.Count -gt 0) { $lastSeen=[DateTime]::UtcNow }
                $withinGrace=$null -ne $lastSeen -and (([DateTime]::UtcNow-$lastSeen).TotalSeconds -lt $RestartGraceSeconds)
                $journal=Read-Json $JournalFile
                if ($targets.Count -gt 0 -or $withinGrace) {
                    if ($journal -and ($journal.Version -ne 2 -or $journal.Phase -in @('RestoreFailed','PendingRestoreAfterUnlock'))) {
                        $null=Restore-Settings;$journal=Read-Json $JournalFile
                    }
                    if (-not $journal) { $null=Apply-Settings }
                    elseif ($journal.Phase -notin @('RestoreFailed','PendingRestoreAfterUnlock')) { $null=Repair-Settings }
                } elseif ($journal) { $null=Restore-Settings }
                $observation.LastError=$null
            } catch {
                $errorText=$_.Exception.Message
                if ($observation.LastError -ne $errorText) { Write-Event 'configuration_error' $errorText }
                $observation.LastError=$errorText
                # Keep monitoring and retrying. A failed write is never a healthy state.
            }
            $session=[CodexLockGuard.Native]::SessionState($SessionId)
            if ($session -ne $lastSession) {
                if ($session -eq 'locked') {
                    $observation.UnlockedSince=$null
                    if ($lastSession -eq 'unlocked' -and (@($targets).Count -gt 0 -or $withinGrace)) {
                        $observation.LockAfterUnlockObserved=$true
                        Write-Event 'lock_detected_while_guard_active' @{SessionState=$session;Targets=$targets;ConfigurationProblems=@(Get-ConfigurationProblems);ResumePassword=[CodexLockGuard.Native]::ResumePassword($null)}
                    }
                } elseif ($session -eq 'unlocked') { $observation.UnlockedSince=[DateTimeOffset]::Now.ToString('o') }
                Write-Event 'session_state_changed' @{From=$lastSession;To=$session}
                $lastSession=$session
            }
            $health=Get-Health $true $targets $observation
            if ($observation.LastError) { $health.State='ConfigurationError' }
            Write-AtomicJson $HealthFile $health
            if ($health.State -ne $lastState) { Write-Event 'state' @{State=$health.State;Targets=$targets};$lastState=$health.State }
            if ($ExitWhenNoTargets -and $targets.Count -eq 0 -and -not $withinGrace -and -not $observation.LastError) {
                $initialWaitElapsed=([DateTime]::UtcNow-$started).TotalSeconds -ge $InitialTargetWaitSeconds
                if ($null -ne $lastSeen -or $initialWaitElapsed) {
                    Write-Event 'application_lifetime_ended' @{LastTargetSeen=$lastSeen;GraceSeconds=$RestartGraceSeconds}
                    break
                }
            }
            if ($RunSeconds -gt 0 -and ([DateTime]::UtcNow-$started).TotalSeconds -ge $RunSeconds) { break }
            $null=$stop.WaitOne($PollSeconds*1000)
        }
    } catch {
        Write-Event 'controller_error' $_.Exception.Message
        throw
    } finally {
        try { $null=Restore-Settings;Write-Event 'controller_stopped' $null }
        finally {
            if ([IO.File]::Exists($ControllerFile)) { [IO.File]::Delete($ControllerFile) }
            if ([IO.File]::Exists($HealthFile)) { [IO.File]::Delete($HealthFile) }
            if ($stop) {$stop.Dispose()};$m.ReleaseMutex();$m.Dispose()
        }
    }
}

Initialize-Directory
switch ($Mode) {
    'Status' {
        $controller=Read-Json $ControllerFile
        $running=$false
        if ($controller) { $running=Test-ProcessIdentity $controller.ProcessId $controller.StartTicks }
        $targets=@(Get-Targets)
        $lastHealth=Read-Json $HealthFile
        [pscustomobject]@{Version=2;Time=[DateTimeOffset]::Now.ToString('o');UserSid=$UserSid;SessionId=$SessionId;
            SessionState=[CodexLockGuard.Native]::SessionState($SessionId);Running=$running;Controller=$controller;
            Health=(Get-Health $running $targets $lastHealth);LastControllerObservation=$lastHealth;
            Targets=$targets;BlockingPolicies=@(Get-Blockers);Settings=Get-Settings;
            IdentityCheck=Read-Json (Join-Path $StateDirectory 'identity-status.json');
            Backup=Read-Json $JournalFile;StateDirectory=$StateDirectory} | ConvertTo-Json -Depth 12
    }
    'Start' {
        $existing=Read-Json $ControllerFile
        if ($existing -and (Test-ProcessIdentity $existing.ProcessId $existing.StartTicks)) {
            throw 'Guard is already running. Use -Mode Status or -Mode Stop.'
        }
        # Package identities are passed as a PowerShell array through a UTF-16 encoded command.
        $scriptLiteral="'"+$ScriptFile.Replace("'","''")+"'"
        $dirLiteral="'"+$StateDirectory.Replace("'","''")+"'"
        $familyLiteral=($PackageFamily|ForEach-Object {"'"+$_.Replace("'","''")+"'"}) -join ','
        $command="if([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne '"+$UserSid+"'){throw 'Elevation selected another Windows account'}; & "+$scriptLiteral+' -Mode Run -StateDirectory '+$dirLiteral+' -PackageFamily @('+$familyLiteral+') -PollSeconds '+$PollSeconds+' -RestartGraceSeconds '+$RestartGraceSeconds+' -RunSeconds '+$RunSeconds
        if ($ExitWhenNoTargets) { $command+=' -ExitWhenNoTargets -InitialTargetWaitSeconds '+$InitialTargetWaitSeconds }
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
        if ([CodexLockGuard.Native]::ResumeWriteAccess() -ne 0) {
            # UAC is a Windows consent boundary, independent of Codex permissions.
            # No ACL change, credential storage or unattended elevation bypass.
            $p=Start-Process -FilePath (Get-Shell) -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        } else { $p=Start-Hidden $arguments }
        $ready=$false
        for ($attempt=0;$attempt -lt 50;$attempt++) {
            if ($p.HasExited) { throw 'Controller exited during startup; inspect events.jsonl.' }
            $current=Read-Json $ControllerFile
            $currentHealth=Read-Json $HealthFile
            if ($current -and $current.ProcessId -eq $p.Id -and $currentHealth -and $currentHealth.ReportingProcessId -eq $p.Id) { $ready=$true;break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $ready) { throw 'Controller has not reported ready; inspect -Mode Status before retrying.' }
        [pscustomobject]@{StartedProcessId=$p.Id;Version=2;Health=(Read-Json $HealthFile);StateDirectory=$StateDirectory}|ConvertTo-Json -Depth 8
    }
    'Stop' {
        try { $e=[Threading.EventWaitHandle]::OpenExisting($StopName);try {$null=$e.Set()}finally{$e.Dispose()} }
        catch [Threading.WaitHandleCannotBeOpenedException] { }
        $controller=Read-Json $ControllerFile
        if ($controller -and (Test-ProcessIdentity $controller.ProcessId $controller.StartTicks)) {
            $p=[Diagnostics.Process]::GetProcessById($controller.ProcessId)
            try { if (-not $p.WaitForExit(15000)) { throw 'Controller has not stopped; no forced termination was used.' } } finally {$p.Dispose()}
        } else { $m=Enter-GuardMutex;try {$null=Restore-Settings}finally{$m.ReleaseMutex();$m.Dispose()} }
        [pscustomobject]@{Stopped=$true;RestorePending=[IO.File]::Exists($JournalFile)}|ConvertTo-Json
    }
    'Restore' {
        $m=Enter-GuardMutex
        try { [pscustomobject]@{Restored=(Restore-Settings)}|ConvertTo-Json }
        finally {$m.ReleaseMutex();$m.Dispose()}
    }
    'Test' {
        $m=Enter-GuardMutex
        try {
            if ([IO.File]::Exists($JournalFile)) { throw 'Restore an existing backup before running this test.' }
            $before=Get-Settings
            $targets=@(Get-Targets)
            $applied=Apply-Settings
            if (-not $applied) { throw 'Unlock is required for a screen-saver-password change; no settings were changed.' }
            $during=Get-Settings
            if (-not (Restore-Settings)) { throw 'Runtime restoration is pending until unlock.' }
            $after=Get-Settings
            $equal=($before|ConvertTo-Json -Depth 8 -Compress) -eq ($after|ConvertTo-Json -Depth 8 -Compress)
            if (-not $equal) { throw 'Before/after settings did not match.' }
            [pscustomobject]@{Passed=$true;Targets=$targets;SessionState=[CodexLockGuard.Native]::SessionState($SessionId);
                SettingsRoundTrip=$equal;DisplayAndScreenSaverUnchanged=(($before.Invariants|ConvertTo-Json -Depth 8 -Compress) -eq ($during.Invariants|ConvertTo-Json -Depth 8 -Compress));
                LongIdleLockPreventionTested=$false;Before=$before;During=$during;After=$after} | ConvertTo-Json -Depth 12
        } finally { $null=Restore-Settings;$m.ReleaseMutex();$m.Dispose() }
    }
    'Watchdog' { Invoke-Watchdog }
    'Run' { Invoke-Run }
}
