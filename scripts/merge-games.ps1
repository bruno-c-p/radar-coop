# Junta o resultado do sync-feed.ps1 ao games.json do site (C:\Users\PC\radar-coop).
# Sem -Apply: só mostra "NEW: ..." e "UPDATED: ...".
# Com -Apply: adiciona os novos (com mídia de -MediaDir, se houver), marca os atualizados e grava games.json.
# -DescFile: JSON opcional {"<id>": "descrição em pt-BR"} que substitui a descrição da Steam.
# -Push: faz commit e push no GitHub.
param(
  [Parameter(Mandatory)][string]$SyncDir,
  [string]$Site = 'C:\Users\PC\radar-coop',
  [string]$MediaDir = "$env:TEMP\radar-coop-media",
  [string]$DescFile,
  [switch]$Apply,
  [switch]$Push
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$jsonPath = Join-Path $Site 'games.json'
$games = [Collections.ArrayList]@()
if (Test-Path $jsonPath) { $arr = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($g in $arr) { [void]$games.Add($g) } }
$byId = @{}; foreach ($g in $games) { $byId[[string]$g.id] = $g }

$new = @(); $upd = @()
foreach ($f in Get-ChildItem (Join-Path $SyncDir '*.json')) {
  $id = $f.BaseName; $s = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  if (-not $byId.ContainsKey($id)) { $new += $id }
  elseif ([DateTimeOffset]::Parse($s.d) -gt [DateTimeOffset]::Parse($byId[$id].d)) { $upd += $id }
}
"NEW: $($new -join ',')"
"UPDATED: $($upd -join ',')"
if (-not $Apply) { exit 0 }

$descs = @{}
if ($DescFile -and (Test-Path $DescFile)) { (Get-Content $DescFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $descs[$_.Name] = $_.Value } }
$mediaOut = Join-Path $Site 'media'; New-Item -ItemType Directory -Force $mediaOut | Out-Null

foreach ($id in $new) {
  $s = Get-Content (Join-Path $SyncDir "$id.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  $s | Add-Member -NotePropertyName id -NotePropertyValue $id -Force
  $mj = Join-Path $MediaDir "$id.media.json"
  if (Test-Path $mj) {
    $m = Get-Content $mj -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.found) {
      $map = @{ cap = @($m.capsule, "$id-capsule.jpg"); img = @($m.hero, "$id-img.jpg"); clip = @($m.clip, "$id-clip.mp4") }
      foreach ($k in $map.Keys) {
        $from = $map[$k][0]; $to = $map[$k][1]
        if ($from -and (Test-Path (Join-Path $MediaDir $from))) { Copy-Item (Join-Path $MediaDir $from) (Join-Path $mediaOut $to) -Force; $s | Add-Member -NotePropertyName $k -NotePropertyValue "media/$to" -Force }
      }
      if ($m.appid) { $s | Add-Member -NotePropertyName appid -NotePropertyValue $m.appid -Force }
      if ($m.desc) { $s | Add-Member -NotePropertyName desc -NotePropertyValue $m.desc -Force }
    }
  }
  if ($descs.ContainsKey($id)) { $s | Add-Member -NotePropertyName desc -NotePropertyValue $descs[$id] -Force }
  [void]$games.Add($s)
}
foreach ($id in $upd) {
  $s = Get-Content (Join-Path $SyncDir "$id.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  $g = $byId[$id]
  if (-not $g.PSObject.Properties['first']) { $g | Add-Member -NotePropertyName first -NotePropertyValue $g.d -Force }
  $g.d = $s.d
  $g | Add-Member -NotePropertyName upd -NotePropertyValue $true -Force
}
$sorted = @($games | Sort-Object { [DateTimeOffset]::Parse($_.d) } -Descending)
[IO.File]::WriteAllText($jsonPath, (ConvertTo-Json $sorted -Depth 4), $utf8)
"WROTE: $($sorted.Count) jogos"

if ($Push -and ($new.Count -or $upd.Count)) {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
  Push-Location $Site
  try {
    git add -A
    git commit -q -m ("Atualização " + (Get-Date -Format 'yyyy-MM-dd') + ": $($new.Count) novos, $($upd.Count) atualizados")
    git push -q origin main
    "PUSHED"
  } finally { Pop-Location }
}
