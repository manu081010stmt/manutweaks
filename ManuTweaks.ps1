# ManuTweaks - optimizacion de Windows 10 / 11
# Ejecucion:  iwr -useb <URL_RAW_DE_ESTE_ARCHIVO> | iex
# Los ajustes se aplican uno a uno. En cada paso puedes Aplicar, Omitir o Detener.
# Si un ajuste falla, se registra el error y se pasa al siguiente.

# ===================== CONFIGURACION =====================
$ManuTweaksUrl  = 'https://raw.githubusercontent.com/manu081010stmt/manutweaks/main/ManuTweaks.ps1'
$AuthSalt       = 'gWG6zurDC2jPONEdgp+P3w=='
$AuthHash       = 't87iufZq6+DB3TOZl9dp5CtXnx+cK5Jn4qM8ZuuMEno='
$AuthIterations = 210000

# ===================== REGISTRO DE ACTIVIDAD (solo ventana, sin archivos) =====================
function MT-Color {
    param([int]$R, [int]$G, [int]$B)
    [System.Drawing.Color]::FromArgb($R, $G, $B)
}

function MT-Log {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [Parameter(Mandatory = $true)][string]$Message
    )
    $tag = switch ($Level) { 'OK' { '[ OK ]' } 'WARN' { '[WARN]' } 'ERROR' { '[FAIL]' } default { '[INFO]' } }
    if ($global:MTRichBox) {
        $colors = @{ OK = 'LightGreen'; WARN = 'Gold'; ERROR = 'Tomato'; INFO = 'LightSkyBlue' }
        $box = $global:MTRichBox
        $box.SelectionStart  = $box.TextLength
        $box.SelectionLength = 0
        $box.SelectionColor  = [System.Drawing.Color]::FromName($colors[$Level])
        $box.SelectedText    = "$tag $Message`r`n"
        $box.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
    else {
        $c = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Cyan' } }
        Write-Host ('  ' + $tag + ' ' + $Message) -ForegroundColor $c
    }
}

# ===================== ADMIN Y CONTRASENA =====================
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

