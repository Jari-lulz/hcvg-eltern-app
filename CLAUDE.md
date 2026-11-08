# HCVG Eltern-App

Eltern-App für die weibliche D- und C-Jugend des HC Vorpommern-Greifswald (Saison 2026/27, BHV Ost).

## Aufbau
- `index.html`: die App (HTML, CSS, JS in einer Datei, keine Build-Tools).
- `data.js`: Spieldaten, **automatisch erzeugt** von `tools/update-data.ps1`. Nicht von Hand bearbeiten.
  - `window.HCVG_DATA = { updated, leagues: { D, C }, halls }`
  - je Liga: `table`, `games`, `reports`
  - Spielzeile: `[Datum, Uhrzeit, Hallen-ID, Heim, Gast, Ergebnis, Notiz, Bericht-ID, angesetzter Schiri]`
  - Bericht (Cache `tools/cache/<id>.v2.json`): `{ ht, sr[], h, a, ev[] }`. `ev` = `[Sekunde, Seite, Code, Rückennummer]` – über die Nummer wird jedes Tor der Werferin zugeordnet (Torphasen, Halbzeiten, Steckbriefe im Gegner-Check).
- Alt: `h`/`a` = `{ p: [[Nr, Name, PersonID, Tore, 7mTore, 7mVersuche, Gelb, 2Min, Disq]], s7, g7, m2, y, d, to }`. `ev` = `[Sekunde, Seite(1 Heim/2 Gast), Code]` mit Code `g`, `7g`, `7x`, `y`, `2`, `d`, `t`.
- Von Hand gepflegt in `index.html`: `SHORT` (Kurznamen), `LEN` (Spielzeit je Liga).
- Trainingszeiten: `tools/training.json` (einzige Stelle, gilt für App und Kalender). `from`/`until` = Zeitraum der wöchentlichen Kalender-Serien. Nach Änderung: Skript laufen lassen oder einfach pushen (der Workflow läuft bei jedem Push).
- Hallen mit Adresse: `tools/halls.json` (einzige Liste). Das Skript schreibt sie als `hallInfo` nach `data.js`, die App liest sie von dort (`HALLS`). Neue Halle = Eintrag dort ergänzen.
- Kalender-Abos: `kalender.ics` (beide), `kalender-c.ics`, `kalender-d.ics`, erzeugt vom Skript bei jedem Lauf. Termin = Treff (1 Std. vor Anwurf) bis ca. 40 Min. nach Spielende, mit Halle, Adresse und Google-Maps-Link. Dazu die Trainings als wöchentliche Serientermine (C-Kalender: Di + Fr, D-Kalender: Do + Fr, beide: alle). Kachel „Spiele in deinen Kalender“ auf der Startseite (webcal-Link fürs iPhone, Google-Kalender-Link, Adresse kopieren).
- Eigenes Team: `US = "HC Vorpommern-Greifswald"`.

## Daten aktualisieren
```
powershell -ExecutionPolicy Bypass -File tools\update-data.ps1
```
- Läuft mit Windows PowerShell 5.1 und PowerShell 7.
- Genehmigte Spielberichte werden in `tools/cache/` gespeichert und nicht erneut geladen.
- Namen werden schon im Skript gekürzt („Vorname N.“), weil es um Kinder geht.
- In der App zeigt `pName()` unsere Spielerinnen nur mit erstem Vornamen („Annie Lea L.“ → „Annie“). Kommt ein Vorname in beiden Jugenden zusammen mehrfach vor, bleibt das Kürzel („Leni W.“ / „Leni G.“). Andere Teams bleiben „Vorname N.“.

## Datenquellen (nuLiga HVMV)
- wJD Bezirksoberliga: group=486919
- wJC Bezirksoberliga: group=486898
- Tabelle: `.../groupPage?championship=BHV+Ost+26%2F27&group=<id>`
- Gesamtspielplan: `...&displayTyp=vorrunde&displayDetail=meetings`
- Spielbericht: `.../groupMeetingReport?meeting=<id>&championship=...&group=<id>`
- Live-Ticker: `https://hbde-live.liga.nu/nuScoreLive/#/groups/<id>`. Wird nur verlinkt (öffnet in neuem Tab), nicht eingebettet. Die REST-API (`/nuScoreLiveRestBackend/api/1/`) erlaubt keinen Zugriff von fremden Seiten (CORS).
- handball.net (geprüft 11/2026): Vereinsseite `/club/0e22k3j` zeigt keine Teams, die API (`/api/new/...`) antwortet mit 403. Keine zusätzlichen Daten.

