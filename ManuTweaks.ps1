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
    foreach ($t in @($global:OptiTweaks)) {
        foreach ($r in $t.Registry) { MT-AddRegBackup -Path $r.Path -Name $r.Name }
        foreach ($s in $t.Services) { MT-AddRegBackup -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $s.Name) -Name 'Start' }
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

$global:OptiScript_S02_Apply = @'
powercfg.exe /hibernate off
'@
$global:OptiScript_S02_Undo = @'
powercfg.exe /hibernate on
'@
$global:OptiScript_S03_Apply = @'
# Sometimes if you dont stop the Widgets process the removal may fail

      Get-Process *Widget* | Stop-Process
      Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers | Remove-AppxPackage -AllUsers
      Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers | Remove-AppxPackage -AllUsers

      Invoke-WinUtilExplorerUpdate -action "restart"
      Write-Host "Removed widgets"
'@
$global:OptiScript_S05_Apply = @'
icacls "$Env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db" /deny *S-1-1-0:F
'@
$global:OptiScript_S05_Undo = @'
icacls "$Env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db" /grant *S-1-1-0:F
'@
$global:OptiScript_S08_Apply = @'
# A threshold above the physical memory disables svchost service splitting
      $Memory = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name SvcHostSplitThresholdInKB -Value $Memory -Type DWord
'@
$global:OptiScript_S08_Undo = @'
# Windows client default (0x380000): splitting back on
      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name SvcHostSplitThresholdInKB -Value 3670016 -Type DWord -Force
'@
$global:OptiScript_S13_Apply = @'
# Disable Defender Auto Sample Submission
      try {
          Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop
      } catch {
          # Skip Defender error 0x800106ba when its service is unavailable; other errors must fail.
          if ($_.Exception.Message -notmatch '\b0x800106ba\b' -and $_.Exception.HResult -ne 0x800106BA) {
              throw
          }
          Write-Warning 'Defender sample submission preference could not be changed; Defender may be unavailable or disabled.'
          Write-WinUtilLog -Level 'WARN' -Component 'Script' -Message 'Defender sample submission preference could not be changed; Defender may be unavailable or disabled.'
      }

      # Disable PowerShell 7 telemetry
      [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
'@
$global:OptiScript_S13_Undo = @'
# Enable Defender Auto Sample Submission
      try {
          Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction Stop
      } catch {
          # Skip Defender error 0x800106ba when its service is unavailable; other errors must fail.
          if ($_.Exception.Message -notmatch '\b0x800106ba\b' -and $_.Exception.HResult -ne 0x800106BA) {
              throw
          }
          Write-Warning 'Defender sample submission preference could not be restored; Defender may be unavailable or disabled.'
          Write-WinUtilLog -Level 'WARN' -Component 'Script' -Message 'Defender sample submission preference could not be restored; Defender may be unavailable or disabled.'
      }

      # Enable PowerShell 7 telemetry
      [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '', 'Machine')
'@
$global:OptiScript_S15_Apply = @'
$EdgeAppDir = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application"
      $Path = $null
      if (Test-Path -LiteralPath $EdgeAppDir -ErrorAction Stop) {
          $InstallerPattern = Join-Path $EdgeAppDir "*\Installer\setup.exe"
          if (Test-Path -Path $InstallerPattern -ErrorAction Stop) {
              $Path = Resolve-Path -Path $InstallerPattern -ErrorAction Stop | Select-Object -Last 1
          }
      }

      if ($Path) {
          New-Item -Path "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe" -Force
          Start-Process -FilePath $Path -ArgumentList "--uninstall --system-level --force-uninstall --delete-profile" -Wait
          Write-Host "Microsoft Edge was removed"
      } else {
          Write-Host "Microsoft Edge is not installed"
      }
'@
$global:OptiScript_S15_Undo = @'
Write-Host "Installing Microsoft Edge..."
      winget install Microsoft.Edge --source winget
'@
$global:OptiScript_S16_Apply = @'
$bitLockerVolume = Get-BitLockerVolume -MountPoint $Env:SystemDrive -ErrorAction Stop

      if ($bitLockerVolume.VolumeStatus -eq 'FullyDecrypted') {
          Write-Host "BitLocker is already disabled on $($Env:SystemDrive)."
      } else {
          Disable-BitLocker -MountPoint $Env:SystemDrive -ErrorAction Stop
      }
'@
$global:OptiScript_S16_Undo = @'
Enable-BitLocker -MountPoint $Env:SystemDrive
'@
$global:OptiScript_S17_Apply = @'
$OneDrivePath = $Env:OneDrive
      $OneDriveFolderExists = -not [string]::IsNullOrWhiteSpace($OneDrivePath) -and (Test-Path -LiteralPath $OneDrivePath -PathType Container -ErrorAction Stop)

      if ($OneDriveFolderExists) {
          $OneDriveAcl = Get-Acl -LiteralPath $OneDrivePath -ErrorAction Stop
      } else {
          Write-Host "OneDrive folder is already absent; skipping folder permissions and cleanup."
      }

      try {
          if ($OneDriveFolderExists) {
              # Protect user files while the uninstaller runs.
              icacls $OneDrivePath /deny "*S-1-5-32-544:(D,DC)"
              if ($LASTEXITCODE -ne 0) { throw "Unable to protect the OneDrive folder (icacls exit code $LASTEXITCODE)." }
          }

          Write-Host "Uninstalling OneDrive..."
          Start-Process -FilePath (Join-Path $Env:SystemRoot "System32\OneDriveSetup.exe") -ArgumentList '/uninstall' -Wait -ErrorAction Stop

          # Some of OneDrive files use explorer, and OneDrive uses FileCoAuth
          Write-Host "Removing leftover OneDrive Files..."

          Get-Process -ErrorAction Stop | Where-Object ProcessName -eq 'FileCoAuth' | Stop-Process -ErrorAction Stop
          Get-Process -ErrorAction Stop | Where-Object ProcessName -eq 'Explorer' | Stop-Process -ErrorAction Stop

          $OneDriveLeftovers = @("$Env:LocalAppData\Microsoft\OneDrive", "$Env:ProgramData\Microsoft OneDrive")
          foreach ($LeftoverPath in $OneDriveLeftovers) {
              if (Test-Path -LiteralPath $LeftoverPath -ErrorAction Stop) {
                  Remove-Item -LiteralPath $LeftoverPath -Recurse -Force -ErrorAction Stop
              }
          }
      } finally {
          if ($OneDriveFolderExists) {
              # Restore access even when uninstall or leftover cleanup fails.
              Set-Acl -LiteralPath $OneDrivePath -AclObject $OneDriveAcl -ErrorAction Stop
          }
      }

      if ($OneDriveFolderExists -and -not (Get-ChildItem -LiteralPath $OneDrivePath -Force -ErrorAction Stop)) {
          # Refuse to delete if files appeared after the emptiness check.
          [System.IO.Directory]::Delete($OneDrivePath, $false)
          [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')
      }

      # OneSyncSvc is a per-user template; Get-Service only exposes user instances.
      # Skip the operation if this Windows installation has no template.
      if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc') {
          Set-Service -Name OneSyncSvc -StartupType Disabled
      }
'@
$global:OptiScript_S17_Undo = @'
Write-Host "Installing OneDrive"
      winget install Microsoft.Onedrive --source winget

      # Enable OneSyncSvc when the per-user service template exists
      if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc') {
          Set-Service -Name OneSyncSvc -StartupType Automatic
      }
