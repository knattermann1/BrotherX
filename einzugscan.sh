#!/bin/bash
# =============================================================================
#  einzugscan.sh – Mehrseitiges Scannen über den automatischen Vorlageneinzug
#  (ADF) eines Brother MFC-L2710DW (und anderer AirScan/eSCL-Scanner) am Mac.
#
#  Benötigt nur Bordmittel von macOS: bash, curl, osascript (PDFKit).
#  Kompatibel mit dem bash 3.2 von macOS.
# =============================================================================

set -u

VERSION="1.0"
CONFIG_FILE="${EINZUGSCAN_CONFIG:-$HOME/.config/einzugscan.conf}"

# ---- Standardwerte ----------------------------------------------------------
SCANNER=""            # host[:port]   z.B. 192.168.1.50
ESCL_PATH="eSCL"
SCHEME="http"
OUTPUT=""
RESOLUTION=300
MODE="farbe"          # farbe | grau
PAPER="a4"            # a4 | letter | legal
DUPLEX=0              # manueller Duplex (Stapel wenden)
REVERSE_BACKS=1       # Rückseiten kommen nach dem Wenden in umgekehrter Reihenfolge
GUI=0                 # Rückfragen/Fehler als macOS-Dialog
OPEN_AFTER=0
KEEP_IMAGES=0
NO_MERGE=0
ACTION="scan"         # scan | discover | status

# Konfiguration laden (SCANNER=..., RESOLUTION=..., MODE=..., PAPER=...)
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

# ---- Hilfsfunktionen --------------------------------------------------------
usage() {
    cat <<EOF
einzugscan $VERSION – Scannen über den Vorlageneinzug (ADF) per AirScan/eSCL

Benutzung:
  einzugscan.sh [Optionen]            Einzug scannen und als PDF speichern
  einzugscan.sh --discover            Scanner im Netzwerk suchen
  einzugscan.sh --status              Scannerstatus (Einzug belegt?) anzeigen

Optionen:
  -s, --scanner HOST[:PORT]  IP-Adresse/Hostname des Scanners
                             (Standard: aus $CONFIG_FILE oder automatische Suche)
  -o, --output DATEI.pdf     Zieldatei (Standard: ~/Desktop/Scan_JJJJ-MM-TT_hh-mm-ss.pdf)
  -r, --resolution DPI       100 | 150 | 200 | 300 | 600   (Standard: $RESOLUTION)
  -m, --mode MODUS           farbe | grau                  (Standard: $MODE)
  -p, --paper FORMAT         a4 | letter | legal           (Standard: $PAPER)
  -d, --duplex               Manueller Duplex: erst Vorderseiten, dann Stapel
                             wenden und Rückseiten scannen – wird automatisch sortiert
      --no-reverse           Rückseiten beim Duplex NICHT umkehren
      --https                HTTPS statt HTTP verwenden
      --open                 PDF danach in Vorschau öffnen
      --keep-images          Einzelne JPEG-Seiten zusätzlich behalten
      --save                 Gewählten Scanner in der Konfiguration speichern
      --gui                  Rückfragen und Meldungen als Dialogfenster
  -h, --help                 Diese Hilfe
EOF
}

die() {
    if [ "$GUI" = 1 ] && command -v osascript >/dev/null 2>&1; then
        osascript -e 'on run argv
            display dialog (item 1 of argv) with title "Einzugscan" buttons {"OK"} default button 1 with icon stop
        end run' "$1" >/dev/null 2>&1
    fi
    echo "Fehler: $1" >&2
    exit 1
}

info() { echo "$@" >&2; }

notify() {
    if command -v osascript >/dev/null 2>&1; then
        osascript -e 'on run argv
            display notification (item 1 of argv) with title "Einzugscan"
        end run' "$1" >/dev/null 2>&1 || true
    fi
}

# Wartet auf Bestätigung durch den Benutzer (Terminal oder Dialog).
confirm() {
    local msg="$1"
    if [ "$GUI" = 1 ]; then
        osascript -e 'on run argv
            display dialog (item 1 of argv) with title "Einzugscan" buttons {"Abbrechen", "Weiter"} default button 2 cancel button 1 with icon note
        end run' "$msg" >/dev/null 2>&1 || return 1
    else
        printf '%s\n[Enter] = weiter, Strg+C = abbrechen ' "$msg" >&2
        read -r _ </dev/tty || return 1
    fi
    return 0
}

