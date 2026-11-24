# Baixa mídia da Steam para um jogo: capa, pôster, screenshots, descrição em pt-BR e um trecho de 15 s do trailer (360p, sem áudio).
# Uso: powershell -NoProfile -File fetch-media.ps1 -Name "<nome>" -Id <id-do-online-fix> -OutDir <pasta> [-AppId <steam appid>]
param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$OutDir, [string]$AppId)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
function Get-Json($u) { [Text.Encoding]::UTF8.GetString($wc.DownloadData($u)) | ConvertFrom-Json }
function Save-Url($u, $f) { try { $wc.DownloadFile($u, (Join-Path $OutDir $f)); return $f } catch { return $null } }

if (-not $AppId) {
  $clean = ($Name -replace '[^\p{L}\p{N} ]', ' ' -replace '\s+', ' ').Trim()
  $hit = $null
  foreach ($term in @($clean, ($clean -replace '(?i)\s+online$', ''), ((($clean -split ' ') | Select-Object -First 3) -join ' ')) | Select-Object -Unique) {
    $s = Get-Json ("https://store.steampowered.com/api/storesearch/?cc=br&l=english&term=" + [uri]::EscapeDataString($term))
    $hit = $s.items | Where-Object { $_.name -notmatch '(?i)demo|soundtrack|pack|expansion|dlc|upgrade|pass' } | Select-Object -First 1
    if ($hit) { break }
  }
  if (-not $hit) { '{"found":false}' | Out-File (Join-Path $OutDir "$Id.media.json") -Encoding utf8; "NOTFOUND $Name"; exit 0 }
  $AppId = $hit.id
}
$g = (Get-Json "https://store.steampowered.com/api/appdetails?appids=$AppId&cc=br&l=brazilian").$AppId.data
$cdn = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$AppId"
$m = [ordered]@{ found = $true; appid = [int]$AppId; desc = $g.short_description; genres = @($g.genres | ForEach-Object { $_.description }) }
$m.capsule = Save-Url "$cdn/capsule_616x353.jpg" "$Id-capsule.jpg"
if (-not $m.capsule) { $m.capsule = Save-Url $g.header_image "$Id-capsule.jpg" }
$m.poster = Save-Url "$cdn/library_600x900.jpg" "$Id-poster.jpg"
$m.hero = Save-Url "$cdn/library_hero.jpg" "$Id-hero.jpg"
$shots = @(); $n = 0
foreach ($sh in ($g.screenshots | Select-Object -First 3)) { $n++; $f = Save-Url (($sh.path_full -split '\?')[0] -replace '1920x1080', '1920x1080') "$Id-shot$n.jpg"; if ($f) { $shots += $f } }
$m.shots = $shots
if (-not $m.hero -and $shots.Count) { $m.hero = $shots[0] }
# Trecho do trailer: init + 5 segmentos fMP4 (3 s cada) do stream de vídeo de menor resolução.
$mov = $g.movies | Where-Object { $_.highlight } | Select-Object -First 1
if (-not $mov) { $mov = $g.movies | Select-Object -First 1 }
if ($mov -and $mov.hls_h264) {
  try {
    $base = ($mov.hls_h264 -split '\?')[0]; $base = $base.Substring(0, $base.LastIndexOf('/') + 1)
    $master = [Text.Encoding]::UTF8.GetString($wc.DownloadData($mov.hls_h264))
    $vids = @($master -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '_video\.m3u8$' })
    $pl = [Text.Encoding]::UTF8.GetString($wc.DownloadData($base + $vids[-1]))
    $init = [regex]::Match($pl, 'URI="([^"]+)"').Groups[1].Value
    $segs = @($pl -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 5)
    $out = [IO.File]::Create((Join-Path $OutDir "$Id-clip.mp4"))
    foreach ($part in @($init) + $segs) { $b = $wc.DownloadData($base + $part); $out.Write($b, 0, $b.Length) }
    $out.Close(); $m.clip = "$Id-clip.mp4"
  } catch { $m.clip = $null }
}
[IO.File]::WriteAllText((Join-Path $OutDir "$Id.media.json"), ($m | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
"OK $Name appid=$AppId capsule=$($m.capsule) poster=$($m.poster) hero=$($m.hero) shots=$($shots.Count) clip=$($m.clip)"
