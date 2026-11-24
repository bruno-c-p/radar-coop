# Baixa o RSS de online-fix.me, traduz os campos e grava um JSON por jogo em $OutDir.
# Uso: powershell -NoProfile -File sync-feed.ps1 -OutDir <pasta>
param([Parameter(Mandatory)][string]$OutDir)
$ErrorActionPreference = 'Stop'
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('User-Agent', 'Mozilla/5.0')
$text = [System.Text.Encoding]::GetEncoding(1251).GetString($wc.DownloadData('https://online-fix.me/rss.xml'))
[xml]$x = $text -replace 'encoding="windows-1251"', 'encoding="utf-8"'

$cats = @{ officialservers='Servidores oficiais'; puzzles='Quebra-cabeça'; adventures='Aventura'; arcade='Arcade'; sandbox='Sandbox';
           action='Ação'; shooters='Tiro'; rpg='RPG'; strategy='Estratégia'; simulators='Simulador'; racing='Corrida'; sport='Esporte';
           horror='Terror'; survival='Sobrevivência'; fighting='Luta'; indie='Indie' }
$ids = @()
foreach ($i in $x.rss.channel.item) {
  $link = [string]$i.link
  if ($link -notmatch '/games/([^/]+)/(\d+)-') { continue }
  $slug = $Matches[1]; $id = $Matches[2]
  $desc = if ($i.description -is [string]) { $i.description } else { $i.description.InnerText }
  $rel = if ($desc -match '(\d{2})\.(\d{2})\.(\d{4})') { "$($Matches[1])/$($Matches[2])/$($Matches[3])" } else { '' }
  $via = if ($desc -match '<a [^>]*>([^<]+)</a>') { $Matches[1].Trim() } else { '' }
  $coop = $desc -match '(Кооператив|Cooperative)\s*<span class="fa fa-check"'
  $mp   = $desc -match '(Мультиплеер|Multiplayer)\s*<span class="fa fa-check"'
  $title = ([string]$i.title) -replace '\s*по сети\s*$', ''
  $date = [DateTimeOffset]::Parse([string]$i.pubDate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $cat = if ($cats.ContainsKey($slug)) { $cats[$slug] } else { $slug }
  $doc = [ordered]@{ t=$title; u=$link; d=$date; rel=$rel; via=$via; coop=[bool]$coop; mp=[bool]$mp; cat=$cat }
  [System.IO.File]::WriteAllText((Join-Path $OutDir "$id.json"), ($doc | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
  $ids += $id
}
"IDS: $($ids -join ',')"
