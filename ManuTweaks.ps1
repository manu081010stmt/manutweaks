# ManuTweaks - optimizacion de Windows 10 / 11
# Ejecucion:  iwr -useb <URL_RAW_DE_ESTE_ARCHIVO> | iex
# Si PowerShell no es administrador, se abre una ventana elevada (UAC) que vuelve a cargar esta URL.
# Nada se modifica sin contrasena correcta. Al acertarla: copia de valores + punto de restauracion.

# ===================== CONFIGURACION =====================
$ManuTweaksUrl  = 'iwr -useb https://raw.githubusercontent.com/manu081010stmt/manutweaks/main/ManuTweaks.ps1 | iex'
$AuthSalt       = 'gWG6zurDC2jPONEdgp+P3w=='
$AuthHash       = 't87iufZq6+DB3TOZl9dp5CtXnx+cK5Jn4qM8ZuuMEno='
$AuthIterations = 210000
$MTRoot         = Join-Path $env:ProgramData 'ManuTweaks'
$MTLogDir       = Join-Path $MTRoot 'Logs'
$MTBackupDir    = Join-Path $MTRoot 'Backups'

# ===================== INTERFAZ =====================
$MTWidth = 62






# ===================== ADMIN Y CONTRASENA =====================
# (la interfaz grafica esta al final del archivo)
function MT-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


function MT-TestPassword {
    param([AllowEmptyString()][string]$Password)
    if ([string]::IsNullOrEmpty($Password)) { return $false }
    $salt     = [Convert]::FromBase64String($AuthSalt)
    $expected = [Convert]::FromBase64String($AuthHash)
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password, $salt, $AuthIterations,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try { $actual = $kdf.GetBytes($expected.Length) } finally { $kdf.Dispose() }
    $diff = 0
    for ($i = 0; $i -lt $expected.Length; $i++) { $diff = $diff -bor ($actual[$i] -bxor $expected[$i]) }
    return ($diff -eq 0)
}

# ===================== REGISTRO: COPIA, APLICACION Y VERIFICACION =====================
function New-MTDw  { param([string]$Path, [string]$Name, [int]$Value)    [pscustomobject]@{ Path = $Path; Name = $Name; Kind = 'DWord';  Value = $Value } }
function New-MTSt  { param([string]$Path, [string]$Name, [string]$Value) [pscustomobject]@{ Path = $Path; Name = $Name; Kind = 'String'; Value = $Value } }
function New-MTDel { param([string]$Path, [string]$Name)                 [pscustomobject]@{ Path = $Path; Name = $Name; Kind = 'Delete'; Value = $null } }

function MT-AddRegBackup {
    param([string]$Path, [string]$Name)
    $entry = [ordered]@{ Path = $Path; Name = $Name; Existed = $false; Value = $null; Type = $null }
    if (Test-Path -LiteralPath $Path) {
        $prop = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $prop) {
            $entry.Existed = $true
            $entry.Value   = $prop.$Name
            $entry.Type    = (Get-Item -LiteralPath $Path).GetValueKind($Name).ToString()
        }
    }
    [void]$global:MTBackup.Add([pscustomobject]$entry)
}