function MT-AskPassword {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'ManuTweaks - Acceso'
    $dlg.ClientSize = New-Object System.Drawing.Size(380, 170)
    $dlg.StartPosition = 'CenterScreen'
    $dlg.BackColor = MT-Color 16 28 48
    $dlg.ForeColor = MT-Color 225 235 250
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

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Aceptar'
    $ok.Location = New-Object System.Drawing.Point(150, 100)
    $ok.Size = New-Object System.Drawing.Size(100, 34)
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancelar'
    $cancel.Location = New-Object System.Drawing.Point(260, 100)
    $cancel.Size = New-Object System.Drawing.Size(100, 34)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Controls.AddRange(@($lbl, $tb, $ok, $cancel))
    $dlg.Add_Shown({ $tb.Focus() | Out-Null })
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $tb.Text
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
    param([Parameter(Mandatory = $true)][object[]]$Entries)
    $ok = 0; $fail = 0
    foreach ($e in $Entries) {
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

function MT-GameItems {
    param([Parameter(Mandatory = $true)][ValidateSet(1, 2)][int]$Profile)
    $games = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
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

# ===================== CATALOGO DE AJUSTES (orden de ejecucion) =====================
function New-MTTweak {
    param(
        [string]$Name,
        [string]$Description,
        [object[]]$Items = @(),
        [string[]]$Services = @(),
        [scriptblock]$Action,
        [bool]$Security = $false,
        [string]$Warning = ''
    )
    [pscustomobject]@{
        Name = $Name; Description = $Description; Items = $Items; Services = $Services
        Action = $Action; Security = $Security; Warning = $Warning
    }
}

# Servicios que se deshabilitan (tambien se guardan en la copia de la sesion)
function MT-ServiceNames {
    return @('SysMain', 'DiagTrack', 'diagnosticshub.standardcollector.service', 'dmwappushservice', 'DcpSvc', 'WSearch')
}

function MT-Tweaks {
    $hklmSys   = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $mm        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    $vxd       = 'HKLM:\System\CurrentControlSet\Services\VxD\BIOS'
    $profile   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $pwr1      = 'HKLM:\SYSTEM\ControlSet001\Control\Power\PowerSettings'
    $pwr2      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
    $gbHkcu    = 'HKCU:\Software\Microsoft\GameBar'
    $dvrHkcu   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    $cfgHkcu   = 'HKCU:\System\GameConfigStore'
    $advHkcu   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $defPol    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
    $svcBase   = 'HKLM:\SYSTEM\CurrentControlSet\Services'

    return @(
        # ---------- Rendimiento y juegos ----------
        (New-MTTweak -Name 'Memoria RAM y cache' -Description 'Gestion de memoria, cache de segundo nivel y prioridad VxD / BIOS.' -Items @(
            (New-MTDw $mm 'ClearPageFileAtShutdown' 0),
            (New-MTDw $mm 'DisablePagingExecutive' 1),
            (New-MTDw $mm 'LargeSystemCache' 0),
            (New-MTDw $mm 'SecondLevelDataCache' 1024),
            (New-MTDw $vxd 'FastDRAM' 1),
            (New-MTDw $vxd 'CPUPriority' 1)
        )),

        (New-MTTweak -Name 'Limite de red y respuesta del sistema' -Description 'Quita el limite de trafico de red de multimedia y prioriza la respuesta del sistema.' -Items @(
            (New-MTDw $profile 'NetworkThrottlingIndex' -1),
            (New-MTDw $profile 'SystemResponsiveness' 0)
        )),

        (New-MTTweak -Name 'SvcHostSplitThresholdInKB' -Description 'Umbral de procesos svchost = (RAM en GB x 1024) x 1024.' -Action {
            $bytes = [int64]((Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory)
            $gb    = [math]::Round($bytes / 1GB)
            $value = MT-SvcHostValue -GB $gb
            MT-Log -Level INFO -Message "RAM detectada: $gb GB. Valor aplicado: $value"
            MT-AddRegBackup -Path $hklmSys -Name 'SvcHostSplitThresholdInKB'
            MT-SetReg -Path 'HKLM:\SYSTEM\ControlSet001\Control' -Name 'SvcHostSplitThresholdInKB' -Value $value
        }),

        (New-MTTweak -Name 'Modo juego y programacion de GPU' -Description 'Activa el modo juego y la programacion de GPU acelerada por hardware (requiere reinicio).' -Items @(
            (New-MTDw 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2),
            (New-MTDw $gbHkcu 'AllowAutoGameMode' 1),
            (New-MTDw $gbHkcu 'AutoGameModeEnabled' 1),
            (New-MTDw $cfgHkcu 'GameDVR_FSEBehaviorMode' 2)
        )),

        (New-MTTweak -Name 'Desactivar Game Bar' -Description 'Desactiva la captura de Game Bar y su menu de acceso rapido.' -Items @(
            (New-MTDw $dvrHkcu 'AppCaptureEnabled' 0),
            (New-MTDw $dvrHkcu 'AudioCaptureEnabled' 0),
            (New-MTDw $dvrHkcu 'CursorCaptureEnabled' 0),
            (New-MTDw $gbHkcu 'UseNexusForGameBarEnabled' 0),
            (New-MTDw $gbHkcu 'ShowStartupPanel' 0),
            (New-MTDw $cfgHkcu 'GameDVR_Enabled' 0),
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0)
        )),

        (New-MTTweak -Name 'Perfil de juego (bajos)' -Description 'Prioridad de GPU y CPU para juegos (perfil bajos).' -Items (MT-GameItems -Profile 1)),

        (New-MTTweak -Name 'Ajustes de energia del procesador y USB' -Description 'Limitacion de energia, GPU, procesador y enlace USB 3 en el plan de energia.' -Items @(
            (New-MTDw 'HKLM:\SYSTEM\ControlSet001\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1),
            (New-MTDw "$pwr1\5FB4938D-1EE8-4b0f-9A3C-5036B0AB995C\DD848B2A-8A5D-4451-9AE2-39CD41658F6C" 'Attributes' 2),
            (New-MTDw "$pwr1\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7" 'Attributes' 2),
            (New-MTDw "$pwr2\54533251-82be-4824-96c1-47b60b740d00\943c8cb6-6f93-4227-ad87-e9a3feec08d1" 'Attributes' 2),
            (New-MTDw "$pwr2\2a737441-1930-4402-8d77-b2bebba308a3\d4e98f31-5ffe-4ce1-be31-1b38b384c009" 'Attributes' 2)
        )),

        (New-MTTweak -Name 'Plan de energia de alto rendimiento' -Description 'Duplica el plan e9a42b02... Si falla, usa C:\briefrenzo.pow (no activa el plan).' -Action {
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

        # ---------- Ahorro de recursos ----------
        (New-MTTweak -Name 'Desactivar Superfetch' -Description 'Deja de precargar apps en RAM. Ahorra disco, sobre todo en HDD.' -Services @('SysMain') -Items @(
            (New-MTDw "$mm\PrefetchParameters" 'EnableSuperfetch' 0),
            (New-MTDw "$mm\PrefetchParameters" 'EnablePrefetcher' 0)
        )),

        (New-MTTweak -Name 'Desactivar telemetria (servicios)' -Description 'Detiene los servicios que envian datos de uso y diagnostico a Microsoft.' -Services @('DiagTrack', 'diagnosticshub.standardcollector.service', 'dmwappushservice', 'DcpSvc') -Items @(
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0)
        )),

        (New-MTTweak -Name 'Desactivar tareas programadas de telemetria' -Description 'Desactiva tareas de experiencia de compatibilidad, CEIP y diagnostico de disco.' -Action {
            $tasks = @(
                @{ P = '\Microsoft\Windows\Application Experience\'; N = 'Microsoft Compatibility Appraiser' },
                @{ P = '\Microsoft\Windows\Application Experience\'; N = 'ProgramDataUpdater' },
                @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'Consolidator' },
                @{ P = '\Microsoft\Windows\Customer Experience Improvement Program\'; N = 'UsbCeip' },
                @{ P = '\Microsoft\Windows\DiskDiagnostic\'; N = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
            )
            $count = 0
            foreach ($t in $tasks) {
                if (Get-ScheduledTask -TaskPath $t.P -TaskName $t.N -ErrorAction SilentlyContinue) {
                    Disable-ScheduledTask -TaskPath $t.P -TaskName $t.N -ErrorAction Stop | Out-Null
                    $count++
                }
            }
            if ($count -eq 0) { $global:MTSkipReason = 'No se encontro ninguna tarea de telemetria.' }
            else { MT-Log -Level OK -Message "Tareas desactivadas: $count" }
        }),

        (New-MTTweak -Name 'Desactivar indexado de busqueda' -Description 'Detiene el servicio de indexado de Windows Search. La busqueda sera mas lenta.' -Services @('WSearch')),

        (New-MTTweak -Name 'Ocultar Widgets' -Description 'Quita el icono y el panel de Widgets de la barra de tareas.' -Items @(
            (New-MTDw $advHkcu 'TaskbarDa' 0)
        )),

        (New-MTTweak -Name 'Ocultar Chat' -Description 'Quita el icono de Chat de la barra de tareas y desactiva Meet Now.' -Items @(
            (New-MTDw $advHkcu 'TaskbarMn' 0),
            (New-MTDw 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'HideSCAMeetNow' 1)
        )),

        (New-MTTweak -Name 'Desactivar Copilot' -Description 'Oculta el boton de Copilot y desactiva Copilot en Windows y en Edge.' -Items @(
            (New-MTDw $advHkcu 'ShowCopilotButton' 0),
            (New-MTDw 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1),
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1)
        )),

        # ---------- Mantenimiento ----------
        (New-MTTweak -Name 'Editor de directivas de grupo (gpedit)' -Description 'Instala los paquetes de Group Policy con DISM (util en Windows Home).' -Action {
            $dir  = Join-Path $env:SystemRoot 'servicing\Packages'
            $pkgs = @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft-Windows-GroupPolicy-ClientExtensions-Package~3*.mum' -ErrorAction SilentlyContinue) +
                    @(Get-ChildItem -LiteralPath $dir -Filter 'Microsoft-Windows-GroupPolicy-ClientTools-Package~3*.mum' -ErrorAction SilentlyContinue)
            if ($pkgs.Count -eq 0) { throw 'No se encontraron paquetes de Group Policy.' }
            foreach ($pkg in $pkgs) {
                $null = & dism.exe /online /norestart "/add-package:$($pkg.FullName)" 2>&1
                if ($LASTEXITCODE -notin 0, 3010) { throw "DISM fallo con $($pkg.Name) (codigo $LASTEXITCODE)." }
            }
            MT-Log -Level OK -Message "Paquetes instalados: $($pkgs.Count)"
        }),

        (New-MTTweak -Name 'Reparar archivos del sistema (DISM)' -Description 'Comprueba el almacen de componentes y repara solo si detecta errores reparables.' -Action {
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

        (New-MTTweak -Name 'Liberador de espacio (cleanmgr)' -Description 'Ejecuta el liberador de espacio con el perfil 65535 (solo tiene efecto si esta configurado).' -Action {
            $null = & cleanmgr.exe /sagerun:65535 2>&1
        }),

        (New-MTTweak -Name 'Limpiar temporales' -Description 'Vacia C:\Windows\Temp y %TEMP% (solo contenido) y limpia la cache DNS.' -Action {
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
        }),

        # ---------- Seguridad (requieren confirmacion expresa) ----------
        (New-MTTweak -Name 'Desactivar Windows Defender' -Security $true `
            -Description 'Desactiva el antivirus y antispyware de Windows Defender mediante directivas.' `
            -Warning 'Tu equipo quedara sin antivirus integrado. Si Proteccion contra alteraciones esta activa, Windows puede revertir el cambio.' -Items @(
            (New-MTDw $defPol 'DisableAntiVirus' 1),
            (New-MTDw $defPol 'DisableAntiSpyware' 1),
            (New-MTDw $defPol 'DisableRealtimeMonitoring' 1),
            (New-MTDw $defPol 'DisableSpecialRunningModes' 1),
            (New-MTDw $defPol 'DisableRoutinelyTakingAction' 1),
            (New-MTDw $defPol 'ServiceKeepAlive' 0),
            (New-MTDw $defPol 'PUAProtection' 0),
            (New-MTDw "$defPol\Real-Time Protection" 'DisableRealtimeMonitoring' 1),
            (New-MTDw "$defPol\Real-Time Protection" 'DisableBehaviorMonitoring' 1),
            (New-MTDw "$defPol\Real-Time Protection" 'DisableOnAccessProtection' 1),
            (New-MTDw "$defPol\Real-Time Protection" 'DisableScanOnRealtimeEnable' 1),
            (New-MTDw "$defPol\Real-Time Protection" 'DisableIOAVProtection' 1),
            (New-MTDw "$defPol\Policy Manager" 'DisableScanningNetworkFiles' 1)
        )),

        (New-MTTweak -Name 'Desactivar SmartScreen' -Security $true `
            -Description 'Desactiva el filtro de SmartScreen que bloquea descargas y sitios peligrosos.' `
            -Warning 'Dejaras de recibir avisos al abrir archivos descargados y sitios maliciosos conocidos.' -Items @(
            (New-MTSt 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off'),
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' 0),
            (New-MTSt 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'ShellSmartScreenLevel' 'Warn')
        )),

        (New-MTTweak -Name 'Desactivar VBS (seguridad basada en virtualizacion)' -Security $true `
            -Description 'Desactiva la proteccion del nucleo por virtualizacion. Mejora rendimiento en algunos equipos.' `
            -Warning 'Reduce la proteccion del nucleo frente a drivers maliciosos. Requiere reinicio.' -Items @(
            (New-MTDw 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0)
        )),

        (New-MTTweak -Name 'Desactivar Restaurar sistema' -Security $true `
            -Description 'Impide crear nuevos puntos de restauracion. No borra los puntos que ya existan.' `
            -Warning 'Ya no podras crear puntos de restauracion de Windows. Crea uno antes de continuar si lo necesitas.' -Items @(
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' 'DisableSR' 1),
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' 'DisableConfig' 1)
        )),

        (New-MTTweak -Name 'Desinstalar OneDrive' -Security $true `
            -Description 'Desinstala el cliente de OneDrive y desactiva su sincronizacion. No borra tus carpetas ni archivos.' `
            -Warning 'Los archivos que solo estan en la nube dejaran de sincronizarse. Asegurate de tener copias antes de continuar.' -Items @(
            (New-MTDw 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1)
        ) -Action {
            $setup = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe") |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $setup) { $global:MTSkipReason = 'OneDrive no esta instalado en este equipo.'; return }
            $proc = Start-Process -FilePath $setup -ArgumentList '/uninstall' -PassThru
            if (-not $proc.WaitForExit(180000)) { throw 'La desinstalacion de OneDrive no termino en 3 minutos.' }
            MT-Log -Level OK -Message 'Cliente de OneDrive desinstalado.'
        })
    )
}

# ===================== EJECUCION UNO A UNO =====================
function MT-DisableService {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        MT-Log -Level WARN -Message "El servicio $Name no existe en este equipo. Omitido."
        return
    }
    MT-ApplyItem -Item (New-MTDw ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $Name) 'Start' 4)
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    MT-Log -Level OK -Message "Servicio $Name deshabilitado."
}

function MT-RunTweak {
    param([Parameter(Mandatory = $true)]$Tweak)
    MT-Log -Level INFO -Message "Aplicando: $($Tweak.Name)"
    $global:MTSkipReason = $null
    try {
        foreach ($item in $Tweak.Items) { MT-ApplyItem -Item $item }
        foreach ($svc in $Tweak.Services) { MT-DisableService -Name $svc }
        if ($Tweak.Action) { & $Tweak.Action }
        if ($global:MTSkipReason) {
            MT-Log -Level WARN -Message "$($Tweak.Name) omitido: $($global:MTSkipReason)"
            return 'Omitida'
        }
        MT-Log -Level OK -Message "$($Tweak.Name) completado."
        return 'Correcta'
    }
    catch {
        MT-Log -Level ERROR -Message "$($Tweak.Name) fallo: $($_.Exception.Message). Se continua con el siguiente."
        return 'Error'
    }
}

function MT-RunSequence {
    $tweaks = @(MT-Tweaks)
    $total  = $tweaks.Count
    $index  = 0
    $results = New-Object System.Collections.ArrayList

    foreach ($t in $tweaks) {
        $index++
        if ($t.Security) { MT-Log -Level WARN -Message "Ajuste de seguridad: $($t.Name). $($t.Warning)" }
        MT-Log -Level INFO -Message "[$index de $total] $($t.Name)"
        [void]$results.Add((MT-RunTweak -Tweak $t))
    }

    $ok   = @($results | Where-Object { $_ -eq 'Correcta' }).Count
    $skip = @($results | Where-Object { $_ -eq 'Omitida' }).Count
    $err  = @($results | Where-Object { $_ -eq 'Error' }).Count
    MT-Log -Level INFO -Message '=== RESUMEN ==='
    MT-Log -Level OK   -Message "Aplicados: $ok"
    MT-Log -Level WARN -Message "Omitidos: $skip"
    if ($err -gt 0) { MT-Log -Level ERROR -Message "Con error: $err" } else { MT-Log -Level OK -Message 'Con error: 0' }
}


# ===================== SESION: PUNTO DE RESTAURACION Y COPIA EN MEMORIA =====================
function MT-StartSession {
    $global:MTBackup = New-Object System.Collections.ArrayList
    MT-Log -Level INFO -Message 'Preparando sesion...'
    try {
        Checkpoint-Computer -Description 'ManuTweaks' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        MT-Log -Level OK -Message 'Punto de restauracion creado.'
    }
    catch {
        MT-Log -Level WARN -Message ('Punto de restauracion no creado: ' + $_.Exception.Message)
    }

    foreach ($t in (MT-Tweaks)) {
        foreach ($i in $t.Items) { MT-AddRegBackup -Path $i.Path -Name $i.Name }
    }
    foreach ($svc in (MT-ServiceNames)) {
        MT-AddRegBackup -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $svc) -Name 'Start'
    }
    $global:MTSnapshot = @($global:MTBackup)
    $global:MTBackup   = New-Object System.Collections.ArrayList
    MT-Log -Level OK -Message ('Valores actuales guardados en memoria (' + $global:MTSnapshot.Count + ').')
}

function MT-RestoreLast {
    if (-not $global:MTSnapshot -or $global:MTSnapshot.Count -eq 0) {
        MT-Log -Level WARN -Message 'No hay valores guardados en esta sesion.'
        return
    }
    MT-Log -Level INFO -Message 'Restaurando los valores guardados al abrir la ventana...'
    MT-Restore -Entries $global:MTSnapshot
}

# ===================== INTERFAZ =====================
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

function MT-NewLabel {
    param([string]$Text, [int]$X, [int]$Y, [System.Drawing.Color]$Color, [float]$Size = 10, [string]$Style = 'Regular')
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.ForeColor = $Color
    $l.AutoSize = $true
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]$Style)
    return $l
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
    $sub   = MT-NewLabel 'Optimizacion de Windows  |  manurust0' 22 52 $muted 9
    $perfil = MT-NewLabel 'Perfil de juego: Bajos' 20 92 $light 10 'Bold'

    $btnRun  = MT-NewButton 'Iniciar optimizacion' 20 124 250 42 $blue
    $btnRst  = MT-NewButton 'Restaurar' 290 124 250 42 $grey
    $btnExit = MT-NewButton 'Salir' 20 176 520 36 $red

    $rich = New-Object System.Windows.Forms.RichTextBox
    $rich.Location = New-Object System.Drawing.Point(20, 226)
    $rich.Size = New-Object System.Drawing.Size(520, 274)
    $rich.ReadOnly = $true
    $rich.BackColor = $logBg
    $rich.ForeColor = $light
    $rich.BorderStyle = 'FixedSingle'
    $rich.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $global:MTRichBox = $rich

    $global:MTButtons = @($btnRun, $btnRst, $btnExit)

    $btnRun.Add_Click({
        MT-SetButtons $false
        try { MT-RunSequence }
        catch { MT-Log -Level ERROR -Message ('Fallo inesperado: ' + $_.Exception.Message) }
        finally { MT-SetButtons $true }
    })

    $btnRst.Add_Click({
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

    $form.Controls.AddRange(@($title, $sub, $perfil, $btnRun, $btnRst, $btnExit, $rich))
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
