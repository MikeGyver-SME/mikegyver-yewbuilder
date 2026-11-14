<#
.SYNOPSIS
  Starts the YewBuilder builder server on Windows (PowerShell).

.DESCRIPTION
  Checks Rust + the wasm32 target + trunk are installed, then runs
  server.py on port 8080. Put this machine's LAN IP in the iPhone app
  Settings as the builder URL, e.g. http://192.168.1.10:8080

  First-time setup (one-off, PowerShell):
    winget install Rustlang.Rustup
    # close and reopen PowerShell, then:
    rustup default stable
    rustup target add wasm32-unknown-unknown
    cargo install trunk

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\run-server.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\run-server.ps1 -Port 8080
#>
param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

function Test-Command($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'python')) { throw "Python not found. Install it from python.org or the Microsoft Store, then re-run this script." }
if (-not (Test-Command 'cargo')) { throw "cargo not found. Run: winget install Rustlang.Rustup  — then close and reopen PowerShell and run: rustup default stable" }
if (-not (Test-Command 'trunk')) { throw "trunk not found. Run: cargo install trunk  (after: rustup target add wasm32-unknown-unknown)" }

$trunkVersion = trunk --version
$cargoVersion = cargo --version
Write-Host "YewBuilder server — $cargoVersion / $trunkVersion" -ForegroundColor Green
Write-Host "Listening on http://0.0.0.0:$Port  — iPhone Settings > Builder server: http://<this-PC-LAN-IP>:$Port" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

Set-Location $PSScriptRoot
python server.py $Port
