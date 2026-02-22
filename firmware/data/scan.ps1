# ═══════════════════════════════════════════════════════════════
#  Nixo Soft PC Checker — Windows Diagnostic Script
#  Runs on target PC, sends results to ESP32 dongle
# ═══════════════════════════════════════════════════════════════

$DONGLE_URL = "http://192.168.4.1"
$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor DarkYellow
Write-Host "  ║   Nixo Soft PC Checker v2.0           ║" -ForegroundColor DarkYellow
Write-Host "  ║   Hardware Diagnostic Scanner         ║" -ForegroundColor DarkYellow
Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor DarkYellow
Write-Host ""
Write-Host "  Scanning hardware..." -ForegroundColor Cyan
Write-Host ""

$results = @{}

# ─── CPU ─────────────────────────────────────────────────────
Write-Host "  [1/10] CPU..." -ForegroundColor Gray
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$results.cpu = @{
    name = $cpu.Name.Trim()
    cores = [int]$cpu.NumberOfCores
    threads = [int]$cpu.NumberOfLogicalProcessors
    maxClockMHz = [int]$cpu.MaxClockSpeed
    currentClockMHz = [int]$cpu.CurrentClockSpeed
    architecture = $cpu.Architecture
    l2CacheKB = [int]($cpu.L2CacheSize)
    l3CacheKB = [int]($cpu.L3CacheSize)
    socket = $cpu.SocketDesignation
    manufacturer = $cpu.Manufacturer
}
Write-Host "    $($cpu.Name.Trim())" -ForegroundColor White

# ─── Memory ──────────────────────────────────────────────────
Write-Host "  [2/10] Memory..." -ForegroundColor Gray
$mem = Get-CimInstance Win32_PhysicalMemory
$totalRAM = ($mem | Measure-Object Capacity -Sum).Sum
$memSticks = @()
foreach ($stick in $mem) {
    $memSticks += @{
        capacityGB = [math]::Round($stick.Capacity / 1GB, 1)
        speedMHz = [int]$stick.Speed
        type = switch ($stick.SMBIOSMemoryType) { 26 { "DDR4" } 34 { "DDR5" } 24 { "DDR3" } default { "DDR" } }
        manufacturer = $stick.Manufacturer
        slot = $stick.DeviceLocator
    }
}
$results.memory = @{
    totalGB = [math]::Round($totalRAM / 1GB, 1)
    sticks = $memSticks
    slots = (Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1).MemoryDevices
}
Write-Host "    $([math]::Round($totalRAM / 1GB))GB RAM ($($memSticks.Count) sticks)" -ForegroundColor White

# ─── GPU ─────────────────────────────────────────────────────
Write-Host "  [3/10] GPU..." -ForegroundColor Gray
$gpus = Get-CimInstance Win32_VideoController
$gpuList = @()
foreach ($gpu in $gpus) {
    $vram = [math]::Round($gpu.AdapterRAM / 1GB, 1)
    if ($vram -le 0) { $vram = [math]::Round($gpu.AdapterRAM / 1MB, 0) }
    $gpuList += @{
        name = $gpu.Name
        vramGB = $vram
        driver = $gpu.DriverVersion
        resolution = "$($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
        refreshRate = [int]$gpu.CurrentRefreshRate
    }
    Write-Host "    $($gpu.Name) ($($vram)GB)" -ForegroundColor White
}
$results.gpu = $gpuList

# ─── Storage ─────────────────────────────────────────────────
Write-Host "  [4/10] Storage..." -ForegroundColor Gray
$disks = Get-CimInstance Win32_DiskDrive
$diskList = @()
foreach ($disk in $disks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 1)
    $mediaType = if ($disk.MediaType -match "SSD|Solid") { "SSD" } 
                 elseif ($disk.InterfaceType -eq "NVMe" -or $disk.Model -match "NVMe") { "NVMe" }
                 else { "HDD" }
    $diskList += @{
        model = $disk.Model
        sizeGB = $sizeGB
        type = $mediaType
        interface = $disk.InterfaceType
        serial = $disk.SerialNumber.Trim()
    }
    Write-Host "    $($disk.Model) ($($sizeGB)GB $mediaType)" -ForegroundColor White
}
$results.storage = $diskList

# Partitions with free space
$volumes = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
$partList = @()
foreach ($vol in $volumes) {
    $partList += @{
        drive = $vol.DeviceID
        totalGB = [math]::Round($vol.Size / 1GB, 1)
        freeGB = [math]::Round($vol.FreeSpace / 1GB, 1)
        filesystem = $vol.FileSystem
    }
}
$results.partitions = $partList

# ─── Motherboard ─────────────────────────────────────────────
Write-Host "  [5/10] Motherboard..." -ForegroundColor Gray
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
$results.motherboard = @{
    manufacturer = $board.Manufacturer
    product = $board.Product
    serial = $board.SerialNumber
    biosVersion = $bios.SMBIOSBIOSVersion
    biosDate = $bios.ReleaseDate.ToString("yyyy-MM-dd")
}
Write-Host "    $($board.Manufacturer) $($board.Product)" -ForegroundColor White

