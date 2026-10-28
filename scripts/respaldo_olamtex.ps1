<#
  Respaldo Olamtex - copia de seguridad por estación con reporte a la app de Tickets.

  Uso:
    1. Ajuste la sección CONFIGURACIÓN (carpetas a respaldar y destinos).
    2. Pruebe una vez:            powershell -ExecutionPolicy Bypass -File .\respaldo_olamtex.ps1
    3. Programe la tarea diaria:  powershell -ExecutionPolicy Bypass -File .\respaldo_olamtex.ps1 -Instalar -Hora 18:30
       o semanal (copia fría):    powershell -ExecutionPolicy Bypass -File .\copia_fria.ps1 -Instalar -Dia Friday -Hora 20:00
       Cada copia del script con otro nombre de archivo se instala como una tarea aparte.

  Modo "Copiar":    copia las carpetas al destino con robocopy (sin borrar nada en el destino) y reporta.
  Modo "Verificar": no copia; solo revisa que en el destino haya archivos recientes (útil si otra
                    herramienta hace el respaldo) y reporta el resultado.
#>
param(
    [switch]$Instalar,
    [string]$Hora = "18:30",
    [string]$Dia = "",           # ej. "Friday": tarea semanal en vez de diaria
    [switch]$Desinstalar
)

# ======================= CONFIGURACIÓN =======================
$Origenes = @(
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop"
)
# Disco externo o carpeta de red. Deje "" si esta estación no lleva respaldo físico.
$DestinoFisico = ""          # ej. "E:\Respaldos"  o  "\\SERVIDOR\Respaldos"
# Carpeta sincronizada con la nube (OneDrive / Google Drive). Deje "" si no aplica.
$DestinoNube   = ""          # ej. "$env:USERPROFILE\OneDrive - Olamtex\Respaldos"
$Modo          = "Copiar"    # "Copiar" o "Verificar"
$HorasMaximas  = 26          # en modo Verificar: antigüedad máxima aceptada del último archivo
$Excluir       = @('*.tmp', '~$*', '*.lnk', 'desktop.ini', 'Thumbs.db')
# =============================================================

$UrlApp = "__URL_APP__"
$Token  = "__TOKEN__"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$CarpetaLog = Join-Path $env:ProgramData "RespaldoOlamtex"
New-Item -ItemType Directory -Force -Path $CarpetaLog | Out-Null
$LogGeneral = Join-Path $CarpetaLog ("respaldo_{0:yyyy-MM}.log" -f (Get-Date))
$NombreScript = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$NombreTarea = if ($NombreScript -eq "respaldo_olamtex") { "Respaldo Olamtex" } else { "Respaldo Olamtex ($NombreScript)" }

function Escribir-Log([string]$texto) {
    $linea = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $texto
    Add-Content -Path $LogGeneral -Value $linea -Encoding UTF8
    Write-Host $linea
}

if ($Desinstalar) {
    Unregister-ScheduledTask -TaskName $NombreTarea -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Tarea '$NombreTarea' eliminada."
    exit 0
}

if ($Instalar) {
    $destinoScript = Join-Path $CarpetaLog (Split-Path $PSCommandPath -Leaf)
    if ($PSCommandPath -ne $destinoScript) { Copy-Item -Path $PSCommandPath -Destination $destinoScript -Force }
    $accion  = New-ScheduledTaskAction -Execute "powershell.exe" `
               -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$destinoScript`""
    $disparo = if ($Dia) { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Dia -At $Hora } else { New-ScheduledTaskTrigger -Daily -At $Hora }
    $frecuencia = if ($Dia) { "cada $Dia" } else { "todos los días" }
    $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
               -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 6)
    $usuario = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $NombreTarea -Action $accion -Trigger $disparo -Settings $ajustes `
        -Principal $principal -Description "Copia de seguridad ($frecuencia) con reporte a la app de Tickets Olamtex" -Force | Out-Null
    Write-Host "Tarea '$NombreTarea' programada $frecuencia a las $Hora para $usuario."
    Write-Host "Script instalado en: $destinoScript"
    Write-Host "Si la PC está apagada a esa hora, se ejecuta apenas se encienda."
    exit 0
}

function Enviar-Reporte($datos) {
    $json = $datos | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    for ($intento = 1; $intento -le 3; $intento++) {
        try {
            Invoke-RestMethod -Uri "$UrlApp/api/respaldos/reporte" -Method Post -Body $bytes `
                -ContentType "application/json; charset=utf-8" -Headers @{ "X-Backup-Token" = $Token } -TimeoutSec 30 | Out-Null
            Escribir-Log "Reporte enviado ($($datos.tipo): $($datos.estado))."
            return
        } catch {
            Escribir-Log "No se pudo enviar el reporte (intento $intento): $($_.Exception.Message)"
            Start-Sleep -Seconds (15 * $intento)
        }
    }
}

