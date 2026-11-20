# Waterproofing dashboard - tiny local web server (no install needed, uses built-in Windows PowerShell)
# Usage: double-click start-dashboard.bat   (or:  powershell -ExecutionPolicy Bypass -File server.ps1 -Port 9375)
param([int]$Port = 9375)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
  Write-Host "Port $Port is busy. Trying $($Port+1)..." -ForegroundColor Yellow
  $Port++; $prefix = "http://localhost:$Port/"
  $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add($prefix); $listener.Start()
}

$types = @{ ".html"="text/html; charset=utf-8"; ".js"="application/javascript; charset=utf-8"; ".css"="text/css; charset=utf-8";
            ".json"="application/json; charset=utf-8"; ".png"="image/png"; ".svg"="image/svg+xml"; ".ico"="image/x-icon" }

Write-Host ""
Write-Host "  Waterproofing Status Dashboard is running at  $prefix" -ForegroundColor Green
Write-Host "  Data refreshes from the Google Sheet every 60 seconds."
Write-Host "  Keep this window open. Press Ctrl+C to stop."
Write-Host ""
Start-Process $prefix

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
  if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
  $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
  $res = $ctx.Response
  if ($file.StartsWith($root) -and (Test-Path $file -PathType Leaf)) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $ext = [System.IO.Path]::GetExtension($file).ToLower()
    $res.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" })
    $res.Headers.Add("Cache-Control", "no-store")
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } else {
    $res.StatusCode = 404
    $msg = [System.Text.Encoding]::UTF8.GetBytes("Not found")
    $res.OutputStream.Write($msg, 0, $msg.Length)
  }
  $res.Close()
}
