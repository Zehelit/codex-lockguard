#requires -Version 5.1
# Read-only ACL classification shared by setup and offline tests.
function Get-UnsafeWriteRules($Rules) {
    $trusted=@('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $mask=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    @($Rules|Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Value -notin $trusted -and
        ($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0 -and
        ($_.FileSystemRights -band $mask) -ne 0
    })
}