'@
$global:OptiScript_S19_Apply = @'
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))
'@
$global:OptiScript_S19_Undo = @'
Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask"
'@
$global:OptiScript_S20_Apply = @'
DISM /Online /Set-ReservedStorageState /State:Disabled
'@
$global:OptiScript_S20_Undo = @'
DISM /Online /Set-ReservedStorageState /State:Enabled
'@
$global:OptiScript_S21_Apply = @'
if (-not (Get-ComputerRestorePoint)) {
          Enable-ComputerRestore -Drive $Env:SystemDrive
      }

      Checkpoint-Computer -Description "System Restore Point created by OptiCore" -RestorePointType MODIFY_SETTINGS
      Write-Host "System Restore Point Created Successfully" -ForegroundColor Green
'@
$global:OptiScript_S24_Apply = @'
$Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName
      $Sid = (Get-LocalUser $Env:UserName).Sid.Value

      New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$Sid\$Appx" -Force

      Get-AppxPackage -AllUsers "*Copilot*" | Remove-AppxPackage -AllUsers
      winget uninstall -e --name "Copilot" --silent --force --accept-source-agreements 2>$null
      Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers

      if ($Appx) {
          Remove-AppxPackage $Appx
      }

      # WSAIFabricSvc only exists on some Windows 11 builds; without the guard a
      # missing service aborts the rest of this script block and Recall stays enabled
      if (Get-Service -Name WSAIFabricSvc -ErrorAction SilentlyContinue) {
          Set-Service -Name WSAIFabricSvc -StartupType Disabled
      }
      # Store/MSIX PowerShell 7 can hang or fail COM activation in DISM.
      $RecallCommand = {
          Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction Stop | Out-Null
      }
      $RecallOutput = powershell.exe -NoProfile -NonInteractive -Command $RecallCommand 2>&1
      if ($LASTEXITCODE -ne 0) {
          throw "Failed to disable Recall (exit code $LASTEXITCODE): $(($RecallOutput | Out-String).Trim())"
      }
      $RecallOutput | ForEach-Object { Write-Host $_ }

      Write-Host "Windows AI Disabled"
'@
$global:OptiScript_S27_Apply = @'
$RazerPath = "$Env:SystemRoot\Installer\Razer"

      if (Test-Path $RazerPath) {
        Remove-Item $RazerPath\* -Recurse -Force
      } else {
        New-Item -Path $RazerPath -ItemType Directory
      }

      icacls $RazerPath /deny "*S-1-1-0:(W)"
'@
$global:OptiScript_S27_Undo = @'
icacls "$Env:SystemRoot\Installer\Razer" /remove:d *S-1-1-0
'@
$global:OptiScript_S28_Apply = @'
Stop-Process -Name "logi_download_assistant" -Force -ErrorAction SilentlyContinue

      $ProgramFiles64 = if ($Env:ProgramW6432) { $Env:ProgramW6432 } else { $Env:ProgramFiles }
      $LogiPath = "$ProgramFiles64\LogiDownloadAssistant"

      if (Test-Path $LogiPath) {
        Remove-Item $LogiPath\* -Recurse -Force
      } else {
        New-Item -Path $LogiPath -ItemType Directory
      }

      icacls $LogiPath /deny "*S-1-1-0:(W)"
      if ($LASTEXITCODE -ne 0) { throw "icacls failed to deny write access on $LogiPath (exit code $LASTEXITCODE)" }
'@
$global:OptiScript_S28_Undo = @'
$ProgramFiles64 = if ($Env:ProgramW6432) { $Env:ProgramW6432 } else { $Env:ProgramFiles }
      $LogiPath = "$ProgramFiles64\LogiDownloadAssistant"

      if (Test-Path $LogiPath) {
        icacls $LogiPath /remove:d "*S-1-1-0"
        if ($LASTEXITCODE -ne 0) { throw "icacls failed to remove the write-deny rule on $LogiPath (exit code $LASTEXITCODE)" }
      }