# Extrahiert den Inhalt des ersten XML-Elements mit dem lokalen Namen $2 aus $1.
xml_value() {
    printf '%s' "$1" | tr -d '\r\n' | sed -n "s/.*<\([A-Za-z]*:\)\{0,1\}$2>\([^<]*\)<\/\([A-Za-z]*:\)\{0,1\}$2>.*/\2/p" | head -n 1
}

base_url() { printf '%s://%s/%s' "$SCHEME" "$SCANNER" "$ESCL_PATH"; }

CURL_OPTS="-sS --connect-timeout 5"

# ---- Scanner-Suche per Bonjour (dns-sd) -------------------------------------
# Gibt "host:port" aus.
discover() {
    command -v dns-sd >/dev/null 2>&1 || return 1
    local tmp name resolved hostport
    tmp=$(mktemp -t einzugscan.XXXXXX) || return 1

    dns-sd -B _uscan._tcp local. >"$tmp" 2>/dev/null &
    local pid=$!
    sleep 3; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

    # Zeilenformat: Timestamp A/R Flags if Domain ServiceType InstanceName
    name=$(awk '$2=="Add" { for (i=7;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""; }' "$tmp" \
           | grep -i -m1 'brother' )
    [ -z "$name" ] && name=$(awk '$2=="Add" { for (i=7;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""; exit }' "$tmp")
    if [ -z "$name" ]; then rm -f "$tmp"; return 1; fi
    info "Gefunden: $name"

    dns-sd -L "$name" _uscan._tcp local. >"$tmp" 2>/dev/null &
    pid=$!
    sleep 3; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

    hostport=$(sed -n 's/.*can be reached at \([^ ]*\).*/\1/p' "$tmp" | head -n 1)
    resolved=$(grep -o 'rs=[^ ]*' "$tmp" | head -n 1 | sed 's/^rs=//')
    rm -f "$tmp"
    [ -z "$hostport" ] && return 1
    # "BRN123.local.:80" -> "BRN123.local:80"
    hostport=$(printf '%s' "$hostport" | sed 's/\.:/:/; s/\.$//')
    [ -n "$resolved" ] && ESCL_PATH="$resolved"
    printf '%s\n' "$hostport"
}

ensure_scanner() {
    if [ -z "$SCANNER" ]; then
        info "Kein Scanner angegeben – suche im Netzwerk …"
        SCANNER=$(discover) || SCANNER=""
        [ -z "$SCANNER" ] && die "Kein AirScan-Scanner gefunden. Bitte IP-Adresse mit -s angeben (steht im Druckermenü unter Netzwerk > WLAN > TCP/IP > IP-Adresse)."
        info "Verwende Scanner: $SCANNER"
    fi
}

save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    {
        echo "# Einstellungen für einzugscan.sh"
        echo "SCANNER=\"$SCANNER\""
        echo "ESCL_PATH=\"$ESCL_PATH\""
        echo "SCHEME=\"$SCHEME\""
        echo "RESOLUTION=\"$RESOLUTION\""
        echo "MODE=\"$MODE\""
        echo "PAPER=\"$PAPER\""
    } >"$CONFIG_FILE"
    info "Einstellungen gespeichert in $CONFIG_FILE"
}

# ---- eSCL -------------------------------------------------------------------
get_status() {
    # shellcheck disable=SC2086
    curl $CURL_OPTS --max-time 10 "$(base_url)/ScannerStatus"
}

get_caps() {
    # shellcheck disable=SC2086
    curl $CURL_OPTS --max-time 10 "$(base_url)/ScannerCapabilities"
}

