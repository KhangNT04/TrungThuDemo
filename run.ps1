Param(
  [int[]]$Ports = @(5501, 8081, 3000, 5173)
)

function Test-PortFree {
  param([int]$Port)
  $inUse = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $Port }).Count -gt 0
  return -not $inUse
}

function Wait-ServerUp {
  param([int]$Port, [int]$Retries = 40)
  $url = "http://127.0.0.1:$Port/" 
  for ($i=0; $i -lt $Retries; $i++) {
    try {
      $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 1
      if ($resp.StatusCode -ge 200) { return $true }
    } catch { }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Start-PythonOrNode {
  param([int]$Port)
  if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Host "Starting Python server on $Port" -ForegroundColor Cyan
    Start-Process -WindowStyle Minimized powershell -ArgumentList "-NoProfile","-Command","python -m http.server $Port --bind 127.0.0.1" | Out-Null
    return $true
  }
  if (Get-Command npx -ErrorAction SilentlyContinue) {
    Write-Host "Starting npx http-server on $Port" -ForegroundColor Cyan
    Start-Process -WindowStyle Minimized powershell -ArgumentList "-NoProfile","-Command","npx http-server -p $Port --silent" | Out-Null
    return $true
  }
  return $false
}

function Get-ContentType {
  param([string]$Path)
  switch ([IO.Path]::GetExtension($Path).ToLower()) {
    '.html' { 'text/html; charset=utf-8' }
    '.htm'  { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.png'  { 'image/png' }
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.gif'  { 'image/gif' }
    '.svg'  { 'image/svg+xml' }
    '.ico'  { 'image/x-icon' }
    '.mp3'  { 'audio/mpeg' }
    default { 'application/octet-stream' }
  }
}

function Start-PSHttpServer {
  param([int]$Port)
  try { $listener = [System.Net.HttpListener]::new() } catch { Write-Warning "HttpListener unavailable."; return $false }
  $prefix = "http://127.0.0.1:$Port/"
  $listener.Prefixes.Add($prefix)
  try { $listener.Start() } catch { Write-Warning "Cannot bind $prefix (conflict)."; return $false }
  Write-Host "PowerShell HttpListener started on $prefix" -ForegroundColor Cyan
  Start-Job -Name "ps-server-$Port" -ScriptBlock {
    param($listener)
    while ($listener.IsListening) {
      try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $relPath = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($relPath)) { $relPath = 'index.html' }
        $fsPath = Join-Path -Path (Get-Location) -ChildPath $relPath
        if (-not (Test-Path $fsPath)) { if (Test-Path (Join-Path $fsPath 'index.html')) { $fsPath = Join-Path $fsPath 'index.html' } }
        if (Test-Path $fsPath -PathType Leaf) {
          $bytes = [IO.File]::ReadAllBytes($fsPath)
          $res.ContentType = (Get-ContentType -Path $fsPath)
          $res.ContentLength64 = $bytes.Length
          $res.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
          $res.StatusCode = 404
          $msg = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
          $res.OutputStream.Write($msg, 0, $msg.Length)
        }
        $res.OutputStream.Close()
      } catch { Start-Sleep -Milliseconds 50 }
    }
  } -ArgumentList $listener | Out-Null
  return $true
}

$chosen = $null
foreach ($p in $Ports) { if (Test-PortFree -Port $p) { $chosen = $p; break } }
if (-not $chosen) { $chosen = $Ports[0] }

$started = Start-PythonOrNode -Port $chosen
if (-not (Wait-ServerUp -Port $chosen)) {
  Write-Warning "First attempt not reachable. Falling back to built-in PowerShell server."
  $started = Start-PSHttpServer -Port $chosen
  if (-not $started) {
    foreach ($p in $Ports) {
      if ($p -ne $chosen -and (Test-PortFree -Port $p)) { $chosen = $p; $started = Start-PSHttpServer -Port $chosen; if ($started) { break } }
    }
  }
  if (-not $started) { Write-Error "Failed to start any server"; exit 1 }
  if (-not (Wait-ServerUp -Port $chosen)) { Write-Error "Server still unreachable. Check Firewall/Anti-virus."; exit 1 }
}

$indexUrl = "http://127.0.0.1:$chosen/index.html"
Start-Process $indexUrl | Out-Null
Write-Host "Opened $indexUrl" -ForegroundColor Green