'@
$global:OptiScript_S30_Apply = @'
$hostsUrl = Invoke-RestMethod -Uri https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts
      Add-Content -Path "$Env:SystemRoot\System32\drivers\etc\hosts" -Value $hostsUrl

      ipconfig /flushdns
      Write-Host 'Added Adobe url block list from host file'
'@
$global:OptiScript_S30_Undo = @'
Set-Content "$Env:SystemRoot\System32\drivers\etc\hosts" (
          (Get-Content "$Env:SystemRoot\System32\drivers\etc\hosts") -join "`n" -replace '(?s)#New Ver.*', ''
      )

      ipconfig /flushdns
      Write-Host 'Removed Adobe url block list from host file'
'@
$global:OptiScript_S31_Apply = @'
New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Name InprocServer32 -Value "" -Force
      Stop-Process -Name explorer
'@
$global:OptiScript_S31_Undo = @'
Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse
'@
$global:OptiScript_S32_Apply = @'
cleanmgr.exe /d C: /VERYLOWDISK
      Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
'@
$global:OptiScript_S33_Apply = @'
# A temp folder always holds files something has open, including this run's own, and
      # the job layer counts a logged error as a failed step
      Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
'@
$global:OptiScript_S35_Apply = @'
netsh interface teredo set state disabled
'@
$global:OptiScript_S35_Undo = @'
netsh interface teredo set state default
'@
$global:OptiScript_S36_Apply = @'
$search = Get-Service -Name WSearch -ErrorAction SilentlyContinue
      if ($search -and $search.StartType -eq 'Disabled' -and $search.Status -ne 'Stopped') {
        Stop-Service -Name WSearch -Force -ErrorAction Stop
      }
'@
$global:OptiScript_S36_Undo = @'
$search = Get-Service -Name WSearch -ErrorAction SilentlyContinue
      if ($search -and $search.StartType -eq 'Automatic' -and $search.Status -ne 'Running') {
        Start-Service -Name WSearch -ErrorAction Stop
      }
'@
$global:OptiScript_S37_Apply = @'
Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6
'@
$global:OptiScript_S37_Undo = @'
Enable-NetAdapterBinding -Name * -ComponentID ms_tcpip6
'@
$global:OptiScript_S39_Apply = @'
# Previously detected folders
      $bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"

      # Folder types lookup table
      $bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"

      # Flush Explorer view database
      Remove-Item -Path $bags -Recurse -Force
      Write-Host "Removed $bags"

      Remove-Item -Path $bagMRU -Recurse -Force
      Write-Host "Removed $bagMRU"

      # Every folder
      $allFolders = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"

      if (!(Test-Path $allFolders)) {
        New-Item -Path $allFolders -Force
        Write-Host "Created $allFolders"
      }

      # Generic view
      New-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" -PropertyType String -Force
      Write-Host "Set FolderType to NotSpecified"

      Write-Host Please sign out and back in, or restart your computer to apply the changes!
'@
$global:OptiScript_S39_Undo = @'
# Previously detected folders
      $bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"

      # Folder types lookup table
      $bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"

      # Flush Explorer view database
      Remove-Item -Path $bags -Recurse -Force
      Write-Host "Removed $bags"

      Remove-Item -Path $bagMRU -Recurse -Force
      Write-Host "Removed $bagMRU"

      Write-Host Please sign out and back in, or restart your computer to apply the changes!
'@
$global:OptiScript_S42_Apply = @'
Invoke-WinUtilExplorerUpdate
      if ($sync.ThemeButton.Content -eq [char]0xF08C) {
        Invoke-WinutilThemeChange -theme "Auto"
      }
'@
$global:OptiScript_S42_Undo = @'
Invoke-WinUtilExplorerUpdate
      if ($sync.ThemeButton.Content -eq [char]0xF08C) {
        Invoke-WinutilThemeChange -theme "Auto"
      }
'@
$global:OptiScript_S43_Apply = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S43_Undo = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S44_Apply = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S44_Undo = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S58_Apply = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S58_Undo = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S60_Apply = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@
$global:OptiScript_S60_Undo = @'
Invoke-WinUtilExplorerUpdate -action "restart"
'@

# ===================== OPTICORE: TWEAKS IMPORTADOS =====================
# Shims para los scripts importados: solo se ejecutan los que no dependen de otras partes de OptiCore.
$global:sync = @{}
function Write-WinUtilLog { param([string]$Level = 'INFO', [string]$Component = '', [string]$Message = '') MT-Log -Level $Level -Message $Message }
function Invoke-WinUtilExplorerUpdate { try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Process explorer.exe } catch {} }
function Invoke-WinutilThemeChange { param($theme) }

function New-OptiReg { param([string]$Path, [string]$Name, [string]$Value, [string]$Kind, [string]$Original)
    [pscustomobject]@{ Path = $Path; Name = $Name; Value = $Value; Kind = $Kind; Original = $Original } }
function New-OptiSvc { param([string]$Name, [string]$Startup, [string]$Original)
    [pscustomobject]@{ Name = $Name; Startup = $Startup; Original = $Original } }
function New-OptiTweak { param([string]$Id, [string]$Name, [string]$Category, [string]$Description, [bool]$Advanced,
    [bool]$Available, [string]$Note, [object[]]$Registry = @(), [object[]]$Services = @(), $Script = $null, $Undo = $null)
    [pscustomobject]@{ Id = $Id; Name = $Name; Category = $Category; Description = $Description; Advanced = $Advanced;
        Available = $Available; Note = $Note; Registry = $Registry; Services = $Services; Script = $Script; Undo = $Undo } }