scan_settings_xml() {
    local version="$1" width height color
    case "$PAPER" in
        a4)     width=2480; height=3508 ;;   # 210 x 297 mm in 1/300 Zoll
        letter) width=2550; height=3300 ;;
        legal)  width=2550; height=4200 ;;
        *) die "Unbekanntes Papierformat: $PAPER" ;;
    esac
    case "$MODE" in
        farbe|color|colour) color="RGB24" ;;
        grau|gray|grey|sw)  color="Grayscale8" ;;
        *) die "Unbekannter Farbmodus: $MODE" ;;
    esac
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
  <pwg:Version>$version</pwg:Version>
  <scan:Intent>Document</scan:Intent>
  <pwg:ScanRegions>
    <pwg:ScanRegion>
      <pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits>
      <pwg:XOffset>0</pwg:XOffset>
      <pwg:YOffset>0</pwg:YOffset>
      <pwg:Width>$width</pwg:Width>
      <pwg:Height>$height</pwg:Height>
    </pwg:ScanRegion>
  </pwg:ScanRegions>
  <pwg:InputSource>Feeder</pwg:InputSource>
  <scan:ColorMode>$color</scan:ColorMode>
  <scan:XResolution>$RESOLUTION</scan:XResolution>
  <scan:YResolution>$RESOLUTION</scan:YResolution>
  <pwg:DocumentFormat>image/jpeg</pwg:DocumentFormat>
  <scan:DocumentFormatExt>image/jpeg</scan:DocumentFormatExt>
</scan:ScanSettings>
EOF
}

check_adf_loaded() {
    local status state adf
    status=$(get_status) || die "Scanner $SCANNER ist nicht erreichbar ($(base_url)). Ist er eingeschaltet und im selben Netzwerk?"
    state=$(xml_value "$status" State)
    adf=$(xml_value "$status" AdfState)
    [ "$state" = "Processing" ] && die "Der Scanner ist gerade beschäftigt. Bitte kurz warten und erneut versuchen."
    case "$adf" in
        ScannerAdfEmpty) return 1 ;;
        ScannerAdfJam)   die "Papierstau im Vorlageneinzug." ;;
        ScannerAdfHatchOpen) die "Die Abdeckung des Vorlageneinzugs ist offen." ;;
    esac
    return 0
}

