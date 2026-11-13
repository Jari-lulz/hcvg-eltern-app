# Holt Tabellen, Spielplaene und Spielberichte von nuLiga (HVMV) und schreibt data.js.
# Laeuft mit Windows PowerShell 5.1 und PowerShell 7 (auch auf GitHub Actions).
# Aufruf:  powershell -ExecutionPolicy Bypass -File tools\update-data.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root    = Split-Path -Parent $PSScriptRoot
$CacheDir = Join-Path $PSScriptRoot 'cache'
$OutFile = Join-Path $Root 'data.js'
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir | Out-Null }

$Base  = 'https://hvmv-handball.liga.nu/cgi-bin/WebObjects/nuLigaHBDE.woa/wa'
$Champ = 'BHV+Ost+26%2F27'
$Leagues = [ordered]@{
  D = @{ name = 'Bezirksoberliga wJD'; group = '486919' }
  C = @{ name = 'Bezirksoberliga wJC'; group = '486898' }
}

function Get-Page([string]$url) {
  Start-Sleep -Milliseconds 400   # nuLiga schonen
  $r = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'HCVG-Mannschafts-App (Spielplan-Update)' }
  $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  return ($text -replace '\s+', ' ')
}

function Clean([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s -replace '<[^>]+>', ' '
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  $t = $t -replace [char]0xA0, ' '
  return ($t -replace '\s+', ' ').Trim()
}

function ToInt([string]$s) { $c = Clean $s; if ($c -match '^-?\d+$') { return [int]$c } else { return 0 } }

# "Adam, Fabienne" -> "Fabienne A." (Kinder: nur Vorname + Initiale)
function ShortName([string]$s) {
  $c = Clean $s
  if ($c -notmatch ',') { return $c }
  $parts = $c.Split(',', 2)
  $last = $parts[0].Trim(); $first = $parts[1].Trim()
  $lastWord = ($last -split ' ')[-1]
  if (-not $lastWord) { return $first }
  return "$first $($lastWord.Substring(0,1))."
}

function Get-Cells([string]$rowHtml) {
  $list = @()
  foreach ($m in [regex]::Matches($rowHtml, '<td([^>]*)>(.*?)</td>')) {
    $list += , @($m.Groups[1].Value, $m.Groups[2].Value)
  }
  return , $list
}

function Get-TableAfter([string]$html, [string]$marker) {
  $i = $html.IndexOf($marker)
  if ($i -lt 0) { return '' }
  $j = $html.IndexOf('<table', $i)
  $k = $html.IndexOf('</table>', $j)
  return $html.Substring($j, $k - $j)
}

function Parse-Table([string]$html) {
  $tbl = Get-TableAfter $html 'Tabelle</h2>'
  $rows = @()
  foreach ($tr in ($tbl -split '<tr')) {
    if ($tr -match '<th') { continue }
    $c = Get-Cells $tr
    if ($c.Count -lt 10) { continue }
    $tore = Clean $c[7][1]
    $diff = (Clean $c[8][1]) -replace '\+', ''
    $rows += , @((Clean $c[2][1]), (ToInt $c[3][1]), (ToInt $c[4][1]), (ToInt $c[5][1]), (ToInt $c[6][1]), $tore, [int]$diff, (Clean $c[9][1]))
  }
  return , $rows
}

$HallNames = @{}

function Parse-Games([string]$html) {
  $tbl = Get-TableAfter $html 'Spielplan (Gesamt)</h2>'
  $games = @()
  $prevDate = ''
  foreach ($tr in ($tbl -split '<tr')) {
    if ($tr -match '<th') { continue }
    $c = Get-Cells $tr
    if ($c.Count -lt 8) { continue }
    $date = ''
    if ($c[0][0] -match 'colspan="2"') {
      # "Termin offen": eine Zelle weniger -> ausrichten
      $c = , $c[0] + , @('', '') + $c[1..($c.Count - 1)]
    } else {
      $d = Clean $c[1][1]
      if ($d -match '\d{2}\.\d{2}\.\d{4}') { $date = $Matches[0] }
      elseif ($c[0][0] -match 'tabelle-rowspan') { $date = $prevDate }
      $prevDate = $date
    }
    $timeTxt = Clean $c[2][1]
    $time = ''; if ($timeTxt -match '\d{2}:\d{2}') { $time = $Matches[0] }
    $note = ''
    if ($c[2][0] -match 'title="([^"]*verlegt[^"]*)"') { $note = 'verlegt' }
    if (-not $date) { $note = 'Termin offen' }
    $loc = ''; if ($c[3][1] -match 'location=(\d+)') { $loc = $Matches[1] }
    if ($loc -and $c[3][1] -match 'title="([^"]+)"') { $HallNames[$loc] = [System.Net.WebUtility]::HtmlDecode($Matches[1]) }
    $hm = Clean $c[5][1]; $away = Clean $c[6][1]
    if ($hm -match 'ENDRUNDE' -or $away -match 'ENDRUNDE') { $note = 'Endrunde' }
    $resCell = $c[7][1]
    $res = ''; $mid = ''; $ref = ''
    if ($resCell -match 'meeting=(\d+)') { $mid = $Matches[1] }
    $resTxt = Clean $resCell
    if ($resTxt -match '^(\d+:\d+)') { $res = $Matches[1] }
    elseif ($resCell -match '<span title="([^"]+)"') { $ref = $Matches[1] }   # angesetzter Schiri
    $approved = [bool]($tr -match 'Spielbericht genehmigt')
    $games += , @($date, $time, $loc, $hm, $away, $res, $note, $mid, $approved, $ref)
  }
  return , $games
}

function Parse-Players([string]$tbody) {
  $out = @()
  foreach ($tr in ($tbody -split '<tr')) {
    $c = Get-Cells $tr
    if ($c.Count -lt 12) { continue }
    $nr = Clean $c[0][1]
    if ($nr -notmatch '^\d+$') { continue }   # Offizielle (A, B, ...) weglassen
    $person = ''; if ($c[1][1] -match 'person=(\d+)') { $person = $Matches[1] }
    $s7 = Clean $c[5][1]; $g7 = 0; $a7 = 0
    if ($s7 -match '(\d+)/(\d+)') { $g7 = [int]$Matches[1]; $a7 = [int]$Matches[2] }
    $two = 0; foreach ($k in 7, 8, 9) { if ((Clean $c[$k][1]) -ne '') { $two++ } }
    $dq = 0; foreach ($k in 10, 11) { if ((Clean $c[$k][1]) -ne '') { $dq++ } }
    $yel = 0; if ((Clean $c[6][1]) -ne '') { $yel = 1 }
    $out += , @([int]$nr, (ShortName $c[1][1]), $person, (ToInt $c[4][1]), $g7, $a7, $yel, $two, $dq)
  }
  return , $out
}

function Parse-Report([string]$html) {
  $teams = [regex]::Matches($html, '<thead>(?:(?!</thead>).)*Trikot.*?</thead>\s*<tbody>(.*?)</tbody>')
  $sum = {
    param($label, $idx)
    $m = [regex]::Matches($html, "<td>$([regex]::Escape($label))</td>\s*<td>([^<]*)</td>")
    if ($m.Count -gt $idx) { return (ToInt $m[$idx].Groups[1].Value) } else { return 0 }
  }
  $side = {
    param($idx)
    $p = @(); if ($teams.Count -gt $idx) { $p = Parse-Players $teams[$idx].Groups[1].Value }
    $to = 0
    foreach ($t in 1, 2, 3) {
      $m = [regex]::Matches($html, "<td>Timeout $t</td>\s*<td>([^<]*)</td>")
      if ($m.Count -gt $idx -and (Clean $m[$idx].Groups[1].Value) -ne '') { $to++ }
    }
    return [ordered]@{
      p  = $p
      s7 = (& $sum '7-Meter' $idx); g7 = (& $sum '7-Meter-Tore' $idx)
      m2 = (& $sum '2-Minuten' $idx); y = (& $sum 'gelbe Karten' $idx)
      d  = (& $sum 'Disqualifikationen' $idx); to = $to
    }
  }
  $ht = ''
  if ($html -match '<td>Ergebnis</td>\s*<td>\s*\d+:\d+\s*\((\d+:\d+)\)') { $ht = $Matches[1] }
  $sr = @()
  $pers = Get-TableAfter $html 'Personen</h2>'
  foreach ($tr in ($pers -split '<tr')) {
    $c = Get-Cells $tr
    if ($c.Count -ge 2 -and (Clean $c[0][1]) -match '^SR') { $sr += (ShortName $c[1][1]) }
  }
  $ev = @()
  $tl = Get-TableAfter $html 'Spielverlauf</h2>'
  foreach ($tr in ($tl -split '<tr')) {
    $c = Get-Cells $tr
    if ($c.Count -lt 4) { continue }
    $team = Clean $c[0][1]; $time = Clean $c[1][1]; $what = Clean $c[3][1]
    $nr = 0; if ($c.Count -ge 5 -and (Clean $c[4][1]) -match '^(\d+)\s') { $nr = [int]$Matches[1] }   # Rueckennummer der Werferin
    if ($time -notmatch '^(\d+):(\d+)$') { continue }
    $sec = [int]$Matches[1] * 60 + [int]$Matches[2]
    $s = 0
    if ($team -eq 'Heim' -or $what -match 'Heim') { $s = 1 } elseif ($team -eq 'Gast' -or $what -match 'Gast') { $s = 2 }
    $code = switch -Regex ($what) {
      '^Tor$' { 'g' } '7m mit Tor' { '7g' } '7m ohne Tor' { '7x' } 'Verwarnung' { 'y' }
      '2-?min|Zeitstrafe' { '2' } 'Disqual' { 'd' } 'Auszeit' { 't' } default { $what }
    }
    $ev += , @($sec, $s, $code, $nr)
  }
  return [ordered]@{ ht = $ht; sr = $sr; h = (& $side 0); a = (& $side 1); ev = $ev }
}

# Kuchen-Regel: Wer hat in einem Spiel das 30. Tor fuer uns geworfen?
# Steht nicht im nuLiga-Bericht, aber in der nuScore-Ereignisliste (mit Spielstand und Werferin).
$Us = 'HC Vorpommern-Greifswald'
# Capri-Sonne-Regel: Wer das 40. Tor wirft, bringt einen 10er-Traeger Capri-Sonne mit.
function Get-Scorer30([string]$mid, [bool]$usHome, [int]$target = 30) {
  try {
    Start-Sleep -Milliseconds 300
    $r = Invoke-WebRequest -UseBasicParsing "https://hbde-live.liga.nu/nuScoreLiveRestBackend/api/1/events/$mid" -Headers @{ 'User-Agent' = 'HCVG-Mannschafts-App (Spielplan-Update)' }
    $e = ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())) | ConvertFrom-Json
    foreach ($x in ($e.events | Sort-Object idx)) {
      if ($x.event -ne 4 -and $x.event -ne 5) { continue }        # 4 = Tor, 5 = 7m-Tor
      if ([bool]$x.teamHome -ne $usHome) { continue }
      $pts = if ($usHome) { $x.pointsHome } else { $x.pointsGuest }
      if ($pts -eq $target -and $x.personFirstname -and $x.personFirstname -ne 'Anonym') {
        return (ShortName "$($x.personLastname), $($x.personFirstname)")
      }
    }
  } catch { Write-Host "  nuScore $mid nicht erreichbar" }
  return ''
}

