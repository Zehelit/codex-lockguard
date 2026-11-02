#requires -Version 5.1
$ErrorActionPreference='Stop'
$outputFile=Join-Path $PSScriptRoot 'IdentityAlert.exe'
$temporary=Join-Path $PSScriptRoot ('IdentityAlert.'+[Guid]::NewGuid().ToString('N')+'.exe')
try {
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'IdentityAlert.cs'))
    Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing -OutputAssembly $temporary -OutputType WindowsApplication
    Move-Item -LiteralPath $temporary -Destination $outputFile -Force
    Get-FileHash -LiteralPath $outputFile -Algorithm SHA256|Select-Object Hash
} finally {if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
