-- Einzugscan.app – grafische Oberfläche für einzugscan.sh
-- Wird von install.sh mit osacompile zu einer App gebaut.

property configPath : "~/.config/einzugscan.conf"

on readSetting(keyName, defaultValue)
	try
		set v to do shell script "f=" & configPath & "; [ -f \"$f\" ] && sed -n 's/^" & keyName & "=\"\\{0,1\\}\\([^\"]*\\)\"\\{0,1\\}$/\\1/p' \"$f\" | tail -n 1"
		if v is not "" then return v
	end try
	return defaultValue
end readSetting

on run
	set scriptPath to quoted form of (POSIX path of (path to me) & "Contents/Resources/einzugscan.sh")

	-- 1. Scanner ermitteln (gespeichert oder per Bonjour suchen)
	set scanner to readSetting("SCANNER", "")
	if scanner is "" then
		try
			set scanner to do shell script scriptPath & " --discover --save 2>/dev/null"
		on error
			set scanner to ""
		end try
		if scanner is "" then
			set dlg to display dialog "Der Scanner wurde im Netzwerk nicht automatisch gefunden." & return & return & "Bitte die IP-Adresse des Brother MFC-L2710DW eingeben" & return & "(am Gerät: Menü > Netzwerk > WLAN > TCP/IP > IP-Adresse):" default answer "192.168." with title "Einzugscan" buttons {"Abbrechen", "OK"} default button 2 cancel button 1
			set scanner to text returned of dlg
			do shell script scriptPath & " --gui --scanner " & quoted form of scanner & " --save --status"
		end if
	end if

	-- 2. Optionen abfragen
	set modeChoice to choose from list {"Schwarzweiß/Graustufen – einseitig", "Schwarzweiß/Graustufen – beidseitig (Stapel wenden)", "Farbe – einseitig", "Farbe – beidseitig (Stapel wenden)"} with title "Einzugscan" with prompt "Dokumente mit der Schrift nach OBEN in den Einzug legen." & return & "Scanner: " & scanner default items {"Schwarzweiß/Graustufen – einseitig"} OK button name "Weiter" cancel button name "Abbrechen"
	if modeChoice is false then return
	set modeChoice to item 1 of modeChoice

	set resChoice to choose from list {"150 dpi (klein)", "300 dpi (Standard)", "600 dpi (sehr fein, langsam)"} with title "Einzugscan" with prompt "Auflösung:" default items {"300 dpi (Standard)"} OK button name "Weiter" cancel button name "Abbrechen"
	if resChoice is false then return
	set resChoice to item 1 of resChoice

	set args to ""
	if modeChoice starts with "Farbe" then
		set args to args & " --mode farbe"
	else
		set args to args & " --mode grau"
	end if
	if modeChoice contains "beidseitig" then set args to args & " --duplex"
	set args to args & " --resolution " & (word 1 of resChoice)

	-- 3. Speicherort
	set defaultName to "Scan " & (do shell script "date +%Y-%m-%d_%H-%M") & ".pdf"
	set outFile to choose file name with prompt "PDF speichern unter:" default name defaultName default location (path to desktop folder)
	set outPath to POSIX path of outFile
	if outPath does not end with ".pdf" then set outPath to outPath & ".pdf"

	-- 4. Scannen
	try
		do shell script scriptPath & " --gui --open --scanner " & quoted form of scanner & args & " --output " & quoted form of outPath & " 2>/dev/null"
	on error
		-- Fehlermeldungen zeigt einzugscan.sh (--gui) bereits selbst als Dialog an
	end try
end run
