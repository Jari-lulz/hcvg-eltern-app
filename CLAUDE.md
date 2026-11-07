# HCVG Eltern-App

Eltern-App für die weibliche D- und C-Jugend des HC Vorpommern-Greifswald (Saison 2026/27, BHV Ost).

## Aufbau
- `index.html`: die App (HTML, CSS, JS in einer Datei, keine Build-Tools).
- `data.js`: Spieldaten, **automatisch erzeugt** von `tools/update-data.ps1`. Nicht von Hand bearbeiten.
  - `window.HCVG_DATA = { updated, leagues: { D, C }, halls }`
  - je Liga: `table`, `games`, `reports`
  - Spielzeile: `[Datum, Uhrzeit, Hallen-ID, Heim, Gast, Ergebnis, Notiz, Bericht-ID, angesetzter Schiri]`
  - Bericht: `{ ht, sr[], h, a, ev[] }`. `h`/`a` = `{ p: [[Nr, Name, PersonID, Tore, 7mTore, 7mVersuche, Gelb, 2Min, Disq]], s7, g7, m2, y, d, to }`. `ev` = `[Sekunde, Seite(1 Heim/2 Gast), Code]` mit Code `g`, `7g`, `7x`, `y`, `2`, `d`, `t`.
- Von Hand gepflegt in `index.html`: `TRAINING` (Trainingszeiten), `HALLS` (Adressen), `SHORT` (Kurznamen), `LEN` (Spielzeit je Liga).
- Eigenes Team: `US = "HC Vorpommern-Greifswald"`.

## Daten aktualisieren
```
powershell -ExecutionPolicy Bypass -File tools\update-data.ps1
```
- Läuft mit Windows PowerShell 5.1 und PowerShell 7.
- Genehmigte Spielberichte werden in `tools/cache/` gespeichert und nicht erneut geladen.
- Namen werden schon im Skript gekürzt („Vorname N.“), weil es um Kinder geht.

## Datenquellen (nuLiga HVMV)
- wJD Bezirksoberliga: group=486919
- wJC Bezirksoberliga: group=486898
- Tabelle: `.../groupPage?championship=BHV+Ost+26%2F27&group=<id>`
- Gesamtspielplan: `...&displayTyp=vorrunde&displayDetail=meetings`
- Spielbericht: `.../groupMeetingReport?meeting=<id>&championship=...&group=<id>`
- Live-Ticker: `https://hbde-live.liga.nu/nuScoreLive/#/groups/<id>`. Wird nur verlinkt (öffnet in neuem Tab), nicht eingebettet. Die REST-API (`/nuScoreLiveRestBackend/api/1/`) erlaubt keinen Zugriff von fremden Seiten (CORS).
- handball.net (geprüft 11/2026): Vereinsseite `/club/0e22k3j` zeigt keine Teams, die API (`/api/new/...`) antwortet mit 403. Keine zusätzlichen Daten.

## Startseite
- Nur: nächstes Spiel C-Jugend, nächstes Spiel D-Jugend (Treff = 1 Stunde vor Anwurf, Countdown, Route, Live-Ticker-Link) und die Trainingszeiten (ohne Adresse/Route, die Halle kennen alle).
- Ergebnisse, Tabellen und Statistik stehen in den Reitern D-Jugend und C-Jugend.
- Gelbe Karten und Zeitstrafen sind bei Jugendspielen anonym, also nur pro Mannschaft verfügbar.

## Design
- Farben als CSS-Tokens in `:root`, Hell- und Dunkelmodus.
- Schriften: Barlow Condensed (Überschriften), Figtree (Text).
- Mobil zuerst: muss bei ~375px Breite sauber aussehen.

## Ideen für später
- Trainings-Uhrzeiten eintragen (kommen vom Trainer)
- Torjubel-Animation mit Comic-Avataren statt echter Kinderfotos (DSGVO)