function Medir-Carpeta([string]$ruta) {
    $archivos = Get-ChildItem -Path $ruta -Recurse -File -Force -ErrorAction SilentlyContinue
    $medida = $archivos | Measure-Object -Property Length -Sum
    $ultimo = $archivos | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return @{ Archivos = [int]$medida.Count; Bytes = [int64]($medida.Sum); Ultimo = $ultimo }
}

function Ejecutar-Respaldo([string]$tipo, [string]$destinoBase) {
    $inicio = Get-Date
    $destinoEquipo = Join-Path $destinoBase $env:COMPUTERNAME
    $errores = @()
    $detalle = @()

    try {
        if (-not (Test-Path $destinoBase)) { throw "No se encuentra el destino $destinoBase (¿disco desconectado o sin red?)" }

        if ($Modo -eq "Copiar") {
            New-Item -ItemType Directory -Force -Path $destinoEquipo | Out-Null
            $logRobocopy = Join-Path $CarpetaLog ("robocopy_{0}_{1:yyyyMMdd}.log" -f $tipo.Replace("í","i"), (Get-Date))
            foreach ($origen in $Origenes) {
                if (-not (Test-Path $origen)) { $errores += "No existe el origen $origen"; continue }
                $nombre = Split-Path $origen -Leaf
                $destino = Join-Path $destinoEquipo $nombre
                $argumentos = @($origen, $destino, "/E", "/XO", "/R:1", "/W:5", "/NP", "/NFL", "/NDL", "/XJ", "/MT:8", "/LOG+:$logRobocopy", "/XF") + $Excluir
                & robocopy @argumentos | Out-Null
                $codigo = $LASTEXITCODE
                if ($codigo -ge 8) { $errores += "robocopy terminó con código $codigo en $nombre (ver $logRobocopy)" }
                else { $detalle += "$nombre OK (código $codigo)" }
            }
            $medida = Medir-Carpeta $destinoEquipo
        } else {
            $carpeta = if (Test-Path $destinoEquipo) { $destinoEquipo } else { $destinoBase }
            $medida = Medir-Carpeta $carpeta
            if (-not $medida.Ultimo) { throw "El destino $carpeta está vacío" }
            $horas = ((Get-Date) - $medida.Ultimo.LastWriteTime).TotalHours
            $detalle += "Archivo más reciente: $($medida.Ultimo.Name) ({0:N1} h)" -f $horas
            if ($horas -gt $HorasMaximas) { $errores += "El último archivo tiene {0:N0} horas (máximo $HorasMaximas)" -f $horas }
        }
    } catch {
        $errores += $_.Exception.Message
        $medida = @{ Archivos = 0; Bytes = 0 }
    }

    $estado = if ($errores.Count -eq 0) { "OK" } else { "Error" }
    $mensaje = (($detalle + $errores) -join " | ")
    Escribir-Log "[$tipo] $estado - $mensaje"
    Enviar-Reporte @{
        hostname     = $env:COMPUTERNAME
        tipo         = $tipo
        estado       = $estado
        destino      = $destinoBase
        tamano_bytes = $medida.Bytes
        archivos     = $medida.Archivos
        duracion_seg = [int]((Get-Date) - $inicio).TotalSeconds
        fecha        = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
        mensaje      = "[$Modo] $mensaje"
    }
}

Escribir-Log "==== Inicio respaldo en $env:COMPUTERNAME (modo $Modo) ===="
if (-not $DestinoFisico -and -not $DestinoNube) {
    Escribir-Log "No hay destinos configurados. Edite la sección CONFIGURACIÓN del script."
    exit 1
}
if ($DestinoFisico) { Ejecutar-Respaldo "Físico" $DestinoFisico }
if ($DestinoNube)   { Ejecutar-Respaldo "Nube"   $DestinoNube }
Escribir-Log "==== Fin ===="