function MT-SetReg {
    param([string]$Path, [string]$Name, [int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type DWord -ErrorAction Stop
    $actual = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
    $mask = [int64]4294967295
    if ((([int64]$actual) -band $mask) -ne (([int64]$Value) -band $mask)) {
        throw "Verificacion fallida en $Path\$Name (esperado $Value, leido $actual)."
    }
}

function MT-ApplyItem {
    param([Parameter(Mandatory = $true)]$Item)
    MT-AddRegBackup -Path $Item.Path -Name $Item.Name
    switch ($Item.Kind) {
        'DWord' {
            MT-SetReg -Path $Item.Path -Name $Item.Name -Value ([int]$Item.Value)
        }
        'String' {
            if (-not (Test-Path -LiteralPath $Item.Path)) { New-Item -Path $Item.Path -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -Value ([string]$Item.Value) -Type String -ErrorAction Stop
            $actual = (Get-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction Stop).($Item.Name)
            if ($actual -cne [string]$Item.Value) { throw "Verificacion fallida en $($Item.Path)\$($Item.Name)." }
        }
        'Delete' {
            $prop = Get-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
            if ($null -ne $prop) { Remove-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction Stop }
            $after = Get-ItemProperty -LiteralPath $Item.Path -Name $Item.Name -ErrorAction SilentlyContinue
            if ($null -ne $after) { throw "No se pudo eliminar $($Item.Path)\$($Item.Name)." }
        }
    }
}

function MT-Restore {
    param([Parameter(Mandatory = $true)][string]$ManifestPath)
    $entries = @(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
    $ok = 0; $fail = 0
    foreach ($e in $entries) {
        try {
            if ($e.Existed) {
                if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $e.Value -Type $e.Type -ErrorAction Stop
            }
            else {
                Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
            }
            $ok++
        }
        catch {
            $fail++
            MT-Log -Level ERROR -Message "No se pudo restaurar $($e.Path) / $($e.Name): $($_.Exception.Message)"
        }
    }
    MT-Log -Level INFO -Message "Restauracion: $ok correctas, $fail con error."
}

# ===================== FUNCIONES AUXILIARES =====================
function MT-SvcHostValue {
    param([Parameter(Mandatory = $true)][double]$GB)
    return [int]($GB * 1024 * 1024)
}

function MT-DismState {
    param([AllowEmptyString()][string]$Output)
    if ($Output -match 'No component store corruption detected|No se detect') { return 'Healthy' }
    if ($Output -match 'repairable|reparable|se puede reparar') { return 'Repairable' }
    return 'Unknown'
}

function New-MTTask {
    param(
        [string]$Module,
        [string]$Name,
        [string]$Description,
        [object[]]$Items = @(),
        [scriptblock]$Action
    )
    [pscustomobject]@{ Module = $Module; Name = $Name; Description = $Description; Items = $Items; Action = $Action }
}

# ===================== DATOS: VALORES DEL PACK Y DE LA CAPTURA =====================
function MT-Paths {
    @{
        Mm      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        Vxd     = 'HKLM:\System\CurrentControlSet\Services\VxD\BIOS'
        Profile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Games   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
        Gfx     = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Thr     = 'HKLM:\SYSTEM\ControlSet001\Control\Power\PowerThrottling'
        PsCs1   = 'HKLM:\SYSTEM\ControlSet001\Control\Power\PowerSettings'
        PsCs    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
    }
}

# Valores de optimizacion (captura + pack)
function MT-OptimizationItems {
    $p = MT-Paths
    return @(
        (New-MTDw $p.Mm 'ClearPageFileAtShutdown' 0),
        (New-MTDw $p.Mm 'DisablePagingExecutive' 1),
        (New-MTDw $p.Mm 'LargeSystemCache' 0),
        (New-MTDw $p.Mm 'SecondLevelDataCache' 1024),
        (New-MTDw $p.Vxd 'FastDRAM' 1),
        (New-MTDw $p.Vxd 'CPUPriority' 1),
        (New-MTDw $p.Profile 'NetworkThrottlingIndex' -1),
        (New-MTDw $p.Profile 'SystemResponsiveness' 0),
        (New-MTDw $p.Gfx 'HwSchMode' 2),
        (New-MTDw $p.Thr 'PowerThrottlingOff' 1),
        (New-MTDw "$($p.PsCs1)\5FB4938D-1EE8-4b0f-9A3C-5036B0AB995C\DD848B2A-8A5D-4451-9AE2-39CD41658F6C" 'Attributes' 2),
        (New-MTDw "$($p.PsCs1)\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7" 'Attributes' 2),
        (New-MTDw "$($p.PsCs)\54533251-82be-4824-96c1-47b60b740d00\943c8cb6-6f93-4227-ad87-e9a3feec08d1" 'Attributes' 2),
        (New-MTDw "$($p.PsCs)\2a737441-1930-4402-8d77-b2bebba308a3\d4e98f31-5ffe-4ce1-be31-1b38b384c009" 'Attributes' 2)
    )
}

# Perfil de juego: 1 = bajos, 2 = medios y altos (optimizar_juego__bajos_.reg / medios-altos_.reg)
function MT-GameItems {
    param([Parameter(Mandatory = $true)][ValidateSet(1, 2)][int]$Profile)
    $games = (MT-Paths).Games
    $prio  = if ($Profile -eq 1) { 6 } else { 8 }
    return @(
        (New-MTDw $games 'Affinity' 0),
        (New-MTSt $games 'Background Only' 'False'),
        (New-MTDw $games 'Clock Rate' 10000),
        (New-MTDw $games 'GPU Priority' $prio),
        (New-MTDw $games 'Priority' $prio),
        (New-MTSt $games 'Scheduling Category' 'High'),
        (New-MTSt $games 'SFIO Priority' 'High')
    )
}

# Valores predeterminados (default.reg)
function MT-DefaultItems {
    $p = MT-Paths
    return @(
        (New-MTDw $p.Profile 'NetworkThrottlingIndex' 10),
        (New-MTDw $p.Profile 'SystemResponsiveness' 20),
        (New-MTDw $p.Games 'Affinity' 0),
        (New-MTSt $p.Games 'Background Only' 'False'),
        (New-MTDw $p.Games 'Clock Rate' 10000),
        (New-MTDw $p.Games 'GPU Priority' 6),
        (New-MTDw $p.Games 'Priority' 2),
        (New-MTSt $p.Games 'Scheduling Category' 'Medium'),
        (New-MTSt $p.Games 'SFIO Priority' 'Normal'),
        (New-MTDw $p.Mm 'ClearPageFileAtShutdown' 0),
        (New-MTDw $p.Mm 'DisablePagingExecutive' 0),
        (New-MTDw $p.Mm 'LargeSystemCache' 0),
        (New-MTDw $p.Mm 'SecondLevelDataCache' 512),
        (New-MTDw $p.Vxd 'FastDRAM' 3),
        (New-MTDw $p.Vxd 'CPUPriority' 3),
        (New-MTDw $p.Gfx 'HwSchMode' 0),
        (New-MTDel $p.Thr 'PowerThrottlingOff')
    )
}

# Todo lo que se guarda antes de cambiar nada
function MT-AllTrackedItems {
    $list = New-Object System.Collections.ArrayList
    foreach ($i in (MT-OptimizationItems)) { [void]$list.Add($i) }
    foreach ($i in (MT-DefaultItems)) { [void]$list.Add($i) }
    [void]$list.Add((New-MTDw 'HKLM:\SYSTEM\ControlSet001\Control' 'SvcHostSplitThresholdInKB' 0))
    [void]$list.Add((New-MTDw 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' 'Start' 0))
    return @($list)
}

# ===================== TAREAS DE OPTIMIZACION =====================
function MT-GetTasks {
    param([Parameter(Mandatory = $true)][int]$GameProfile)
    $gameDesc = if ($GameProfile -eq 1) { 'Perfil bajos (prioridad 6).' } else { 'Perfil medios y altos (prioridad 8).' }
    return @(
        (New-MTTask -Module 'Juegos' -Name 'Perfil de juego' -Description $gameDesc `
            -Items (MT-GameItems -Profile $GameProfile)),

        (New-MTTask -Module 'Registro' -Name 'Valores de optimizacion' `
            -Description 'Memoria, respuesta del sistema, GPU, limitacion de energia, planes y USB (captura y pack).' `
            -Items (MT-OptimizationItems)),

        (New-MTTask -Module 'Registro' -Name 'SvcHostSplitThresholdInKB' `
            -Description 'Valor = (RAM en GB x 1024) x 1024 en HKLM\SYSTEM\ControlSet001\Control.' -Action {
                $bytes = [int64]((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory)
                $gb    = [math]::Round($bytes / 1GB)
                $value = MT-SvcHostValue -GB $gb
                MT-Log -Level INFO -Message "RAM detectada: $gb GB. Valor aplicado: $value"
                MT-AddRegBackup -Path 'HKLM:\SYSTEM\ControlSet001\Control' -Name 'SvcHostSplitThresholdInKB'
                MT-SetReg -Path 'HKLM:\SYSTEM\ControlSet001\Control' -Name 'SvcHostSplitThresholdInKB' -Value $value
            }),

        (New-MTTask -Module 'Energia' -Name 'Plan de energia' `
            -Description 'Duplica e9a42b02-d5df-448d-aa00-03f14749eb61. Si falla, usa C:\briefrenzo.pow.' -Action {
                $done = $false
                try {
                    $out = (& powercfg.exe -duplicatescheme 'e9a42b02-d5df-448d-aa00-03f14749eb61' 2>&1) | Out-String
                    if ($LASTEXITCODE -ne 0) { throw "powercfg codigo $LASTEXITCODE. $out" }
                    $m = [regex]::Match($out, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
                    if (-not $m.Success) { throw 'No se pudo leer el GUID del plan creado.' }
                    MT-Log -Level OK -Message "Plan duplicado: $($m.Value)"
                    $done = $true
                }
                catch {
                    MT-Log -Level WARN -Message "Plan principal no disponible: $($_.Exception.Message) Se usa el plan alternativo."
                }
                if (-not $done) {
                    if (-not (Test-Path -LiteralPath 'C:\briefrenzo.pow')) { throw 'Plan alternativo no disponible: falta C:\briefrenzo.pow.' }
                    $imp = (& powercfg.exe /import 'C:\briefrenzo.pow' 2>&1) | Out-String
                    if ($LASTEXITCODE -ne 0) { throw "Plan alternativo fallo (codigo $LASTEXITCODE): $imp" }
                    MT-Log -Level OK -Message 'Plan alternativo importado.'
                }
            }),

        (New-MTTask -Module 'Servicios' -Name 'DiagTrack (telemetria)' `
            -Description 'ADVERTENCIA: deshabilita la experiencia de usuario y telemetria asociadas.' -Action {
                $svc = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue
                if (-not $svc) {
                    $global:MTSkipReason = 'El servicio DiagTrack no existe en este equipo.'
                    return
                }
                MT-AddRegBackup -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' -Name 'Start'
                Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction Stop
                Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
                $s = Get-Service -Name 'DiagTrack' -ErrorAction Stop
                if ($s.StartType -ne 'Disabled') { throw "Tipo de inicio actual: $($s.StartType)." }
            }),

        (New-MTTask -Module 'Sistema' -Name 'Paquetes de Group Policy (gpedit)' `
            -Description 'Instala los paquetes ClientExtensions y ClientTools con DISM (gpedit windows 11.bat).' -Action {
                $dir  = Join-Path $env:SystemRoot 'servicing\Packages'
                $pkgs = @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft-Windows-GroupPolicy-ClientExtensions-Package~3*.mum' -ErrorAction SilentlyContinue) +
                        @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft-Windows-GroupPolicy-ClientTools-Package~3*.mum' -ErrorAction SilentlyContinue)
                if ($pkgs.Count -eq 0) { throw 'No se encontraron paquetes de Group Policy en servicing\Packages.' }
                foreach ($p in $pkgs) {
                    $null = & dism.exe /online /norestart "/add-package:$($p.FullName)" 2>&1
                    if ($LASTEXITCODE -notin 0, 3010) { throw "DISM fallo con $($p.Name) (codigo $LASTEXITCODE)." }
                }
                MT-Log -Level OK -Message "Paquetes instalados: $($pkgs.Count)"
            }),

        (New-MTTask -Module 'Sistema' -Name 'DISM CheckHealth / RestoreHealth' `
            -Description 'checkhealth; restorehealth solo si detecta errores reparables.' -Action {
                $check = (& dism.exe /online /cleanup-image /checkhealth 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) { throw "checkhealth fallo (codigo $LASTEXITCODE)." }
                switch (MT-DismState -Output $check) {
                    'Healthy' { MT-Log -Level OK -Message 'DISM: sin errores en el almacen de componentes.' }
                    'Repairable' {
                        MT-Log -Level WARN -Message 'DISM: errores reparables. Ejecutando RestoreHealth...'
                        $null = & dism.exe /online /cleanup-image /restorehealth 2>&1
                        if ($LASTEXITCODE -ne 0) { throw "restorehealth fallo (codigo $LASTEXITCODE)." }
                    }
                    default { throw 'No se pudo interpretar la salida de checkhealth.' }
                }
            }),

        (New-MTTask -Module 'Limpieza' -Name 'Liberador de espacio (cleanmgr)' `
            -Description 'cleanmgr /sagerun:65535 (solo tiene efecto si el perfil 65535 esta configurado).' -Action {
                $null = & cleanmgr.exe /sagerun:65535 2>&1
            }),

        (New-MTTask -Module 'Limpieza' -Name 'Limpiar temporales' `
            -Description 'Vacia C:\Windows\Temp y %TEMP% (solo contenido) y limpia la cache DNS.' -Action {
                $null = & ipconfig.exe /flushdns 2>&1
                $removed = 0; $skipped = 0
                foreach ($dir in @('C:\Windows\Temp', $env:TEMP)) {
                    if ([string]::IsNullOrEmpty($dir) -or -not (Test-Path -LiteralPath $dir)) { continue }
                    foreach ($it in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
                        try { Remove-Item -LiteralPath $it.FullName -Recurse -Force -ErrorAction Stop; $removed++ }
                        catch { $skipped++ }
                    }
                }
                MT-Log -Level INFO -Message "Eliminados: $removed. Omitidos (en uso): $skipped."
            })
    )
}

# ===================== EJECUCION =====================
function MT-RunTasks {
    param([object[]]$Tasks)
    $results = New-Object System.Collections.ArrayList
    $total = $Tasks.Count
    $i = 0
    foreach ($t in $Tasks) {
        $i++
        Write-Progress -Activity 'ManuTweaks' -Status "$($t.Module): $($t.Name)" -PercentComplete ([int](100 * $i / $total))
        if ($global:MTProgress) { $global:MTProgress.Value = [int](100 * $i / $total) }
        MT-Log -Level INFO -Message "[$i/$total] $($t.Module) > $($t.Name)"
        try {
            foreach ($item in $t.Items) { MT-ApplyItem -Item $item }
            $global:MTSkipReason = $null
            if ($t.Action) { & $t.Action }
            if ($global:MTSkipReason) {
                [void]$results.Add([pscustomobject]@{ Module = $t.Module; Name = $t.Name; Status = 'Omitida'; Detail = $global:MTSkipReason })
                MT-Log -Level WARN -Message "$($t.Name) omitida: $($global:MTSkipReason)"
            }
            else {
                [void]$results.Add([pscustomobject]@{ Module = $t.Module; Name = $t.Name; Status = 'Correcta'; Detail = '' })
                MT-Log -Level OK -Message "$($t.Name) completada."
            }
        }
        catch {
            $msg = $_.Exception.Message
            [void]$results.Add([pscustomobject]@{ Module = $t.Module; Name = $t.Name; Status = 'Error'; Detail = $msg })
            MT-Log -Level ERROR -Message "$($t.Name): $msg"
        }
    }
    Write-Progress -Activity 'ManuTweaks' -Completed
    return @($results)
}

function MT-Summary {
    param([object[]]$Results)
    $ok     = @($Results | Where-Object { $_.Status -eq 'Correcta' })
    $errors = @($Results | Where-Object { $_.Status -eq 'Error' })
    $skip   = @($Results | Where-Object { $_.Status -eq 'Omitida' })
    MT-Section 'Resumen'
    MT-Log -Level OK -Message "Correctas: $($ok.Count)"
    MT-Log -Level WARN -Message "Omitidas: $($skip.Count)"
    foreach ($o in $skip) { MT-Log -Level WARN -Message "  - $($o.Name): $($o.Detail)" }
    if ($errors.Count -gt 0) {
        MT-Log -Level ERROR -Message "Errores: $($errors.Count)"
        foreach ($e in $errors) { MT-Log -Level ERROR -Message "  - $($e.Name): $($e.Detail)" }
    }
    else {
        MT-Log -Level OK -Message 'Errores: 0'
    }
}

function MT-StartSession {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    New-Item -ItemType Directory -Path $MTLogDir -Force | Out-Null
    $global:MTSessionDir = Join-Path $MTBackupDir $stamp
    New-Item -ItemType Directory -Path $global:MTSessionDir -Force | Out-Null
    $global:MTLogFile = Join-Path $MTLogDir "ManuTweaks_$stamp.log"
    $global:MTBackup  = New-Object System.Collections.ArrayList

    MT-Section 'Preparacion'
    MT-Log -Level INFO -Message "Registro de actividad: $global:MTLogFile"

    try {
        Checkpoint-Computer -Description 'ManuTweaks' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        MT-Log -Level OK -Message 'Punto de restauracion creado.'
    }
    catch {
        MT-Log -Level WARN -Message "Punto de restauracion no creado: $($_.Exception.Message)"
    }

    foreach ($i in (MT-AllTrackedItems)) { MT-AddRegBackup -Path $i.Path -Name $i.Name }
    $snapshot = Join-Path $global:MTSessionDir 'snapshot_previo.json'
    ConvertTo-Json -InputObject @($global:MTBackup) -Depth 5 | Set-Content -LiteralPath $snapshot -Encoding UTF8
    $global:MTBackup.Clear()
    MT-Log -Level OK -Message "Valores actuales guardados: $snapshot"
}

function MT-Execute {
    param([Parameter(Mandatory = $true)][int]$GameProfile)
    $results = MT-RunTasks -Tasks (MT-GetTasks -GameProfile $GameProfile)
    MT-Summary -Results $results
    MT-Log -Level INFO -Message "Log completo: $global:MTLogFile"
}

function MT-RestoreLast {
    $snap = $null
    foreach ($d in @(Get-ChildItem -LiteralPath $MTBackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $f = Join-Path $d.FullName 'snapshot_previo.json'
        if (Test-Path -LiteralPath $f) { $snap = $f; break }
    }
    if (-not $snap) { MT-Log -Level WARN -Message 'No hay ninguna copia guardada para restaurar.'; return }
    MT-Log -Level INFO -Message "Restaurando valores de: $snap"
    MT-Restore -ManifestPath $snap
}


# ===================== FLUJO PRINCIPAL =====================


# ===================== REGISTRO DE ACTIVIDAD =====================
function MT-Log {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($global:MTLogFile) { Add-Content -LiteralPath $global:MTLogFile -Value $line -Encoding UTF8 }
    $tag = switch ($Level) {
        'OK'    { '[ OK ]' }
        'WARN'  { '[WARN]' }
        'ERROR' { '[FAIL]' }
        'DEBUG' { '[ .. ]' }
        default { '[INFO]' }
    }
    if ($global:MTRichBox) {
        $colors = @{ OK = 'LightGreen'; WARN = 'Gold'; ERROR = 'Tomato'; DEBUG = 'Gray'; INFO = 'LightSkyBlue' }
        $box = $global:MTRichBox
        $box.SelectionStart  = $box.TextLength
        $box.SelectionLength = 0
        $box.SelectionColor  = [System.Drawing.Color]::FromName($colors[$Level])
        $box.SelectedText    = "$tag $Message`r`n"
        $box.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        $c = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'DEBUG' { 'DarkGray' } default { 'Cyan' } }
        Write-Host ('  ' + $tag + ' ' + $Message) -ForegroundColor $c
    }
}

function MT-Section {
    param([string]$Title)
    MT-Log -Level INFO -Message ('=== ' + $Title + ' ===')
}

# ===================== INTERFAZ GRAFICA =====================
function MT-Color {
    param([int]$R, [int]$G, [int]$B)
    [System.Drawing.Color]::FromArgb($R, $G, $B)
}

function MT-NewButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [System.Drawing.Color]$Back)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, $H)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $Back
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $b
}

function MT-GuiBusy {
    param([bool]$Busy)
    foreach ($b in $global:MTButtons) { $b.Enabled = -not $Busy }
    [System.Windows.Forms.Application]::DoEvents()
}

function MT-AskPassword {
    $navy = MT-Color 10 25 47
    $light = MT-Color 214 230 250
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'ManuTweaks - Acceso'
    $dlg.ClientSize = New-Object System.Drawing.Size(380, 170)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.BackColor = $navy
    $dlg.ForeColor = $light
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Introduce la contrasena para continuar:'
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.AutoSize = $true

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(20, 50)
    $tb.Size = New-Object System.Drawing.Size(340, 28)
    $tb.PasswordChar = [char]'*'
    $tb.UseSystemPasswordChar = $false

    $ok = MT-NewButton 'Aceptar' 150 100 100 34 (MT-Color 0 102 204)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = MT-NewButton 'Cancelar' 260 100 100 34 (MT-Color 45 62 88)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel

    $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    $dlg.Add_Shown({ $tb.Focus() | Out-Null })
    $res = $dlg.ShowDialog()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $tb.Text
}

function MT-SetButtons {
    param([bool]$Enabled)
    foreach ($b in $global:MTButtons) { $b.Enabled = $Enabled }
    [System.Windows.Forms.Application]::DoEvents()
}

function MT-ShowMain {
    $navy  = MT-Color 16 28 48
    $blue  = MT-Color 0 102 204
    $grey  = MT-Color 55 70 95
    $red   = MT-Color 150 40 40
    $light = MT-Color 225 235 250
    $muted = MT-Color 150 175 210
    $logBg = MT-Color 8 16 30

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ManuTweaks'
    $form.ClientSize = New-Object System.Drawing.Size(560, 520)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.BackColor = $navy
    $form.ForeColor = $light
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $global:MTForm = $form

    $title = MT-NewLabel 'ManuTweaks' 20 14 ([System.Drawing.Color]::White) 18 'Bold'
    $sub   = MT-NewLabel 'Optimizacion de Windows' 22 52 $muted 9

    $lblPerfil = MT-NewLabel 'Perfil de juego' 20 92 $light 10 'Bold'
    $rbLow = New-Object System.Windows.Forms.RadioButton
    $rbLow.Text = 'Bajos'
    $rbLow.Location = New-Object System.Drawing.Point(20, 118)
    $rbLow.AutoSize = $true
    $rbLow.Checked = $true
    $rbLow.ForeColor = $light
    $rbHigh = New-Object System.Windows.Forms.RadioButton
    $rbHigh.Text = 'Medios y altos'
    $rbHigh.Location = New-Object System.Drawing.Point(120, 118)
    $rbHigh.AutoSize = $true
    $rbHigh.ForeColor = $light
    $global:MTRadioLow = $rbLow

    $btnRun  = MT-NewButton 'Iniciar optimizacion' 20 160 250 42 $blue
    $btnRst  = MT-NewButton 'Restaurar' 290 160 250 42 $grey
    $btnExit = MT-NewButton 'Salir' 20 212 520 36 $red

    $rich = New-Object System.Windows.Forms.RichTextBox
    $rich.Location = New-Object System.Drawing.Point(20, 264)
    $rich.Size = New-Object System.Drawing.Size(520, 236)
    $rich.ReadOnly = $true
    $rich.BackColor = $logBg
    $rich.ForeColor = $light
    $rich.BorderStyle = 'FixedSingle'
    $rich.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $global:MTRichBox = $rich

    $global:MTButtons = @($btnRun, $btnRst, $btnExit, $rbLow, $rbHigh)

    $btnRun.Add_Click({
        $pregunta = 'Se aplicaran los ajustes de optimizacion. Antes se guardaran los valores actuales. Continuar?'
        $res = [System.Windows.Forms.MessageBox]::Show($pregunta, 'ManuTweaks',
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($res -ne [System.Windows.Forms.DialogResult]::Yes) {
            MT-Log -Level INFO -Message 'Cancelado. No se ha aplicado nada.'
            return
        }
        $perfil = if ($global:MTRadioLow.Checked) { 1 } else { 2 }
        MT-SetButtons $false
        try { MT-Execute -GameProfile $perfil }
        catch { MT-Log -Level ERROR -Message ('Fallo inesperado: ' + $_.Exception.Message) }
        finally { MT-SetButtons $true }
        [System.Windows.Forms.MessageBox]::Show('Proceso terminado. Revisa el registro.', 'ManuTweaks',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })

    $btnRst.Add_Click({
        $pregunta = 'Restaurar los valores guardados en la ultima sesion?'
        $res = [System.Windows.Forms.MessageBox]::Show($pregunta, 'ManuTweaks',
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        MT-SetButtons $false
        try { MT-RestoreLast }
        catch { MT-Log -Level ERROR -Message ('Fallo al restaurar: ' + $_.Exception.Message) }
        finally { MT-SetButtons $true }
    })

    $btnExit.Add_Click({
        $global:MTExitShell = $true
        $global:MTForm.Close()
    })

    $form.Add_Shown({
        MT-SetButtons $false
        try { MT-StartSession } finally { MT-SetButtons $true }
    })

    $form.Controls.AddRange(@($title, $sub, $lblPerfil, $rbLow, $rbHigh, $btnRun, $btnRst, $btnExit, $rich))
    [void]$form.ShowDialog()

    $global:MTRichBox = $null
    $global:MTButtons = $null
}


function MT-Main {
    if (-not (MT-IsAdmin)) {
        if ($ManuTweaksUrl -like '*TU-URL*') {
            Write-Host 'Configura $ManuTweaksUrl con la URL raw de este archivo.' -ForegroundColor Red
            return
        }
        Write-Host 'Se necesitan permisos de administrador. Se abrira una ventana elevada (UAC)...' -ForegroundColor Yellow
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ErrorAction Stop `
                -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -Command "irm ''{0}'' | iex"' -f $ManuTweaksUrl)
        }
        catch {
            Write-Host 'No se ha concedido la elevacion. No se ha hecho ningun cambio.' -ForegroundColor Red
        }
        return
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $typed = MT-AskPassword
    if ($null -eq $typed) { return }
    $ok = MT-TestPassword -Password $typed
    $typed = $null
    if (-not $ok) {
        [System.Windows.Forms.MessageBox]::Show('Contrasena incorrecta. No se ha hecho ningun cambio.', 'ManuTweaks',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    MT-ShowMain
    if ($global:MTExitShell) { exit }
}

if (-not $env:MANUTWEAKS_NO_RUN) { MT-Main }
