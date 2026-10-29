# SmartPlane Pro — Installation und erster Test

Diese Version ist eine **Research Preview**. Die Pro-spezifische Steuerung ist
noch nicht bestätigt. Das Bluetooth-Labor funktioniert unabhängig davon, ob ein
bekanntes Steuerprofil gefunden wird.

## IPA herunterladen

1. Im Repository **Actions → Build iOS IPA** öffnen.
2. Einen grünen Lauf auswählen.
3. Unter **Artifacts** das Paket `SmartPlanePro-1.0.0-unsigned-IPA` herunterladen
   und das ZIP entpacken.
4. `SmartPlanePro-1.0.0-unsigned.ipa` mit deinem eigenen Signierdienst signieren,
   z. B. über deinen bestehenden Feather-/Signulous-Workflow. Die IPA enthält
   absichtlich kein Apple-Zertifikat und kein Provisioning Profile.
5. Die signierte IPA installieren und Bluetooth erlauben. Mindestversion iOS 18;
   echtes Liquid Glass ab iOS 26. Aktuelle iPhones und iPads werden unterstützt.

## Ohne Flugzeug ausprobieren

**Hangar → Cockpit im Trainingsmodus ansehen → Freigeben**. Dieser Modus sendet
keine Bluetooth-Befehle. Steuerung: linken Schubregler gedrückt halten, rechts
Ruder ziehen oder Neigen auswählen und bei ruhigem Telefon den Neutralpunkt setzen.

## Dein SmartPlane Pro untersuchen

1. Vor dem ersten Motortest **Propeller entfernen**. Akku einsetzen, iPhone nahe
   ans Flugzeug halten.
2. **Verbinden → 20 Sekunden suchen**. Falls nötig **Alle BLE-Geräte anzeigen**.
3. Gewünschtes Gerät öffnen und verbinden.
4. **Bluetooth-Labor → Alle lesbaren Werte abfragen**.
5. Dienste öffnen, gegebenenfalls Benachrichtigungen aktivieren.
6. **Aktuellen Diagnosebericht erstellen → Diagnosebericht teilen** und die
   JSON-Datei hier im Chat schicken. Nach weiteren Messungen neu erstellen.

Das Labor zeigt Firmware-Version, Modell und Hersteller, wenn das Flugzeug diese
GATT-Werte veröffentlicht. Es liest nicht die gesamte Firmware aus.

## Wenn ein Profil gefunden wird

Ein passendes UUID-Schema ist noch kein bestätigter Pro-Treiber. Zuerst ohne
Propeller Nullschub, Ruder-Richtung und STOP überprüfen. Das Cockpit setzt beide
Ausgänge bis zur manuellen Freigabe auf null und begrenzt den Schub standardmäßig
auf 50 %. Schub wirkt nur, solange der Regler gedrückt bleibt. Ruder zentriert
beim Loslassen. Einstellungen erlauben andere Schubgrenzen.

STOP fordert Nullwerte an. Bei Funkverlust kann die App die physische Abschaltung
nicht garantieren. Beim Verlassen der App wird ein Stopp versucht und danach die
Verbindung getrennt. Es gibt keine automatische Wiederfreigabe.

Pro-Stunts, Helicopter/Plane-Modus und Firmware-Updates sind ohne belegte Befehle
noch nicht implementiert. Das ist ausdrücklich keine vollständige Pro-App.

## Eigene Profile

Einstellungen → JSON-Steuerprofil importieren. Format und Grenzen siehe
`docs/control-profile-example.json`. Das Beispiel ist das veröffentlichte ältere
SmartLink-Protokoll mit einer eigenen ID, **kein neuer Pro-Treiber**. Profile
bleiben lokal. Die Expertenkonsole schreibt nur nach einzelner Bestätigung.