$out = [ordered]@{
  updated = (Get-Date).ToString('dd.MM.yyyy, HH:mm') + ' Uhr'
  leagues = [ordered]@{}
  halls   = @{}
}

foreach ($key in $Leagues.Keys) {
  $L = $Leagues[$key]
  Write-Host "Liga $key ($($L.group)) ..."
  $tablePage = Get-Page "$Base/groupPage?championship=$Champ&group=$($L.group)"
  $gamesPage = Get-Page "$Base/groupPage?championship=$Champ&group=$($L.group)&displayTyp=vorrunde&displayDetail=meetings"
  $table = Parse-Table $tablePage
  $games = Parse-Games $gamesPage
  $reports = [ordered]@{}
  $cake = [ordered]@{}
  $capri = [ordered]@{}
  $outGames = @()
  foreach ($g in $games) {
    $mid = $g[7]
    if ($mid -and $g[5] -and ($g[3] -eq $Us -or $g[4] -eq $Us)) {
      $usHome = $g[3] -eq $Us
      $ourGoals = [int](($g[5] -split ':')[$(if ($usHome) { 0 } else { 1 })])
      if ($ourGoals -ge 30) {
        $cakeFile = Join-Path $CacheDir "cake-$mid.txt"
        if (Test-Path $cakeFile) { $who = [IO.File]::ReadAllText($cakeFile, [Text.Encoding]::UTF8).Trim() }
        else {
          Write-Host "  30. Tor in Spiel $mid"
          $who = Get-Scorer30 $mid $usHome
          if ($who -and $g[8]) { [IO.File]::WriteAllText($cakeFile, $who, (New-Object Text.UTF8Encoding $false)) }
        }
        if ($who) { $cake[$mid] = $who }
      }
      if ($ourGoals -ge 40) {
        $capFile = Join-Path $CacheDir "capri-$mid.txt"
        $who40 = ''
        if (Test-Path $capFile) { $who40 = [IO.File]::ReadAllText($capFile, [Text.Encoding]::UTF8).Trim() }
        else {
          Write-Host "  40. Tor in Spiel $mid"
          $who40 = Get-Scorer30 $mid $usHome 40
          if ($who40 -and $g[8]) { [IO.File]::WriteAllText($capFile, $who40, (New-Object Text.UTF8Encoding $false)) }
        }
        if ($who40) { $capri[$mid] = $who40 }
      }
    }
    if ($mid -and $g[5]) {
      $cacheFile = Join-Path $CacheDir "$mid.v2.json"   # v2: Ereignisse mit Rueckennummer
      $rep = $null
      if (Test-Path $cacheFile) {
        $rep = [IO.File]::ReadAllText($cacheFile, [Text.Encoding]::UTF8)
      } else {
        Write-Host "  Spielbericht $mid"
        $obj = Parse-Report (Get-Page "$Base/groupMeetingReport?meeting=$mid&championship=$Champ&group=$($L.group)")
        $rep = ConvertTo-Json -InputObject $obj -Depth 8 -Compress
        if ($g[8]) { [IO.File]::WriteAllText($cacheFile, $rep, (New-Object Text.UTF8Encoding $false)) }  # nur genehmigte cachen
      }
      $reports[$mid] = '@@' + $mid + '@@'
      Set-Variable -Name "rep_$mid" -Value $rep -Scope Script
    }
    # [Datum, Zeit, Halle, Heim, Gast, Ergebnis, Notiz, Bericht-ID, angesetzter Schiri]
    $refShort = ''
    if ($g[9] -match '/') { $refShort = ($g[9] -replace [string][char]0xA7, '').Trim() }   # z. B. "Heim-/Gastverein" stellt den Schiri
    elseif ($g[9]) { $p = $g[9].Trim() -split ' '; if ($p.Count -ge 2) { $refShort = "$($p[1]) $($p[0].Substring(0,1))." } else { $refShort = $g[9] } }
    $outGames += , @($g[0], $g[1], $g[2], $g[3], $g[4], $g[5], $g[6], $g[7], $refShort)
  }
  # Live-Spielstand (nuScore): eine Abfrage pro Liga, nur unsere Spiele von +/- 3 Tagen
  # [Heim, Gast, Anwurf (UTC, ISO), Tore Heim, Tore Gast, live, HZ Heim, HZ Gast]
  $live = @()
  try {
    $ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 15) * 15
    $r = Invoke-WebRequest -UseBasicParsing "https://hbde-live.liga.nu/nuScoreLiveRestBackend/api/1/meetings/$($L.group)/time/$ts" -Headers @{ 'User-Agent' = 'HCVG-Mannschafts-App (Spielplan-Update)' }
    $mj = ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())) | ConvertFrom-Json
    $nowU = [DateTime]::UtcNow
    foreach ($m in $mj.meetings) {
      if ($m.teamHome -ne $Us -and $m.teamGuest -ne $Us) { continue }
      $sch = [DateTimeOffset]::Parse([string]$m.scheduled, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
      if ([Math]::Abs(($sch - $nowU).TotalDays) -gt 3) { continue }
      $live += , @($m.teamHome, $m.teamGuest, $sch.ToString('yyyy-MM-ddTHH:mm:ssZ'), [int]$m.matchesHome, [int]$m.matchesGuest, [bool]$m.live, [int]$m.halfTimeScoreHome, [int]$m.halfTimeScoreGuest)
    }
  } catch { Write-Host "  nuScore-Liveliste $($L.group) nicht erreichbar" }
  $out.leagues[$key] = [ordered]@{ name = $L.name; group = $L.group; table = $table; games = $outGames; reports = $reports; cake = $cake; capri = $capri; live = $live }
}
foreach ($k in $HallNames.Keys) { $out.halls[$k] = $HallNames[$k] }

