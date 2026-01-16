param (
    [Parameter(Mandatory=$false)] [string]$sourcePath,
    [Parameter(Mandatory=$false)] [string]$codigo
)





# --- FUNCIÓN PARA MOSTRAR LA INTERFAZ ---
function Mostrar-Interfaz {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object Windows.Forms.Form
    $form.Text = "DocuDrivers"
    $form.Size = New-Object Drawing.Size(500,250)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    # Etiqueta Archivo
    $labelJar = New-Object Windows.Forms.Label
    $labelJar.Text = "Archivo JAR de origen:"
    $labelJar.Location = New-Object Drawing.Point(20,20)
    $labelJar.Size = New-Object Drawing.Size(150,20)
    $form.Controls.Add($labelJar)

    # Input Archivo
    $txtJar = New-Object Windows.Forms.TextBox
    $txtJar.Location = New-Object Drawing.Point(20,40)
    $txtJar.Size = New-Object Drawing.Size(350,20)
    $form.Controls.Add($txtJar)

    # Botón Buscar
    $btnBrowse = New-Object Windows.Forms.Button
    $btnBrowse.Text = "..."
    $btnBrowse.Location = New-Object Drawing.Point(380,38)
    $btnBrowse.Size = New-Object Drawing.Size(40,23)
    $btnBrowse.Add_Click({
        $objForm = New-Object Windows.Forms.OpenFileDialog
        $objForm.Filter = "Archivos JAR (*.jar)|*.jar"
        if ($objForm.ShowDialog() -eq "OK") { $txtJar.Text = $objForm.FileName }
    })
    $form.Controls.Add($btnBrowse)

    # Etiqueta Código
    $labelCod = New-Object Windows.Forms.Label
    $labelCod.Text = "Driver Key (Ej: MGHL7Driver):"
    $labelCod.Location = New-Object Drawing.Point(20,80)
    $labelCod.Size = New-Object Drawing.Size(200,20)
    $form.Controls.Add($labelCod)

    # Input Código
    $txtCod = New-Object Windows.Forms.TextBox
    $txtCod.Location = New-Object Drawing.Point(20,100)
    $txtCod.Size = New-Object Drawing.Size(400,20)
    $form.Controls.Add($txtCod)

    # Botón Ejecutar
    $btnRun = New-Object Windows.Forms.Button
    $btnRun.Text = "Actualizar y Registrar"
    $btnRun.Location = New-Object Drawing.Point(150,150)
    $btnRun.Size = New-Object Drawing.Size(180,40)
    $btnRun.BackColor = [Drawing.Color]::LightGreen
    $btnRun.Add_Click({
        if ($txtJar.Text -and $txtCod.Text) {
            $script:sourcePath = $txtJar.Text
            $script:codigo = $txtCod.Text
            $form.Close()
        } else {
            [Windows.Forms.MessageBox]::Show("Por favor, rellena ambos campos","Error")
        }
    })
    $form.Controls.Add($btnRun)

    $form.ShowDialog() | Out-Null
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [Windows.Forms.MessageBox]::Show("Debes ejecutar este programa como Administrador.","Error de Permisos")
    return
}

# Si no hay parámetros CLI, lanzamos la GUI
if (-not $sourcePath -or -not $codigo) {
    Mostrar-Interfaz
}

# Validar que después de la GUI (o CLI) tenemos los datos
if (-not $sourcePath -or -not $codigo) { return }

# --- LÓGICA ORIGINAL ---
$sourcePath = $sourcePath.Trim('"').Trim("'")
$destJarPath = "C:\Program Files (x86)\Modulab\MultiOnline.jar"
$exePath = "C:\Program Files (x86)\Modulab\MultiOnlineCommandLine.exe"
$propertiesInternalPath = "com/systelab/modulabgold/client/multionline/util/interest/multionline_drivers.properties"
$codigoSinDriver = $codigo -replace "Driver$", ""

if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
    Write-Host "ERROR: No se encuentra el origen: $sourcePath" -ForegroundColor Red
    Read-Host "Enter para salir..."; return
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Write-Host "--- Iniciando proceso (Clase + Properties) ---" -ForegroundColor Cyan

    $srcZip = [System.IO.Compression.ZipFile]::OpenRead($sourcePath)
    $destZip = [System.IO.Compression.ZipFile]::Open($destJarPath, "Update")

    # 1. ACTUALIZACIÓN DE LA CLASE
    foreach ($entry in $srcZip.Entries) {
        if ($entry.Name -like "*$codigo*.class") {
            Write-Host "Actualizando clase: $($entry.FullName)" -ForegroundColor Green
            $tempClassFile = Join-Path $env:TEMP $entry.Name
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tempClassFile, $true)
            $oldEntry = $destZip.GetEntry($entry.FullName)
            if ($null -ne $oldEntry) { $oldEntry.Delete() }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($destZip, $tempClassFile, $entry.FullName)
            Remove-Item $tempClassFile -Force
        }
    }

    # 2. ACTUALIZACIÓN DEL PROPERTIES
    $propEntry = $destZip.GetEntry($propertiesInternalPath)
    if ($null -ne $propEntry) {
        $tempPropPath = Join-Path $env:TEMP "multionline_drivers.properties"
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($propEntry, $tempPropPath, $true)
        $propContent = Get-Content $tempPropPath -Raw
        if ($propContent -notmatch "(?m)^$codigoSinDriver=") {
            Write-Host "Añadiendo clave en properties..." -ForegroundColor Green
            Add-Content -Path $tempPropPath -Value "`r`n$codigoSinDriver=LABORATORY_INTEREST"
            $propEntry.Delete()
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($destZip, $tempPropPath, $propertiesInternalPath)
        }
        Remove-Item $tempPropPath -Force
    }

    $srcZip.Dispose(); $destZip.Dispose()

    # 3. EJECUCIÓN DEL EXE
    if (Test-Path $exePath) {
        Write-Host "Ejecutando comando..." -ForegroundColor Yellow
        & $exePath -addNewDriver $codigoSinDriver -driversInfoDestinationFolder "C:\MultiOnlineDrivers\"
    }

    Write-Host "`nProceso completado correctamente." -ForegroundColor Green
} catch {
    Write-Host "Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
}