function OPT-ToItem { param($r, [bool]$Undo)
    if ($Undo) {
        if ($r.Original -eq '<RemoveEntry>') { return (New-MTDel $r.Path $r.Name) }
        $v = $r.Original; $k = $r.Kind
    } else { $v = $r.Value; $k = $r.Kind }
    if ($k -eq 'String') { return (New-MTSt $r.Path $r.Name ([string]$v)) }
    return (New-MTDw $r.Path $r.Name ([int]$v))
}

function OPT-ApplyTweak { param($T, [bool]$Undo)
    $label = if ($Undo) { 'Deshaciendo' } else { 'Aplicando' }
    MT-Log -Level INFO -Message "$label: $($T.Name)"
    try {
        foreach ($r in $T.Registry) { MT-ApplyItem -Item (OPT-ToItem $r $Undo) }
        foreach ($s in $T.Services) {
            $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $s.Name
            if (-not (Test-Path -LiteralPath $path)) { MT-Log -Level WARN -Message "Servicio $($s.Name) no existe. Omitido."; continue }
            $startup = if ($Undo) { $s.Original } else { $s.Startup }
            MT-ApplyItem -Item (New-MTDw $path 'Start' $SVC_VAL[$startup])
            if ((-not $Undo) -and $startup -eq 'Disabled') { Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue }
        }
        $code = if ($Undo) { $T.Undo } else { $T.Script }
        if ($code) { & ([scriptblock]::Create([string]$code)) }
        MT-Log -Level OK -Message "$($T.Name): hecho."
        return 'Correcta'
    } catch {
        MT-Log -Level ERROR -Message "$($T.Name) fallo: $($_.Exception.Message)"
        return 'Error'
    }
}

$SVC_VAL = @{ Automatic = 2; Manual = 3; Disabled = 4 }

