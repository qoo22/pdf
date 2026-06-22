param([int]$Port = 8765, [string]$Root = $PSScriptRoot)

$rootFull = [System.IO.Path]::GetFullPath($Root)

# Handles one connection. Each connection runs on its own runspace thread so that
# concurrent requests (e.g. thumbnail generation) never block the whole server.
$handler = {
  param($client, $rootFull)
  $mime = @{
    ".html" = "text/html; charset=utf-8"; ".js" = "text/javascript"; ".css" = "text/css"
    ".png" = "image/png"; ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".svg" = "image/svg+xml"
    ".json" = "application/json"; ".wasm" = "application/wasm"; ".ico" = "image/x-icon"
    ".bat" = "text/plain"; ".ps1" = "text/plain"
  }
  try {
    $client.NoDelay = $true
    $stream = $client.GetStream()
    $stream.ReadTimeout = 5000
    $stream.WriteTimeout = 15000
    $reader = New-Object System.IO.StreamReader($stream)
    $reqLine = $reader.ReadLine()
    while ($true) {
      $line = $reader.ReadLine()
      if ($null -eq $line -or $line -eq "") { break }
    }
    if (-not $reqLine) { return }
    $parts = $reqLine.Split(' ')
    if ($parts.Count -lt 2) { return }
    $path = [Uri]::UnescapeDataString(($parts[1] -split '\?')[0])
    if ($path -eq '/') { $path = '/index.html' }
    $file = Join-Path $rootFull ($path.TrimStart('/') -replace '/', '\')
    $full = [System.IO.Path]::GetFullPath($file)
    if ($full.StartsWith($rootFull) -and (Test-Path -LiteralPath $full -PathType Leaf)) {
      $bytes = [System.IO.File]::ReadAllBytes($full)
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      if ($mime.ContainsKey($ext)) { $ct = $mime[$ext] } else { $ct = "application/octet-stream" }
      $header = "HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    } else {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
      $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain`r`nConnection: close`r`n`r`n"
    }
    $hb = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($hb, 0, $hb.Length)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
  } catch {
  } finally {
    $client.Close()
  }
}

$pool = [runspacefactory]::CreateRunspacePool(1, 24)
$pool.Open()

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
Write-Host "Serving $rootFull at http://localhost:$Port/"

$jobs = New-Object System.Collections.ArrayList
while ($true) {
  $client = $listener.AcceptTcpClient()
  $ps = [powershell]::Create()
  $ps.RunspacePool = $pool
  [void]$ps.AddScript($handler).AddArgument($client).AddArgument($rootFull)
  $h = $ps.BeginInvoke()
  [void]$jobs.Add([pscustomobject]@{ ps = $ps; h = $h })
  for ($i = $jobs.Count - 1; $i -ge 0; $i--) {
    if ($jobs[$i].h.IsCompleted) {
      try { $jobs[$i].ps.EndInvoke($jobs[$i].h) } catch {}
      $jobs[$i].ps.Dispose()
      $jobs.RemoveAt($i)
    }
  }
}