## Startseite
- Banner, nächstes Spiel C-Jugend, nächstes Spiel D-Jugend (Treff = 1 Stunde vor Anwurf, Countdown, Route, Live-Ticker-Link), Kuchen-Zeile und die Trainingszeiten (mit Adresse und Google-Maps-Knopf).
- Ergebnisse, Tabellen und Statistik stehen in den Reitern D-Jugend und C-Jugend.
- Gelbe Karten und Zeitstrafen sind bei Jugendspielen anonym, also nur pro Mannschaft verfügbar.

## Reiter
- Start, D-Jugend (Spiele/Statistik), C-Jugend (Spiele/Statistik), Analyse.
- Analyse hat drei Bereiche: Unser Team, Gegner-Check, Liga. Gegner-Check und Liga lassen sich mit `FEATURE_GEGNER` / `FEATURE_LIGA = false` in `index.html` wieder ausblenden (dann verschwindet auch der Knopf „Gegner-Check“ auf den Spielkarten).
- Gegner-Check (`viewOpponent`): nächster echter Gegner je Jugend. Zahlenvergleich, Schlüsselspielerinnen (Anteil an den Toren), 7m-Schützin, automatische Hinweise („Worauf achten?“), direkter Vergleich und gemeinsame Gegner.
- Liga (`viewLigaAna`): meiste Tore, bester Schnitt, sicherste 7m, Schlüsselspielerin je Team, Auffälligkeiten. Filter „Nur HC VG“.
- Unser Team (`analyse(k)` in `index.html`): feste Regeln, keine Live-KI. Vergleicht HC VG mit der Liga (Angriff, Abwehr, 7m, Strafen, Halbzeiten, erste/letzte 10 Minuten, Torverteilung, enge Spiele) und leitet daraus Stärken, Baustellen und bis zu 3 Trainingsschwerpunkte ab. Nur Mannschaftsebene, keine Kritik an einzelnen Kindern.

## Kuchen-Regel (Startseite)
- Wer in einem Spiel das 30. Mannschaftstor für uns wirft, bringt zum nächsten Training Kuchen mit.
- Die Werferin steht nicht im nuLiga-Bericht. `Get-Scorer30` im Skript liest sie aus der nuScore-Ereignisliste (`.../nuScoreLiveRestBackend/api/1/events/<Bericht-ID>`, Code 4 = Tor, 5 = 7m-Tor, mit Spielstand und Name). Ergebnis: `leagues[k].cake = { Bericht-ID: "Vorname N." }`, zwischengespeichert in `tools/cache/cake-<id>.txt`.
- Startseite (`cakeTile()`): immer eine kleine Zeile „Kuchen-Alarm · nächster Kuchen“. Gelb mit Namen, wenn im letzten Spiel einer Jugend das 30. Tor fiel und das Spiel höchstens 10 Tage her ist (`CAKE_FRESH_DAYS`), höchstens D und C zusammen. Sonst „Noch frei!“ mit einem wöchentlich wechselnden Spruch (`CAKE_EMPTY`).
- Statistik je Jugend: „Kuchen-Chronik“ mit allen bisherigen 30. Toren.

## Bilder
- `img/logo.webp` (Vereinswappen, Kopf + Favicon), `img/team-kreis.jpg` (Mannschaftskreis von oben, kaum Gesichter; Banner auf der Startseite, auf 900px verkleinert).
- Repo und Seite sind öffentlich: Fotos mit erkennbaren Kindergesichtern nur mit Einverständnis der Eltern einbauen. Seite hat `noindex`.
- Der Workflow kopiert `img/` mit nach `_site`.

## Design
- Farben als CSS-Tokens in `:root`, Hell- und Dunkelmodus.
- Schriften: Barlow Condensed (Überschriften), Figtree (Text).
- Mobil zuerst: muss bei ~375px Breite sauber aussehen.

## Ideen für später
- Torjubel-Animation mit Comic-Avataren statt echter Kinderfotos (DSGVO)