# Scannt alle Blätter im Einzug in das Verzeichnis $1 mit Präfix $2.
# Gibt die Anzahl gescannter Seiten aus.
scan_batch() {
    local dir="$1" prefix="$2" caps version settings hdr code location job_url page=0 tries

    if ! check_adf_loaded; then
        die "Der Vorlageneinzug ist leer. Bitte Blätter mit der Schrift nach OBEN einlegen."
    fi

    caps=$(get_caps) || die "Scannerfähigkeiten konnten nicht gelesen werden."
    printf '%s' "$caps" | grep -q 'Adf' || die "Der Scanner meldet keinen Vorlageneinzug (ADF)."
    version=$(xml_value "$caps" Version)
    [ -z "$version" ] && version="2.0"

    settings="$dir/settings.xml"
    scan_settings_xml "$version" >"$settings"
    hdr="$dir/headers.txt"

    # shellcheck disable=SC2086
    code=$(curl $CURL_OPTS --max-time 30 -o "$dir/post_body.txt" -D "$hdr" -w '%{http_code}' \
            -H 'Content-Type: text/xml' --data-binary @"$settings" "$(base_url)/ScanJobs") \
        || die "Scanauftrag konnte nicht gesendet werden."
    case "$code" in
        201|200) ;;
        409|503) die "Scanner ist belegt (HTTP $code). Bitte erneut versuchen." ;;
        *) die "Scanner hat den Auftrag abgelehnt (HTTP $code)." ;;
    esac

    location=$(tr -d '\r' <"$hdr" | sed -n 's/^[Ll]ocation: *//p' | tail -n 1)
    [ -z "$location" ] && die "Scanner hat keine Job-Adresse geliefert."
    case "$location" in
        http://*|https://*) job_url="$location" ;;
        /*) job_url="$SCHEME://$SCANNER$location" ;;
        *)  job_url="$(base_url)/$location" ;;
    esac
    job_url="${job_url%/}"

    while :; do
        local file
        file=$(printf '%s/%s_%03d.jpg' "$dir" "$prefix" $((page + 1)))
        tries=0
        while :; do
            # shellcheck disable=SC2086
            code=$(curl $CURL_OPTS --max-time 180 -o "$file" -w '%{http_code}' "$job_url/NextDocument") || code="000"
            if [ "$code" = "503" ] && [ $tries -lt 30 ]; then
                tries=$((tries + 1)); sleep 1; continue
            fi
            break
        done
        case "$code" in
            200)
                if [ ! -s "$file" ]; then rm -f "$file"; break; fi
                page=$((page + 1))
                info "  Seite $page gescannt"
                ;;
            404|410)
                rm -f "$file"; break ;;
            *)
                rm -f "$file"
                # shellcheck disable=SC2086
                curl $CURL_OPTS --max-time 10 -X DELETE "$job_url" >/dev/null 2>&1
                [ $page -gt 0 ] && { info "Warnung: Abbruch nach $page Seiten (HTTP $code)."; break; }
                die "Fehler beim Abholen der Seite (HTTP $code). Papierstau?"
                ;;
        esac
    done
    echo "$page"
}

# ---- PDF erzeugen (PDFKit via JavaScript for Automation) -------------------
merge_pdf() {
    local out="$1"; shift
    command -v osascript >/dev/null 2>&1 || return 2
    osascript -l JavaScript - "$out" "$RESOLUTION" "$@" <<'JXA'
ObjC.import('Foundation');
ObjC.import('AppKit');
ObjC.import('Quartz');
function run(argv) {
    var out = argv[0];
    var dpi = parseFloat(argv[1]);
    var doc = $.PDFDocument.alloc.init;
    for (var i = 2; i < argv.length; i++) {
        var img = $.NSImage.alloc.initWithContentsOfFile(argv[i]);
        if (img.isNil()) { throw new Error('Bild nicht lesbar: ' + argv[i]); }
        var rep = img.representations.objectAtIndex(0);
        var w = rep.pixelsWide, h = rep.pixelsHigh;
        if (w > 0 && h > 0) { img.setSize($.NSMakeSize(w * 72.0 / dpi, h * 72.0 / dpi)); }
        var page = $.PDFPage.alloc.initWithImage(img);
        doc.insertPageAtIndex(page, doc.pageCount);
    }
    if (!doc.writeToFile(out)) { throw new Error('PDF konnte nicht geschrieben werden: ' + out); }
    return doc.pageCount + ' Seiten';
}
JXA
}

# ---- Argumente --------------------------------------------------------------
SAVE=0
while [ $# -gt 0 ]; do
    case "$1" in
        -s|--scanner)    SCANNER="$2"; shift ;;
        -o|--output)     OUTPUT="$2"; shift ;;
        -r|--resolution) RESOLUTION="$2"; shift ;;
        -m|--mode)       MODE="$2"; shift ;;
        -p|--paper)      PAPER="$2"; shift ;;
        -d|--duplex)     DUPLEX=1 ;;
        --no-reverse)    REVERSE_BACKS=0 ;;
        --https)         SCHEME="https"; CURL_OPTS="$CURL_OPTS -k" ;;
        --open)          OPEN_AFTER=1 ;;
        --keep-images)   KEEP_IMAGES=1 ;;
        --no-merge)      NO_MERGE=1; KEEP_IMAGES=1 ;;
        --save)          SAVE=1 ;;
        --gui)           GUI=1 ;;
        --discover)      ACTION="discover" ;;
        --status)        ACTION="status" ;;
        -h|--help)       usage; exit 0 ;;
        *) usage >&2; die "Unbekannte Option: $1" ;;
    esac
    shift
done

[ "$SCHEME" = "https" ] && case "$CURL_OPTS" in *-k*) ;; *) CURL_OPTS="$CURL_OPTS -k" ;; esac

case "$RESOLUTION" in
    100|150|200|300|600) ;;
    *) die "Ungültige Auflösung: $RESOLUTION (erlaubt: 100, 150, 200, 300, 600)" ;;
esac

# ---- Aktionen ---------------------------------------------------------------
case "$ACTION" in
    discover)
        result=$(discover) || die "Kein AirScan-Scanner im Netzwerk gefunden."
        echo "$result"
        SCANNER="$result"
        [ "$SAVE" = 1 ] && save_config
        exit 0
        ;;
    status)
        ensure_scanner
        status=$(get_status) || die "Scanner $SCANNER nicht erreichbar."
        echo "Scanner:  $SCANNER"
        echo "Zustand:  $(xml_value "$status" State)"
        adf=$(xml_value "$status" AdfState)
        case "$adf" in
            ScannerAdfLoaded) echo "Einzug:   Papier eingelegt" ;;
            ScannerAdfEmpty)  echo "Einzug:   leer" ;;
            "")               echo "Einzug:   (keine Angabe)" ;;
            *)                echo "Einzug:   $adf" ;;
        esac
        exit 0
        ;;
esac

ensure_scanner
[ "$SAVE" = 1 ] && save_config

if [ -z "$OUTPUT" ]; then
    OUTPUT="$HOME/Desktop/Scan_$(date +%Y-%m-%d_%H-%M-%S).pdf"
fi
case "$OUTPUT" in *.pdf|*.PDF) ;; *) OUTPUT="$OUTPUT.pdf" ;; esac

WORK=$(mktemp -d -t einzugscan.XXXXXX) || die "Temporäres Verzeichnis nicht anlegbar."
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

info "Scanne Vorderseiten von $SCANNER (${RESOLUTION} dpi, $MODE, $PAPER) …"
FRONTS=$(scan_batch "$WORK" front) || exit 1
[ "$FRONTS" -gt 0 ] 2>/dev/null || die "Es wurde keine Seite gescannt."

PAGES=""
if [ "$DUPLEX" = 1 ]; then
    confirm "$FRONTS Vorderseiten gescannt.

Bitte jetzt den ausgegebenen Stapel als Ganzes umdrehen (NICHT neu sortieren) und wieder in den Einzug legen." \
        || die "Abgebrochen."
    info "Scanne Rückseiten …"
    BACKS=$(scan_batch "$WORK" back) || exit 1
    if [ "$BACKS" != "$FRONTS" ]; then
        info "Warnung: $FRONTS Vorderseiten, aber $BACKS Rückseiten."
    fi
    i=1
    while [ $i -le "$FRONTS" ] || [ $i -le "$BACKS" ]; do
        f=$(printf '%s/front_%03d.jpg' "$WORK" $i)
        if [ "$REVERSE_BACKS" = 1 ]; then
            b=$(printf '%s/back_%03d.jpg' "$WORK" $((BACKS - i + 1)))
        else
            b=$(printf '%s/back_%03d.jpg' "$WORK" $i)
        fi
        [ -f "$f" ] && PAGES="$PAGES$f"$'\n'
        [ $i -le "$BACKS" ] && [ -f "$b" ] && PAGES="$PAGES$b"$'\n'
        i=$((i + 1))
    done
else
    for f in "$WORK"/front_*.jpg; do PAGES="$PAGES$f"$'\n'; done
fi

# Seitenliste in Array umwandeln (Pfade enthalten keine Zeilenumbrüche)
PAGE_LIST=()
while IFS= read -r line; do
    [ -n "$line" ] && PAGE_LIST+=("$line")
done <<EOF
$PAGES
EOF

mkdir -p "$(dirname "$OUTPUT")" || die "Zielordner nicht anlegbar."

if [ "$KEEP_IMAGES" = 1 ]; then
    imgdir="${OUTPUT%.*}_Seiten"
    mkdir -p "$imgdir"
    n=1
    for f in "${PAGE_LIST[@]}"; do
        cp "$f" "$(printf '%s/Seite_%03d.jpg' "$imgdir" $n)"; n=$((n + 1))
    done
    info "Einzelseiten gespeichert in: $imgdir"
fi

if [ "$NO_MERGE" = 1 ]; then
    echo "${OUTPUT%.*}_Seiten"
    exit 0
fi

merge_pdf "$OUTPUT" "${PAGE_LIST[@]}" >/dev/null
rc=$?
if [ $rc -eq 2 ]; then
    die "osascript nicht gefunden – PDF kann nur auf einem Mac erzeugt werden (verwende --no-merge)."
elif [ $rc -ne 0 ] || [ ! -s "$OUTPUT" ]; then
    die "PDF konnte nicht erstellt werden."
fi

info "Fertig: ${#PAGE_LIST[@]} Seiten → $OUTPUT"
notify "${#PAGE_LIST[@]} Seiten gespeichert: $(basename "$OUTPUT")"
[ "$OPEN_AFTER" = 1 ] && open "$OUTPUT"
echo "$OUTPUT"
