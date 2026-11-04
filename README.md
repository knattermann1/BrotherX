# Einzugscan – Vorlageneinzug (ADF) des Brother MFC-L2710DW am Mac nutzen

Mit diesem Programm scannst du mehrseitige Dokumente über den **automatischen
Vorlageneinzug** des Brother MFC-L2710DW in **eine PDF-Datei**. Es funktioniert
auch dann, wenn die App „Digitale Bilder“ (Image Capture) den Einzug nicht anbietet.

Das Programm spricht den Scanner direkt über das Netzwerkprotokoll **AirScan/eSCL**
an. Diese Bordmittel von macOS reichen aus: `curl` und `osascript` mit PDFKit.
Treiber oder Zusatzsoftware brauchst du nicht.

## Voraussetzungen

* Der Drucker ist per **WLAN oder LAN** im selben Netzwerk wie der Mac.
  Über USB funktioniert es nicht.
* macOS 10.13 oder neuer

## Installation

1. Repository herunterladen: grüner Button „Code“ → „Download ZIP“ → entpacken.
2. Das **Terminal** öffnen und in den Ordner wechseln, zum Beispiel:
   ```bash
   cd ~/Downloads/brotherx-master
   ./install.sh
   ```
3. Danach findest du **Einzugscan** in `~/Applications` (Benutzerordner →
   Programme). Du kannst die App ins Dock ziehen.

Beim ersten Start fragt macOS eventuell, ob Einzugscan auf Geräte im
**lokalen Netzwerk** zugreifen darf. Bestätige das mit **Erlauben**.

## Benutzung (App)

1. Blätter mit der **Schrift nach oben** in den Einzug legen.
2. Einzugscan starten.
3. Farbe oder Graustufen wählen, einseitig oder beidseitig, dann die Auflösung.
4. Den Speicherort wählen. Danach scannt der Drucker alle Blätter, und die fertige
   PDF öffnet sich in der Vorschau.

Beim ersten Start sucht das Programm den Scanner automatisch per Bonjour. Klappt
das nicht, fragt es nach der IP-Adresse. Du findest sie am Gerät unter
**Menü → Netzwerk → WLAN → TCP/IP → IP-Adresse**. Die Adresse wird in
`~/.config/einzugscan.conf` gespeichert.

### Beidseitig scannen

Der Einzug des MFC-L2710DW scannt nur eine Seite pro Blatt. Mit der Option
„beidseitig (Stapel wenden)“ geht es trotzdem:

1. Zuerst werden alle Vorderseiten gescannt.
2. Dann den ausgegebenen Stapel **als Ganzes umdrehen**, ohne ihn neu zu
   sortieren, und wieder einlegen.
3. Die Rückseiten werden gescannt und automatisch richtig einsortiert
   (Seite 1 vorne, Seite 1 hinten, Seite 2 vorne, …).

## Benutzung im Terminal

```bash
einzugscan                         # Standard: 300 dpi, Farbe, A4 → PDF auf dem Schreibtisch
einzugscan -m grau -r 200 -o ~/Documents/Rechnung.pdf --open
einzugscan -d                      # beidseitig (Stapel wenden)
einzugscan -s 192.168.1.50 --save  # Scanner-IP festlegen und speichern
einzugscan --discover              # Scanner im Netzwerk suchen
einzugscan --status                # Ist Papier im Einzug?
einzugscan --help                  # alle Optionen
```

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| „Kein AirScan-Scanner gefunden“ | IP-Adresse mit `-s` angeben bzw. in der App eintragen. Mac und Drucker müssen im selben Netz sein. |
| „Scanner ist nicht erreichbar“ | Drucker eingeschaltet? IP geändert? Am besten im Router eine feste IP für den Drucker vergeben. Danach `einzugscan -s NEUE-IP --save`. |
| „Der Vorlageneinzug ist leer“ | Papier bis zum Anschlag einschieben, Schrift nach oben. |
| HTTP-Fehler beim Auftrag | In der Weboberfläche des Druckers (`http://IP-Adresse`) prüfen, ob unter *Netzwerk → Protokoll* „AirPrint“ bzw. „eSCL“ aktiviert ist. Eventuell `--https` probieren. |
| Keine Netzwerkfreigabe | Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk → Einzugscan aktivieren. |

## Alternative

Brother bietet auch die kostenlose App **„Brother iPrint&Scan“** im Mac App Store
an. Sie unterstützt den Einzug ebenfalls, falls du lieber die offizielle Software
nutzen möchtest.

## Dateien

* `einzugscan.sh` – das eigentliche Programm (Kommandozeile)
* `app/Einzugscan.applescript` – grafische Oberfläche, wird von `install.sh` zur App gebaut
* `install.sh` – baut und installiert die App
* `tests/mock_escl.py` – simulierter Scanner zum Testen ohne Hardware