# Hallen mit Adresse (von Hand gepflegt in tools/halls.json)
$HallInfo = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'halls.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$out.hallInfo = $HallInfo

# ---------- Kalender zum Abonnieren (kalender-c.ics, kalender-d.ics, kalender.ics) ----------
# Termin beginnt beim Treff (1 Stunde vor Anwurf) und endet ca. 30 Minuten nach Spielende.
$GameLen = @{ D = 40; C = 50 }
$AppUrl  = 'https://jari-lulz.github.io/hcvg-mannschafts-app/'
$ae = [char]0xE4

# Route-Link: Adresse mit Hausnummer -> nur Adresse; ohne Hausnummer -> Hallenname + Adresse (wie in der App)
function MapsLink([string]$name, [string]$addr) {
  $dest = if ($addr -and $addr -match '\d+[a-z]?\s*(-\s*\d+)?\s*,') { $addr } else { (@($name, $addr) | Where-Object { $_ }) -join ', ' }
  return 'https://www.google.com/maps/dir/?api=1&destination=' + [uri]::EscapeDataString($dest)
}
function IcsText([string]$s) { return ($s -replace '\\', '\\\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n') }
function IcsFold([string]$line) {
  # Zeilen laenger als 74 Zeichen umbrechen (Folgezeile beginnt mit Leerzeichen)
  if ($line.Length -le 74) { return $line }
  $parts = @(); $i = 0
  while ($i -lt $line.Length) { $n = [Math]::Min(73, $line.Length - $i); $parts += $line.Substring($i, $n); $i += $n }
  return ($parts -join "`r`n ")
}
function ShortTeam([string]$t) { if ($t -eq $Us) { return 'HC VG' } elseif ($t -match 'Platzhalter') { return 'Gegner offen' } else { return $t } }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'")
$events = @{ D = @(); C = @() }
foreach ($key in $out.leagues.Keys) {
  $seen = @{}
  foreach ($g in $out.leagues[$key].games) {
    $date, $time, $loc, $hm, $away, $res, $note = $g[0], $g[1], $g[2], $g[3], $g[4], $g[5], $g[6]
    if (-not $date) { continue }
    if ($hm -ne $Us -and $away -ne $Us) { continue }
    $d = [datetime]::ParseExact($date, 'dd.MM.yyyy', $null)
    $pair = "$key-$hm-$away"; $seen[$pair] = 1 + [int]$seen[$pair]
    $uid = (($pair + '-' + $seen[$pair]) -replace '[^A-Za-z0-9-]', '') + '@hcvg-eltern-app'
    $usHome = $hm -eq $Us
    $title = "$key-Jugend: $(ShortTeam $hm) - $(ShortTeam $away)"
    if ($res) { $title += " ($res)" }
    $hallN = ''; $hallA = ''
    if ($loc -and $HallInfo.$loc) { $hallN = $HallInfo.$loc[0]; $hallA = $HallInfo.$loc[1] }
    elseif ($loc -and $HallNames[$loc]) { $hallN = $HallNames[$loc] }
    $where = (@($hallN, $hallA) | Where-Object { $_ }) -join ', '
    $maps = ''
    if ($where) { $maps = MapsLink $hallN $hallA }
    $desc = @()
    if ($usHome) { $desc += 'Heimspiel' } else { $desc += "Ausw${ae}rtsspiel" }
    $lines = @('BEGIN:VEVENT', "UID:$uid", "DTSTAMP:$stamp")
    if ($time -and $time -ne '00:00') {
      $kick = $d.Add([timespan]::Parse($time))
      $start = $kick.AddMinutes(-60); $end = $kick.AddMinutes($GameLen[$key] + 40)
      $desc += "Treff: $($start.ToString('HH:mm')) Uhr"
      $desc += "Anwurf: $time Uhr"
      $lines += "DTSTART;TZID=Europe/Berlin:$($start.ToString("yyyyMMdd'T'HHmmss"))"
      $lines += "DTEND;TZID=Europe/Berlin:$($end.ToString("yyyyMMdd'T'HHmmss"))"
    } else {
      $desc += 'Uhrzeit noch offen'
      $lines += "DTSTART;VALUE=DATE:$($d.ToString('yyyyMMdd'))"
      $lines += "DTEND;VALUE=DATE:$($d.AddDays(1).ToString('yyyyMMdd'))"
    }
    if ($note) { $desc += "Hinweis: $note" }
    if ($res) { $desc += "Ergebnis: $res" }
    if ($where) { $desc += "Halle: $where" }
    if ($maps) { $desc += "Route: $maps" }
    $desc += "Alle Infos: $AppUrl"
    $lines += "SUMMARY:$(IcsText $title)"
    if ($where) { $lines += "LOCATION:$(IcsText $where)" }
    $lines += "DESCRIPTION:$(IcsText ($desc -join "`n"))"
    if ($maps) { $lines += "URL:$maps" }
    $lines += 'END:VEVENT'
    $events[$key] += , (($lines | ForEach-Object { IcsFold $_ }) -join "`r`n")
  }
}

# Trainings als woechentliche Serientermine (aus tools/training.json)
$Training = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'training.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$out.training = $Training
$tEvents = @{ D = @(); C = @(); CD = @() }
$byDay = @{ Mo = 'MO'; Di = 'TU'; Mi = 'WE'; Do = 'TH'; Fr = 'FR'; Sa = 'SA'; So = 'SU' }
$dowNum = @{ Mo = 1; Di = 2; Mi = 3; Do = 4; Fr = 5; Sa = 6; So = 0 }
$tFrom = [datetime]::ParseExact($Training.from, 'yyyy-MM-dd', $null)
$tUntil = [datetime]::ParseExact($Training.until, 'yyyy-MM-dd', $null)
$tWhere = ''
if ($Training.hall -and $HallInfo.($Training.hall)) { $tWhere = ($HallInfo.($Training.hall)[0] + ', ' + $HallInfo.($Training.hall)[1]) }
$tMaps = if ($tWhere) { MapsLink $HallInfo.($Training.hall)[0] $HallInfo.($Training.hall)[1] } else { '' }
foreach ($day in $Training.days) {
  $short, $full, $times, $who = $day[0], $day[1], $day[2], $day[3]
  if ($times -notmatch '(\d{1,2}:\d{2})\D+(\d{1,2}:\d{2})') { continue }
  $t1 = $Matches[1]; $t2 = $Matches[2]
  $first = $tFrom; while ([int]$first.DayOfWeek -ne $dowNum[$short]) { $first = $first.AddDays(1) }
  $s = $first.Add([timespan]::Parse($t1)); $e = $first.Add([timespan]::Parse($t2))
  $label = if ($who -eq 'CD') { 'D- und C-Jugend (gemeinsam)' } elseif ($who -eq 'X') { 'C-/D-Jugend' } else { "$who-Jugend" }
  $desc = @("Training $label", "$full $t1 - $t2 Uhr", "Ort: $($Training.place)")
  if ($who -eq 'X') { $desc += 'Welche Jugend an diesem Tag trainiert, steht im WhatsApp-Channel der Mannschaft.' }
  if ($tWhere) { $desc += "Halle: $tWhere" }
  if ($tMaps) { $desc += "Route: $tMaps" }
  $desc += "Alle Infos: $AppUrl"
  $lines = @('BEGIN:VEVENT', "UID:training-$short-$who@hcvg-eltern-app", "DTSTAMP:$stamp",
    "DTSTART;TZID=Europe/Berlin:$($s.ToString("yyyyMMdd'T'HHmmss"))",
    "DTEND;TZID=Europe/Berlin:$($e.ToString("yyyyMMdd'T'HHmmss"))",
    "RRULE:FREQ=WEEKLY;BYDAY=$($byDay[$short]);UNTIL=$($tUntil.ToString('yyyyMMdd'))T225959Z",
    "SUMMARY:$(IcsText "Training $label")")
  if ($tWhere) { $lines += "LOCATION:$(IcsText $tWhere)" }
  $lines += "DESCRIPTION:$(IcsText ($desc -join "`n"))"
  if ($tMaps) { $lines += "URL:$tMaps" }
  $lines += 'END:VEVENT'
  $ev = ($lines | ForEach-Object { IcsFold $_ }) -join "`r`n"
  $tEvents['CD'] += , $ev
  if ($who -match 'C|X') { $tEvents['C'] += , $ev }
  if ($who -match 'D|X') { $tEvents['D'] += , $ev }
}

$tz = @('BEGIN:VTIMEZONE', 'TZID:Europe/Berlin',
  'BEGIN:DAYLIGHT', 'TZOFFSETFROM:+0100', 'TZOFFSETTO:+0200', 'TZNAME:CEST', 'DTSTART:19700329T020000', 'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU', 'END:DAYLIGHT',
  'BEGIN:STANDARD', 'TZOFFSETFROM:+0200', 'TZOFFSETTO:+0100', 'TZNAME:CET', 'DTSTART:19701025T030000', 'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU', 'END:STANDARD',
  'END:VTIMEZONE') -join "`r`n"
function Write-Ics([string]$file, [string]$name, $evs) {
  $head = @('BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//HCVG Mannschafts-App//DE', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    "X-WR-CALNAME:$name", 'X-WR-TIMEZONE:Europe/Berlin', 'REFRESH-INTERVAL;VALUE=DURATION:PT6H', 'X-PUBLISHED-TTL:PT6H') -join "`r`n"
  $body = @($head, $tz) + $evs + @('END:VCALENDAR')
  [IO.File]::WriteAllText((Join-Path $Root $file), (($body -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}
Write-Ics 'kalender-c.ics' 'HC VG C-Jugend' ($events['C'] + $tEvents['C'])
Write-Ics 'kalender-d.ics' 'HC VG D-Jugend' ($events['D'] + $tEvents['D'])
Write-Ics 'kalender.ics'   'HC VG D- und C-Jugend' ($events['D'] + $events['C'] + $tEvents['CD'])
Write-Host "Kalender: C $($events['C'].Count), D $($events['D'].Count) Spiele, $($tEvents['CD'].Count) Trainingsserien"

$json = ConvertTo-Json -InputObject $out -Depth 10 -Compress
# Berichte als fertiges JSON einsetzen (vermeidet doppeltes Umwandeln)
$json = [regex]::Replace($json, '"@@(\d+)@@"', { param($m) (Get-Variable -Name "rep_$($m.Groups[1].Value)" -Scope Script).Value })

$js = "// Automatisch erzeugt von tools/update-data.ps1 - nicht von Hand bearbeiten.`nwindow.HCVG_DATA = $json;`n"
[IO.File]::WriteAllText($OutFile, $js, (New-Object Text.UTF8Encoding $false))
Write-Host "Fertig: $OutFile ($([Math]::Round($js.Length/1KB)) KB)"
