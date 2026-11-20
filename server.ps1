# Waterproofing dashboard - local web server with user login (built-in Windows PowerShell, nothing to install)
# Start: double-click start-dashboard.bat   (or: powershell -ExecutionPolicy Bypass -File server.ps1 -Port 9375)
# Users are saved in users.json next to this file (passwords stored only as salted SHA-256 hashes).
param([int]$Port = 9375)

$root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$usersFile = Join-Path $root 'users.json'
$keyFile   = Join-Path $root 'secret.key'
$utf8      = New-Object System.Text.UTF8Encoding($false)

# ---------------- helpers ----------------
function Get-Sha256Hex([string]$text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $b = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) } finally { $sha.Dispose() }
  return (-join ($b | ForEach-Object { $_.ToString('x2') }))
}
function New-RandomBytes([int]$n) {
  $b = New-Object byte[] $n
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($b) } finally { $rng.Dispose() }
  return ,$b
}
function New-Salt { $b = New-RandomBytes 16; return (-join ($b | ForEach-Object { $_.ToString('x2') })) }
function ConvertTo-B64Url([byte[]]$b) { return [Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_') }
function ConvertFrom-B64Url([string]$s) {
  $s = $s.Replace('-','+').Replace('_','/')
  switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
  return ,([Convert]::FromBase64String($s))
}

if (-not (Test-Path $keyFile)) { [System.IO.File]::WriteAllText($keyFile, [Convert]::ToBase64String((New-RandomBytes 32)), $utf8) }
$secret = [Convert]::FromBase64String(([System.IO.File]::ReadAllText($keyFile)).Trim())

function Get-Signature([string]$payload) {
  $h = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$secret)
  try { $sig = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload)) } finally { $h.Dispose() }
  return (ConvertTo-B64Url $sig)
}

function Save-Users($list) {
  $json = ConvertTo-Json -InputObject @($list) -Depth 5
  [System.IO.File]::WriteAllText($usersFile, $json, $utf8)
}
function Get-Users {
  if (-not (Test-Path $usersFile)) {
    $salt = New-Salt
    $first = [pscustomobject]@{ id = 'admin'; name = 'Administrator'; role = 'admin'; salt = $salt; hash = (Get-Sha256Hex ($salt + ':' + 'Homeland@2026')); created = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    Save-Users @($first)
  }
  $parsed = [System.IO.File]::ReadAllText($usersFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  return ,@($parsed)
}
function Find-User($list, [string]$id) {
  foreach ($u in $list) { if ($u.id -eq $id) { return $u } }
  return $null
}
function Get-PublicUser($u) { return [pscustomobject]@{ id = $u.id; name = $u.name; role = $u.role; created = $u.created } }

function New-Token($u, [int]$hours) {
  $exp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + ($hours * 3600)
  $payload = ConvertTo-B64Url ([System.Text.Encoding]::UTF8.GetBytes(($u.id + '|' + $exp)))
  return ($payload + '.' + (Get-Signature $payload))
}
function Get-TokenUser($req) {
  $h = $req.Headers['Authorization']
  if (-not $h -or -not $h.StartsWith('Bearer ')) { return $null }
  $parts = $h.Substring(7).Split('.')
  if ($parts.Length -ne 2) { return $null }
  if ((Get-Signature $parts[0]) -ne $parts[1]) { return $null }
  $fields = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-B64Url $parts[0])).Split('|')
  if ($fields.Length -ne 2) { return $null }
  if ([long]$fields[1] -lt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { return $null }
  return (Find-User (Get-Users) $fields[0])
}

function Send-Json($res, [int]$code, $obj) {
  $res.StatusCode = $code
  $res.ContentType = 'application/json; charset=utf-8'
  $res.Headers.Add('Cache-Control', 'no-store')
  $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $obj -Depth 5 -Compress))
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
}
function Read-Body($req) {
  $sr = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
  try { $t = $sr.ReadToEnd() } finally { $sr.Dispose() }
  if ([string]::IsNullOrWhiteSpace($t)) { return [pscustomobject]@{} }
  return ($t | ConvertFrom-Json)
}

