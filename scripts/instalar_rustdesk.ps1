<#
  Instalador RustDesk - Olamtex
  Instala RustDesk como servicio, le asigna una contraseña fuerte propia de este equipo y guarda
  el ID y la contraseña en la bóveda de la app de Tickets (no hay que anotar nada).

  Uso (PowerShell como administrador):
      powershell -ExecutionPolicy Bypass -File .\instalar_rustdesk.ps1

  Opcional:
      -Version 1.4.2      instala una versión específica en vez de la última
      -SoloRegistrar      no instala; solo genera clave nueva y la reporta (equipo que ya tiene RustDesk)
#>
param(
    [string]$Version = "",
    [switch]$SoloRegistrar
)

$UrlApp = "__URL_APP__"
$Token  = "__TOKEN__"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Exe = Join-Path $env:ProgramFiles "RustDesk\rustdesk.exe"

function Paso($t) { Write-Host "`n>> $t" -ForegroundColor Cyan }

# 1. Debe correr como administrador
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Abra PowerShell como ADMINISTRADOR (clic derecho > Ejecutar como administrador) y vuelva a correr el script." -ForegroundColor Red
    exit 1
}

# 2. Descargar e instalar (si ya está instalado, solo se registra; no se reinstala)
if (-not $SoloRegistrar -and (Test-Path $Exe)) {
    Write-Host "RustDesk ya está instalado en este equipo; se omite la instalación." -ForegroundColor Yellow
    $SoloRegistrar = $true
}
if (-not $SoloRegistrar) {
    Paso "Buscando el instalador oficial de RustDesk (GitHub)..."
    if ($Version) {
        $rel = Invoke-RestMethod "https://api.github.com/repos/rustdesk/rustdesk/releases/tags/$Version" -Headers @{ "User-Agent" = "Olamtex" }
    } else {
        $rel = Invoke-RestMethod "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -Headers @{ "User-Agent" = "Olamtex" }
    }
    $asset = $rel.assets | Where-Object { $_.name -match '^rustdesk-[\d\.]+-x86_64\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw "No se encontró el instalador de Windows en la versión $($rel.tag_name)." }
    $tmp = Join-Path $env:TEMP $asset.name
    Write-Host "Descargando $($asset.name)..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing

    Paso "Instalando RustDesk $($rel.tag_name)..."
    # SIN -Wait: el instalador deja RustDesk abierto y -Wait se quedaría esperando para siempre.
    # Se lanza y se espera a que aparezca el ejecutable instalado.
    Start-Process -FilePath $tmp -ArgumentList "--silent-install"
    for ($i = 0; $i -lt 60 -and -not (Test-Path $Exe); $i++) { Start-Sleep -Seconds 2 }
    if (-not (Test-Path $Exe)) { throw "La instalación no terminó (no existe $Exe)." }
    Start-Sleep -Seconds 15   # deja arrancar el servicio
    # Cierra la ventana de RustDesk que deja abierta el instalador (el servicio sigue corriendo)
    Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle } | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $Exe)) { throw "RustDesk no está instalado en este equipo." }

# 3. Servicio activo y arrancando con Windows
$svc = Get-Service -Name "RustDesk" -ErrorAction SilentlyContinue
if ($svc) {
    Set-Service -Name "RustDesk" -StartupType Automatic
    if ($svc.Status -ne "Running") { Start-Service -Name "RustDesk"; Start-Sleep -Seconds 5 }
}

# 4. Contraseña fuerte propia de este equipo (16 caracteres, sin caracteres confusos)
Paso "Asignando contraseña de acceso desatendido..."
$chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789".ToCharArray()
$bytes = New-Object byte[] 16
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$Password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
& $Exe --password $Password | Out-Null
Start-Sleep -Seconds 3

# 5. Leer el ID del equipo
$Id = ""
for ($i = 0; $i -lt 10 -and -not $Id; $i++) {
    $Id = ((& $Exe --get-id | Out-String) -replace '\D', '')
    if (-not $Id) { Start-Sleep -Seconds 3 }
}
if (-not $Id) { throw "No se pudo leer el ID de RustDesk. Abra RustDesk una vez y vuelva a correr con -SoloRegistrar." }

$ver = ""
try { $ver = (Get-Item $Exe).VersionInfo.ProductVersion } catch {}

# 6. Guardar en la bóveda de la app
Paso "Guardando ID y contraseña en la bóveda de la app de Tickets..."
$datos = @{
    hostname        = $env:COMPUTERNAME
    id              = $Id
    password        = $Password
    version         = $ver
    usuario_windows = "$env:USERDOMAIN\$env:USERNAME"
} | ConvertTo-Json -Compress
$guardado = $false
for ($intento = 1; $intento -le 3 -and -not $guardado; $intento++) {
    try {
        $r = Invoke-RestMethod -Uri "$UrlApp/api/boveda/rustdesk" -Method Post -ContentType "application/json; charset=utf-8" `
            -Body ([Text.Encoding]::UTF8.GetBytes($datos)) -Headers @{ "X-Backup-Token" = $Token } -TimeoutSec 30
        $guardado = $true
        Write-Host "Guardado en la bóveda como: $($r.servicio)" -ForegroundColor Green
    } catch {
        Write-Host "Intento $intento falló: $($_.Exception.Message)" -ForegroundColor Yellow
        Start-Sleep -Seconds (5 * $intento)
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  Equipo : $env:COMPUTERNAME"
Write-Host "  ID     : $Id"
if (-not $guardado) {
    Write-Host "  Clave  : $Password" -ForegroundColor Yellow
    Write-Host "  NO se pudo guardar en la bóveda: anote ID y clave y cárguelos a mano." -ForegroundColor Yellow
} else {
    Write-Host "  Clave  : guardada en la bóveda (Contraseñas > Equipo > RustDesk)"
}
Write-Host "==============================================" -ForegroundColor Green
