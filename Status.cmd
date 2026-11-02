@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ProgramFiles%\CodexLockGuard\Codex-LockGuard.ps1" -Mode Status
pause