# ---------------- API ----------------
function Invoke-Api($ctx) {
  $req = $ctx.Request; $res = $ctx.Response
  $path = $req.Url.AbsolutePath.ToLower(); $method = $req.HttpMethod

  if ($path -eq '/api/ping') { Send-Json $res 200 @{ ok = $true }; return }

  if ($path -eq '/api/login' -and $method -eq 'POST') {
    $b = Read-Body $req
    $id = ([string]$b.id).Trim().ToLower(); $pw = [string]$b.password
    $u = Find-User (Get-Users) $id
    if ($null -eq $u -or (Get-Sha256Hex ($u.salt + ':' + $pw)) -ne $u.hash) {
      Start-Sleep -Milliseconds 400
      Send-Json $res 401 @{ error = 'User ID or password is wrong. Please try again.' }; return
    }
    $hours = 12; if ($b.remember -eq $true) { $hours = 168 }
    Send-Json $res 200 @{ token = (New-Token $u $hours); user = (Get-PublicUser $u) }; return
  }

  $me = Get-TokenUser $req
  if ($null -eq $me) { Send-Json $res 401 @{ error = 'Please sign in again.' }; return }

  if ($path -eq '/api/me') { Send-Json $res 200 @{ user = (Get-PublicUser $me) }; return }

  if ($path -eq '/api/password' -and $method -eq 'POST') {
    $b = Read-Body $req
    if ((Get-Sha256Hex ($me.salt + ':' + [string]$b.old)) -ne $me.hash) { Send-Json $res 400 @{ error = 'Current password is wrong.' }; return }
    $new = [string]$b.new
    if ($new.Length -lt 6) { Send-Json $res 400 @{ error = 'New password must have at least 6 characters.' }; return }
    $users = Get-Users; $u = Find-User $users $me.id
    $u.salt = New-Salt; $u.hash = Get-Sha256Hex ($u.salt + ':' + $new)
    Save-Users $users
    Send-Json $res 200 @{ ok = $true }; return
  }

  if ($me.role -ne 'admin') { Send-Json $res 403 @{ error = 'Only an admin can manage users.' }; return }

  if ($path -eq '/api/users' -and $method -eq 'GET') {
    $list = @(); foreach ($u in (Get-Users)) { $list += (Get-PublicUser $u) }
    Send-Json $res 200 @{ users = $list }; return
  }

  if ($path -eq '/api/users/save' -and $method -eq 'POST') {
    $b = Read-Body $req
    $id = ([string]$b.id).Trim().ToLower(); $name = ([string]$b.name).Trim(); $pw = [string]$b.password
    $role = 'viewer'; if ($b.role -eq 'admin') { $role = 'admin' }
    if ($id -notmatch '^[a-z0-9._-]{2,30}$') { Send-Json $res 400 @{ error = 'User ID must be 2 to 30 characters: letters, numbers, dot, dash or underscore (no spaces).' }; return }
    if (-not $name) { $name = $id }
    $users = Get-Users; $ex = Find-User $users $id
    if ($b.isNew -eq $true) {
      if ($null -ne $ex) { Send-Json $res 409 @{ error = 'This user ID already exists.' }; return }
      if ($pw.Length -lt 6) { Send-Json $res 400 @{ error = 'Password must have at least 6 characters.' }; return }
      $salt = New-Salt
      $users += [pscustomobject]@{ id = $id; name = $name; role = $role; salt = $salt; hash = (Get-Sha256Hex ($salt + ':' + $pw)); created = (Get-Date).ToString('yyyy-MM-dd HH:mm') }
    } else {
      if ($null -eq $ex) { Send-Json $res 404 @{ error = 'User not found.' }; return }
      $admins = @($users | Where-Object { $_.role -eq 'admin' }).Count
      if ($ex.role -eq 'admin' -and $role -ne 'admin' -and $admins -le 1) { Send-Json $res 400 @{ error = 'At least one admin is needed.' }; return }
      $ex.name = $name; $ex.role = $role
      if ($pw) {
        if ($pw.Length -lt 6) { Send-Json $res 400 @{ error = 'Password must have at least 6 characters.' }; return }
        $ex.salt = New-Salt; $ex.hash = Get-Sha256Hex ($ex.salt + ':' + $pw)
      }
    }
    Save-Users $users
    Send-Json $res 200 @{ ok = $true }; return
  }

  if ($path -eq '/api/users/delete' -and $method -eq 'POST') {
    $b = Read-Body $req; $id = ([string]$b.id).Trim().ToLower()
    if ($id -eq $me.id) { Send-Json $res 400 @{ error = 'You cannot delete your own user.' }; return }
    $users = Get-Users; $ex = Find-User $users $id
    if ($null -eq $ex) { Send-Json $res 404 @{ error = 'User not found.' }; return }
    $admins = @($users | Where-Object { $_.role -eq 'admin' }).Count
    if ($ex.role -eq 'admin' -and $admins -le 1) { Send-Json $res 400 @{ error = 'At least one admin is needed.' }; return }
    Save-Users @($users | Where-Object { $_.id -ne $id })
    Send-Json $res 200 @{ ok = $true }; return
  }

  Send-Json $res 404 @{ error = 'Not found' }
}

# ---------------- web server ----------------
$null = Get-Users   # creates users.json with the default admin on first run

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch {
  Write-Host "Port $Port is busy. Trying $($Port+1)..." -ForegroundColor Yellow
  $Port++; $prefix = "http://localhost:$Port/"
  $listener = New-Object System.Net.HttpListener; $listener.Prefixes.Add($prefix); $listener.Start()
}

$types = @{ '.html'='text/html; charset=utf-8'; '.js'='application/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8';
            '.json'='application/json; charset=utf-8'; '.png'='image/png'; '.svg'='image/svg+xml'; '.ico'='image/x-icon' }
$blocked = @('users.json', 'secret.key', 'server.ps1', 'server_basic.ps1')

Write-Host ''
Write-Host "  Waterproofing dashboard is running at  $prefix" -ForegroundColor Green
Write-Host '  Users are saved in users.json. Keep this window open. Press Ctrl+C to stop.'
Write-Host ''
Start-Process $prefix

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $res = $ctx.Response
  try {
    $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ($rel.ToLower().StartsWith('api/')) {
      Invoke-Api $ctx
    } else {
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }
      $file = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
      $name = [System.IO.Path]::GetFileName($file).ToLower()
      if ($file.StartsWith($root) -and ($blocked -notcontains $name) -and (Test-Path $file -PathType Leaf)) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $res.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
        $res.Headers.Add('Cache-Control', 'no-store')
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } else {
        $res.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes('Not found')
        $res.OutputStream.Write($msg, 0, $msg.Length)
      }
    }
  } catch {
    Write-Host ('  Error: ' + $_.Exception.Message) -ForegroundColor Red
    try { Send-Json $res 500 @{ error = ('Server error: ' + $_.Exception.Message) } } catch { }
  } finally {
    try { $res.Close() } catch { }
  }
}