# ─── OS Info ─────────────────────────────────────────────────
Write-Host "  [6/10] Operating System..." -ForegroundColor Gray
$os = Get-CimInstance Win32_OperatingSystem
$results.os = @{
    name = $os.Caption
    version = $os.Version
    build = $os.BuildNumber
    arch = $os.OSArchitecture
    installDate = $os.InstallDate.ToString("yyyy-MM-dd")
    lastBoot = $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm")
}

# ─── Network ────────────────────────────────────────────────
Write-Host "  [7/10] Network..." -ForegroundColor Gray
$nics = Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true -and $_.NetConnectionStatus -ne $null }
$nicList = @()
foreach ($nic in $nics) {
    $nicList += @{
        name = $nic.Name
        mac = $nic.MACAddress
        speed = if ($nic.Speed) { "$([math]::Round($nic.Speed / 1e6))Mbps" } else { "N/A" }
        type = $nic.AdapterType
    }
}
$results.network = $nicList

# ─── Thermals ───────────────────────────────────────────────
Write-Host "  [8/10] Thermals..." -ForegroundColor Gray
$temps = @()
try {
    $thermal = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" 2>$null
    foreach ($t in $thermal) {
        $celsius = [math]::Round(($t.CurrentTemperature / 10) - 273.15, 1)
        $temps += @{ zone = $t.InstanceName; tempC = $celsius }
    }
} catch {}
$results.thermals = @{ zones = $temps }

# ─── USB Ports ──────────────────────────────────────────────
Write-Host "  [9/10] Peripherals..." -ForegroundColor Gray
$usbControllers = Get-CimInstance Win32_USBController
$results.usb = @{
    controllers = $usbControllers.Count
    devices = (Get-CimInstance Win32_USBHub).Count
}

# Display outputs
$monitors = Get-CimInstance Win32_DesktopMonitor
$results.displays = @{
    count = $monitors.Count
}

# Audio
$audio = Get-CimInstance Win32_SoundDevice
$results.audio = @{
    devices = @($audio | ForEach-Object { $_.Name })
}

# ─── Disk Speed Test ────────────────────────────────────────
Write-Host "  [10/10] Disk speed test..." -ForegroundColor Gray
$testFile = "$env:TEMP\nixosoft_disktest.tmp"
$testSize = 100MB
try {
    # Write test
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $data = New-Object byte[] $testSize
    [System.IO.File]::WriteAllBytes($testFile, $data)
    $sw.Stop()
    $writeMBs = [math]::Round($testSize / 1MB / ($sw.ElapsedMilliseconds / 1000), 1)
    
    # Read test
    $sw.Restart()
    [System.IO.File]::ReadAllBytes($testFile) | Out-Null
    $sw.Stop()
    $readMBs = [math]::Round($testSize / 1MB / ($sw.ElapsedMilliseconds / 1000), 1)
    
    Remove-Item $testFile -Force
    $results.diskSpeed = @{
        readMBs = $readMBs
        writeMBs = $writeMBs
        testSizeMB = [math]::Round($testSize / 1MB)
    }
    Write-Host "    Read: ${readMBs}MB/s, Write: ${writeMBs}MB/s" -ForegroundColor White
} catch {
    $results.diskSpeed = @{ error = "test failed" }
}

# ─── System Summary ─────────────────────────────────────────
$results.timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
$results.platform = "windows"
$results.hostname = $env:COMPUTERNAME

# ─── Send Results to Dongle ──────────────────────────────────
Write-Host ""
Write-Host "  Sending results to dongle..." -ForegroundColor Cyan
$json = $results | ConvertTo-Json -Depth 5 -Compress

try {
    $response = Invoke-RestMethod -Uri "$DONGLE_URL/api/results" -Method POST -Body $json -ContentType "application/json" -TimeoutSec 10
    Write-Host ""
    Write-Host "  ✓ Results sent successfully!" -ForegroundColor Green
    Write-Host "  Open the dashboard on your phone to view scores." -ForegroundColor Gray
} catch {
    Write-Host ""
    Write-Host "  ✗ Failed to send results: $_" -ForegroundColor Red
    Write-Host "  Make sure the PC is connected to NixoSoft-Check WiFi" -ForegroundColor Yellow
    
    # Fallback: save locally
    $json | Out-File "$env:USERPROFILE\Desktop\pc-checker-results.json" -Encoding UTF8
    Write-Host "  Results saved to Desktop\pc-checker-results.json" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor DarkYellow
Write-Host "  ║   Scan complete! Check your phone.    ║" -ForegroundColor DarkYellow
Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor DarkYellow
Write-Host ""
Read-Host "  Press Enter to close"