$global:OptiTweaks = @(
    (New-OptiTweak -Id 'WPFTweaksActivity' -Name 'Activity History - Disable' -Category 'Essential Tweaks' -Description 'Stops Windows from publishing or uploading user activities while preserving clipboard history.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksHiber' -Name 'Hibernation - Disable' -Category 'Essential Tweaks' -Description 'Hibernation is really meant for laptops as it saves what''s in memory before turning the PC off. It really should never be used.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\System\CurrentControlSet\Control\Session Manager\Power' 'HibernateEnabled' '0' 'DWord' '1'), (New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings' 'ShowHibernateOption' '0' 'DWord' '1')) -Services @() -Script $global:OptiScript_S02_Apply -Undo $global:OptiScript_S02_Undo),
    (New-OptiTweak -Id 'WPFTweaksWidget' -Name 'Widgets - Remove' -Category 'Essential Tweaks' -Description 'Removes the annoying widgets in the bottom left of the Taskbar.' -Advanced $false -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S03_Apply -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksRevertStartMenu' -Name 'Start Menu Previous Layout - Enable' -Category 'Essential Tweaks' -Description 'Bring back the old Start Menu layout from before the gradual rollout of the new one in 25H2. On newer versions of Windows !!THIS TWEAK WILL NOT WORK!!' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\ControlSet001\Control\FeatureManagement\Overrides\8\3036241548' 'EnabledState' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksDisableStoreSearch' -Name '[Avanzado] Microsoft Store Recommended Search Results - Disable' -Category 'Essential Tweaks' -Description 'Will not display recommended Microsoft Store apps when searching for apps in the Start menu.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S05_Apply -Undo $global:OptiScript_S05_Undo),
    (New-OptiTweak -Id 'WPFTweaksLocation' -Name 'Location Tracking - Disable' -Category 'Essential Tweaks' -Description 'Disables Location Tracking.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String' 'Allow'), (New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' '0' 'DWord' '1'), (New-OptiReg 'HKLM:\SYSTEM\Maps' 'AutoUpdateEnabled' '0' 'DWord' '1')) -Services @((New-OptiSvc 'lfsvc' 'Disabled' 'Manual')) -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksServices' -Name 'Services - Set to Manual' -Category 'Essential Tweaks' -Description 'Sets some services to Manual startup.' -Advanced $false -Available $true -Note '' -Registry @() -Services @((New-OptiSvc 'CscService' 'Disabled' 'Manual'), (New-OptiSvc 'DiagTrack' 'Disabled' 'Automatic'), (New-OptiSvc 'MapsBroker' 'Manual' 'Automatic'), (New-OptiSvc 'StorSvc' 'Manual' 'Automatic'), (New-OptiSvc 'SharedAccess' 'Disabled' 'Automatic')) -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksSvcHostSplitting' -Name '[Avanzado] svchost.exe Splitting - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables service-host splitting to reduce the number of svchost.exe processes and modestly lower memory overhead. Recommended for low-performance systems with 12 GB of RAM or less. Can interfere with Xbox services. Restart Windows after changing this setting.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S08_Apply -Undo $global:OptiScript_S08_Undo),
    (New-OptiTweak -Id 'WPFTweaksBraveDebloat' -Name 'Brave Browser - Debloat' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables various annoyances like Brave Rewards, Leo AI, Crypto Wallet and VPN.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveRewardsDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveWalletDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveVPNDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveAIChatEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveStatsPingEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveNewsDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveTalkDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'TorDisabled' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'BraveP3AEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'UrlKeyedAnonymizedDataCollectionEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'SafeBrowsingExtendedReportingEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave' 'MetricsReportingEnabled' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksDisableWarningForUnsignedRdp' -Name '[Avanzado] RDP Unsigned File Warnings - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables warnings shown when launching unsigned RDP files introduced with the latest Windows 10 and 11 updates.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' 'RedirectionWarningDialogVersion' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\SOFTWARE\Microsoft\Terminal Server Client' 'RdpLaunchConsentAccepted' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksEdgeDebloat' -Name 'Microsoft Edge - Debloat' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables various telemetry options, popups, and other annoyances in Edge.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'PersonalizationReportingEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist' '1' 'ofefcgjbeghpigppfmkologfjadafddi' 'String' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ShowRecommendationsEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'UserFeedbackAllowed' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ConfigureDoNotTrack' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'AlternateErrorPagesEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeCollectionsEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeShoppingAssistantEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'MicrosoftEdgeInsiderPromotionEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'ShowMicrosoftRewards' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WebWidgetAllowed' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'EdgeAssetDeliveryServiceEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'WalletDonationEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DefaultBrowserSettingsCampaignEnabled' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksConsumerFeatures' -Name 'ConsumerFeatures - Disable' -Category 'Essential Tweaks' -Description 'Stops promoted app installs and reduces app suggestions from Microsoft Store content.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksTelemetry' -Name 'Telemetry - Disable' -Category 'Essential Tweaks' -Description 'Disables Microsoft Telemetry.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' '0' 'DWord' '<RemoveEntry>')) -Services @((New-OptiSvc 'diagtrack' 'Disabled' 'Automatic'), (New-OptiSvc 'WerSvc' 'Disabled' 'Manual')) -Script $global:OptiScript_S13_Apply -Undo $global:OptiScript_S13_Undo),
    (New-OptiTweak -Id 'WPFTweaksDeliveryOptimization' -Name 'Delivery Optimization - Disable' -Category 'Essential Tweaks' -Description 'Stops Windows from using your bandwidth to upload updates to other PCs on the internet or local network.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksRemoveEdge' -Name '[Avanzado] Microsoft Edge - Remove' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Uninstalls Microsoft Edge by creating dummy MicrosoftEdge.exe file in the legacy Edge folder. This tricks Windows into unlocking the official Edge uninstaller allowing for a system-level removal.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S15_Apply -Undo $global:OptiScript_S15_Undo),
    (New-OptiTweak -Id 'WPFTweaksDisableBitLocker' -Name '[Avanzado] BitLocker - Disable' -Category 'Essential Tweaks' -Description 'Disables BitLocker.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S16_Apply -Undo $global:OptiScript_S16_Undo),
    (New-OptiTweak -Id 'WPFTweaksRemoveOneDrive' -Name '[Avanzado] Microsoft OneDrive - Remove' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Denies permission to remove OneDrive user files, then uses its own uninstaller to remove it and restores the original permission afterward.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S17_Apply -Undo $global:OptiScript_S17_Undo),
    (New-OptiTweak -Id 'WPFTweaksRemoveHomeAndGallery' -Name '[Avanzado] File Explorer Home and Gallery - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Removes the Home and Gallery from Explorer and sets This PC as default.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' 'System.IsPinnedToNameSpaceTree' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' '0' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksDisplay' -Name 'Visual Effects - Set to Best Performance' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Sets the system preferences to performance. You can do this manually with sysdm.cpl as well.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String' '1'), (New-OptiReg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '200' 'String' '400'), (New-OptiReg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String' '1'), (New-OptiReg 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewAlphaSelect' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' '3' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' '0' 'DWord' '1')) -Services @() -Script $global:OptiScript_S19_Apply -Undo $global:OptiScript_S19_Undo),
    (New-OptiTweak -Id 'WPFTweaksReservedStorage' -Name '[Avanzado] Disable Reserved Storage' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables Windows Reserved Storage (7-10 GB held for updates/temp files). Recommended only on small drives. Re-enable before major Windows feature updates to avoid installation failures.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S20_Apply -Undo $global:OptiScript_S20_Undo),
    (New-OptiTweak -Id 'WPFTweaksRestorePoint' -Name 'Restore Point - Create' -Category 'Essential Tweaks' -Description 'Creates a restore point at runtime in case a revert is needed from WinUtil modifications.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' '0' 'DWord' '1440')) -Services @() -Script $global:OptiScript_S21_Apply -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksEndTaskOnTaskbar' -Name 'End Task With Right Click - Enable' -Category 'Essential Tweaks' -Description 'Enables option to end task when right-clicking a program in the taskbar.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksStorage' -Name 'Storage Sense - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Storage Sense deletes temp files automatically.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' '0' 'DWord' '1')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksWindowsAI' -Name '[Avanzado] Windows AI - Disable And Remove' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Removes and disables all AI features/packages' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'hide:aicomponents' 'String' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $global:OptiScript_S24_Apply -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksWPBT' -Name 'Windows Platform Binary Table (WPBT) - Disable' -Category 'Essential Tweaks' -Description 'If enabled, WPBT allows your computer vendor to execute programs at boot time, such as anti-theft software, software drivers, as well as force install software without user consent. Poses potential security risk.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksPreventDeviceMetadataFromNetwork' -Name 'Prevent Device Companion Apps' -Category 'Essential Tweaks' -Description 'Prevents additional software from being installed when plugging in devices (e.g. Ads when plugging in a monitor). Poses potential security risk.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksRazerBlock' -Name '[Avanzado] Razer Software Auto-Install - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Blocks ALL Razer Software installations. The hardware works fine without any software.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' '0' 'DWord' '1'), (New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' 'DisableCoInstallers' '1' 'DWord' '0')) -Services @() -Script $global:OptiScript_S27_Apply -Undo $global:OptiScript_S27_Undo),
    (New-OptiTweak -Id 'WPFTweaksLogiBlock' -Name '[Avanzado] Logitech Download Assistant Auto-Install - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Blocks the Logi Download Assistant that Windows Update keeps reinstalling with Logitech device drivers. Logitech hardware keeps working without it.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S28_Apply -Undo $global:OptiScript_S28_Undo),
    (New-OptiTweak -Id 'WPFTweaksDisableNotifications' -Name '[Avanzado] System Tray Notifications & Calendar - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables all Notifications INCLUDING Calendar.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' '1' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' '0' 'DWord' '1')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksBlockAdobeNet' -Name '[Avanzado] Adobe URL Block List - Enable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Reduces user interruptions by selectively blocking connections to Adobe''s activation and telemetry servers. Credit: Ruddernation-Designs' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S30_Apply -Undo $global:OptiScript_S30_Undo),
    (New-OptiTweak -Id 'WPFTweaksRightClickMenu' -Name '[Avanzado] Right-Click Menu Previous Layout - Enable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Restores the classic context menu when right-clicking in File Explorer, replacing the simplified Windows 11 version.' -Advanced $true -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S31_Apply -Undo $global:OptiScript_S31_Undo),
    (New-OptiTweak -Id 'WPFTweaksDiskCleanup' -Name 'Disk Cleanup - Run' -Category 'Essential Tweaks' -Description 'Runs Disk Cleanup on Drive C: and removes old Windows Updates.' -Advanced $false -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S32_Apply -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksDeleteTempFiles' -Name 'Temporary Files - Remove' -Category 'Essential Tweaks' -Description 'Erases TEMP Folders.' -Advanced $false -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S33_Apply -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksIPv46' -Name 'IPv6 - Set IPv4 as Preferred' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Setting the IPv4 preference can have latency and security benefits on private networks where IPv6 is not configured.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' '32' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksTeredo' -Name '[Avanzado] Teredo - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Teredo network tunneling is an IPv6 feature that can cause additional latency, but may cause problems with some games.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' '1' 'DWord' '0')) -Services @() -Script $global:OptiScript_S35_Apply -Undo $global:OptiScript_S35_Undo),
    (New-OptiTweak -Id 'WPFTweaksDisableSearchIndexing' -Name 'Windows Search Indexing - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Stops and disables the Windows Search service (WSearch) to cut background disk activity, mainly useful on mechanical hard drives. Warning: file searches in Explorer and the Start menu become much slower because Windows no longer maintains a search index. Undo restores the service and starts it again.' -Advanced $false -Available $true -Note '' -Registry @() -Services @((New-OptiSvc 'WSearch' 'Disabled' 'Automatic')) -Script $global:OptiScript_S36_Apply -Undo $global:OptiScript_S36_Undo),
    (New-OptiTweak -Id 'WPFTweaksDisableIPv6' -Name '[Avanzado] IPv6 - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables IPv6.' -Advanced $true -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' 'DisabledComponents' '255' 'DWord' '0')) -Services @() -Script $global:OptiScript_S37_Apply -Undo $global:OptiScript_S37_Undo),
    (New-OptiTweak -Id 'WPFTweaksDisableBGapps' -Name 'Background Apps - Disable' -Category 'z__Advanced Tweaks - CAUTION' -Description 'Disables all Microsoft Store apps from running in the background, which has to be done individually since Windows 11.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFTweaksDisableExplorerAutoDiscovery' -Name 'File Explorer Automatic Folder Discovery - Disable' -Category 'Essential Tweaks' -Description 'Windows Explorer automatically tries to guess the type of the folder based on its contents, slowing down the browsing experience. WARNING! Will disable File Explorer grouping.' -Advanced $false -Available $true -Note '' -Registry @() -Services @() -Script $global:OptiScript_S39_Apply -Undo $global:OptiScript_S39_Undo),
    (New-OptiTweak -Id 'WPFToggleDetailedBSoD' -Name 'BSoD Verbose Mode' -Category 'Customize Preferences' -Description 'Gives more information when you blue screen.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' '1' 'DWord' '0'), (New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisableEmoticon' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleBatteryPercentage' -Name 'System Tray Battery Percentage' -Category 'Customize Preferences' -Description 'Shows numeric battery percentage next to the battery icon in the system tray.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'IsBatteryPercentageEnabled' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleDarkMode' -Name 'Dark Theme for Windows' -Category 'Customize Preferences' -Description 'Dark Mode for the system and applications.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' '0' 'DWord' '1')) -Services @() -Script $global:OptiScript_S42_Apply -Undo $global:OptiScript_S42_Undo),
    (New-OptiTweak -Id 'WPFToggleShowExt' -Name 'File Explorer File Extensions' -Category 'Customize Preferences' -Description 'Shows .file extensions in Explorer (.exe, .png, etc.)' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' '0' 'DWord' '1')) -Services @() -Script $global:OptiScript_S43_Apply -Undo $global:OptiScript_S43_Undo),
    (New-OptiTweak -Id 'WPFToggleHiddenFiles' -Name 'File Explorer Hidden Files' -Category 'Customize Preferences' -Description 'Reveals hidden files in Explorer.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' '1' 'DWord' '0')) -Services @() -Script $global:OptiScript_S44_Apply -Undo $global:OptiScript_S44_Undo),
    (New-OptiTweak -Id 'WPFToggleVerboseLogon' -Name 'Logon Verbose Mode' -Category 'Customize Preferences' -Description 'Show detailed messages during startup/shutdown.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleNewOutlook' -Name 'Microsoft Outlook New Version' -Category 'Customize Preferences' -Description 'This will ensure the new Outlook application is used.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Preferences' 'UseNewOutlook' '1' 'DWord' '0'), (New-OptiReg 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Options\General' 'HideNewOutlookToggle' '0' 'DWord' '1'), (New-OptiReg 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Options\General' 'DoNewOutlookAutoMigration' '0' 'DWord' '0'), (New-OptiReg 'HKCU:\Software\Policies\Microsoft\Office\16.0\Outlook\Preferences' 'NewOutlookMigrationUserSetting' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleScrollbars' -Name 'Scrollbars Always Visible' -Category 'Customize Preferences' -Description 'If enabled, scrollbars will always be visible. If disabled, Windows will automatically hide scrollbars when not in use.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Control Panel\Accessibility' 'DynamicScrollbars' '0' 'DWord' '1')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFMultiplaneOverlay' -Name 'Multiplane Overlay' -Category 'Customize Preferences' -Description 'Multiplane Overlay composes multiple image layers, which can sometimes cause issues with graphics cards. Changes to this preference are applied immediately.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' '5' 'DWord' '<RemoveEntry>'), (New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'DisableOverlays' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleMouseAcceleration' -Name 'Mouse Acceleration' -Category 'Customize Preferences' -Description 'Makes it so Cursor movement is affected by the speed of your physical mouse movements.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '1' 'String' '0'), (New-OptiReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '6' 'String' '0'), (New-OptiReg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '10' 'String' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleNumLock' -Name 'Num Lock on Startup' -Category 'Customize Preferences' -Description 'Toggle the Num Lock key state when your computer starts.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKU:\.Default\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String' '0'), (New-OptiReg 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' '2' 'String' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleWindowSnapping' -Name 'Window Snapping' -Category 'Customize Preferences' -Description 'Toggles the window snapping feature when dragging windows.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Control Panel\Desktop' 'WindowArrangementActive' '1' 'String' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleStandbyFix' -Name 'S0 Sleep Network Connectivity' -Category 'Customize Preferences' -Description 'Toggles network connectivity during S0 Sleep which is low power idle in modern laptops.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9' 'ACSettingIndex' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleS3Sleep' -Name 'S3 Sleep' -Category 'Customize Preferences' -Description 'Toggles between Modern Standby and S3 Sleep, which cuts off power to the CPU while continuing to refresh the memory.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'PlatformAoAcOverride' '0' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleHideSettingsHome' -Name 'Settings Home Page' -Category 'Customize Preferences' -Description 'Toggles the Home Page in the Windows Settings app.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'show:home' 'String' 'hide:home')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleBingSearch' -Name 'Start Menu Bing Search' -Category 'Customize Preferences' -Description 'Toggles Bing web search results in Windows Search.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleLoginBlur' -Name 'Logon Screen Acrylic Blur' -Category 'Customize Preferences' -Description 'Toggles the acrylic blur effect on login screen background.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon' '0' 'DWord' '1')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleDisableLockscreen' -Name 'Lock Screen - Disable' -Category 'Customize Preferences' -Description 'Skips the lock screen entirely and goes directly to the sign-in screen on boot and wake.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreen' '1' 'DWord' '<RemoveEntry>')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleStartMenuRecommendations' -Name 'Start Menu Recommendations' -Category 'Customize Preferences' -Description 'Toggles the recommendations section in the Start Menu. WARNING: This will also disable Windows Spotlight on your Lock Screen as a side effect.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start' 'HideRecommendedSection' '0' 'DWord' '1'), (New-OptiReg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education' 'IsEducationEnvironment' '0' 'DWord' '1'), (New-OptiReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' '0' 'DWord' '1')) -Services @() -Script $global:OptiScript_S58_Apply -Undo $global:OptiScript_S58_Undo),
    (New-OptiTweak -Id 'WPFToggleStickyKeys' -Name 'Sticky Keys' -Category 'Customize Preferences' -Description 'Toggles the Sticky Keys, which activate when clicking shift rapidly.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'DWord' '58')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleTaskbarAlignment' -Name 'Taskbar Centered Icons' -Category 'Customize Preferences' -Description 'Toggles the Taskbar alignment either to the left or center.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' '1' 'DWord' '0')) -Services @() -Script $global:OptiScript_S60_Apply -Undo $global:OptiScript_S60_Undo),
    (New-OptiTweak -Id 'WPFToggleTaskbarSearch' -Name 'Taskbar Search Icon' -Category 'Customize Preferences' -Description 'Toggles the Search Button on the Taskbar.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleTaskView' -Name 'Taskbar Task View Icon' -Category 'Customize Preferences' -Description 'Toggles the Task View Button in the Taskbar.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleGameMode' -Name 'Game Mode' -Category 'Customize Preferences' -Description 'Toggles Windows prioritizes gaming performance by allocating system resources to games.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' '1' 'DWord' '0'), (New-OptiReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null),
    (New-OptiTweak -Id 'WPFToggleLongPaths' -Name 'Enable Long Paths' -Category 'Customize Preferences' -Description 'Toggles support for file paths longer than 260 characters in Explorer.' -Advanced $false -Available $true -Note '' -Registry @((New-OptiReg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' '1' 'DWord' '0')) -Services @() -Script $null -Undo $null)
)

# ===================== FIN TWEAKS OPTICORE =====================

function OPT-ShowPanel {
    $navy = MT-Color 16 28 48; $blue = MT-Color 0 102 204; $grey = MT-Color 55 70 95
    $light = MT-Color 225 235 250; $logBg = MT-Color 8 16 30
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'ManuTweaks - Tweaks OptiCore'; $f.ClientSize = New-Object System.Drawing.Size(640, 600)
    $f.StartPosition = 'CenterParent'; $f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false
    $f.BackColor = $navy; $f.ForeColor = $light; $f.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $list = New-Object System.Windows.Forms.CheckedListBox
    $list.Location = New-Object System.Drawing.Point(20, 20); $list.Size = New-Object System.Drawing.Size(600, 300)
    $list.CheckOnClick = $true; $list.BackColor = $logBg; $list.ForeColor = $light; $list.BorderStyle = 'FixedSingle'
    $items = @($global:OptiTweaks | Sort-Object Category, Name)
    foreach ($t in $items) { [void]$list.Items.Add($t.Name, $false) }
    $script:OptiItems = $items

    $desc = New-Object System.Windows.Forms.Label
    $desc.Location = New-Object System.Drawing.Point(20, 326); $desc.Size = New-Object System.Drawing.Size(600, 40)
    $desc.ForeColor = MT-Color 150 175 210
    $list.Add_SelectedIndexChanged({
        $i = $list.SelectedIndex
        if ($i -ge 0) {
            $t = $script:OptiItems[$i]
            $desc.Text = $t.Description + $(if (-not $t.Available) { '  [No disponible: ' + $t.Note + ']' } else { '' })
        }
    })

    $bApply = MT-NewButton 'Aplicar marcados' 20 372 190 40 $blue
    $bUndo  = MT-NewButton 'Deshacer marcados' 225 372 190 40 $grey
    $bAll   = MT-NewButton 'Marcar seguros' 430 372 190 40 $grey
    $bBack  = MT-NewButton 'Volver' 20 420 600 34 (MT-Color 150 40 40)

    $rich = New-Object System.Windows.Forms.RichTextBox
    $rich.Location = New-Object System.Drawing.Point(20, 464); $rich.Size = New-Object System.Drawing.Size(600, 120)
    $rich.ReadOnly = $true; $rich.BackColor = $logBg; $rich.ForeColor = $light; $rich.BorderStyle = 'FixedSingle'
    $rich.Font = New-Object System.Drawing.Font('Consolas', 9)
    $prevRich = $global:MTRichBox
    $global:MTRichBox = $rich
    $buttons = @($bApply, $bUndo, $bAll, $bBack)

    $runSel = {
        param([bool]$Undo)
        $sel = @()
        for ($i = 0; $i -lt $list.Items.Count; $i++) { if ($list.GetItemChecked($i)) { $sel += $script:OptiItems[$i] } }
        if ($sel.Count -eq 0) { MT-Log -Level WARN -Message 'No hay tweaks marcados.'; return }
        foreach ($b in $buttons) { $b.Enabled = $false }
        try {
            foreach ($t in $sel) {
                if (-not $t.Available) { MT-Log -Level WARN -Message "$($t.Name) omitido: $($t.Note)"; continue }
                [void](OPT-ApplyTweak -T $t -Undo $Undo)
            }
        } finally { foreach ($b in $buttons) { $b.Enabled = $true } }
    }
    $bApply.Add_Click({ & $runSel $false })
    $bUndo.Add_Click({ & $runSel $true })
    $bAll.Add_Click({
        for ($i = 0; $i -lt $list.Items.Count; $i++) {
            $t = $script:OptiItems[$i]
            $list.SetItemChecked($i, ($t.Available -and -not $t.Advanced))
        }
    })
    $bBack.Add_Click({ $f.Close() })
    $f.Controls.AddRange(@($list, $desc, $bApply, $bUndo, $bAll, $bBack, $rich))
    MT-Log -Level INFO -Message ('Tweaks OptiCore cargados: ' + $items.Count + ' (' + @($items | Where-Object { -not $_.Available }).Count + ' no disponibles en esta version).')
    [void]$f.ShowDialog()
    $global:MTRichBox = $prevRich
}

function New-OptiTweakDefs { return $global:OptiTweaks }

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
    $sub   = MT-NewLabel 'Optimizacion de Windows  |  newmanu0' 22 52 $muted 9
    $perfil = MT-NewLabel 'Perfil de juego: Bajos' 20 92 $light 10 'Bold'

    $btnRun  = MT-NewButton 'Iniciar optimizacion' 20 124 250 42 $blue
    $btnRst  = MT-NewButton 'Restaurar' 290 124 250 42 $grey
    $btnOpti = MT-NewButton 'Tweaks OptiCore' 20 176 250 36 (MT-Color 0 120 150)
    $btnExit = MT-NewButton 'Salir' 290 176 250 36 $red

    $rich = New-Object System.Windows.Forms.RichTextBox
    $rich.Location = New-Object System.Drawing.Point(20, 226)
    $rich.Size = New-Object System.Drawing.Size(520, 274)
    $rich.ReadOnly = $true
    $rich.BackColor = $logBg
    $rich.ForeColor = $light
    $rich.BorderStyle = 'FixedSingle'
    $rich.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $global:MTRichBox = $rich

    $global:MTButtons = @($btnRun, $btnRst, $btnOpti, $btnExit)

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

    $btnOpti.Add_Click({
        MT-SetButtons $false
        try { OPT-ShowPanel }
        catch { MT-Log -Level ERROR -Message ('Fallo en Tweaks OptiCore: ' + $_.Exception.Message) }
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

    $form.Controls.AddRange(@($title, $sub, $perfil, $btnRun, $btnRst, $btnOpti, $btnExit, $rich))
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

