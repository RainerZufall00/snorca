# Snarwal – Kurzanleitung

## 1. Drucker verbinden

1. Tab **Drucker** öffnen.
2. Snarwal sucht den U1 automatisch im WLAN (Abschnitt „Im Netzwerk gefunden“) – antippen.
   Findet er nichts: IP-Adresse eintragen (steht am Touchscreen des U1 unter Einstellungen → WLAN).
3. Für unterwegs: Tailscale (oder ein anderes VPN) auf iPhone und im Heimnetz einrichten und die
   VPN-Adresse des U1 eintragen.

Mit der **Extended-Firmware (paxx12)** gibt es Live-Video; mit der Original-Firmware ein Standbild,
das sich alle zwei Sekunden aktualisiert.

## 2. Modell öffnen

- Tab **Slicen** → **Modell öffnen** (Dateien-App), oder
- in Safari/Printables/MakerWorld eine STL/3MF laden → **Teilen** → **Snarwal**.

3MF-Projekte aus Orca/Snapmaker Orca behalten Position und Kopfzuordnung. Mehrfarbig *bemalte*
Modelle werden (noch) einfarbig gedruckt.

## 3. Platte einrichten

- **Objekt antippen** (in der 3D-Ansicht oder in der Leiste darunter) wählt es aus.
- **Farbpunkt** an einem Objekt: Kopf T1–T4 wählen.
- Werkzeuge: **Drehen** (90°), **Skalieren**, **Flachlegen**, **Anordnen**, **Objekt** → Duplizieren/Entfernen.
- Ansicht: mit einem Finger drehen, mit zwei Fingern zoomen/verschieben.

Gelbe Hinweise erklären, was noch nicht passt (außerhalb des Betts, gemischte Materialien).
In Version 1 müssen alle verwendeten Köpfe dasselbe Material haben (z. B. 4× PLA in verschiedenen Farben).

## 4. Einstellungen

**Fein / Normal / Schnell** wählt die Schichthöhe (0,12 / 0,20 / 0,28 mm).
Unter **Einstellungen**: Infill, Stützen, Brim. Ist der Drucker verbunden, zeigt Snarwal das per
RFID erkannte Filament je Kopf; sonst stellst du Material und Farbe pro Kopf selbst ein.

## 5. Slicen und drucken

1. **Slicen** – dauert je nach Modell Sekunden bis Minuten, alles läuft offline auf dem Gerät.
2. **Vorschau**: Schicht-Regler, Druckzeit, Filament pro Kopf. Über **G-Code teilen** lässt sich
   die Datei auch speichern.
3. **An U1 senden** → Snarwal vergleicht geplante Köpfe mit dem Filament im Drucker →
   **Drucken** (startet sofort) oder **Nur hochladen**.

## 6. Druck überwachen

Tab **Drucker**: Kamera, Fortschritt, Schicht, Restzeit, aktiver Kopf, **Pause/Fortsetzen**,
**Abbrechen** (mit Rückfrage), **Licht**, Temperaturen aller Köpfe und Bauteillüfter.

## Sicherheit

- Snarwal verweigert G-Code, der das Druckbett verlassen würde.
- Start-/Wechsel-/End-Sequenz rufen dieselben Firmware-Makros in derselben Reihenfolge auf wie
  Snapmaker Orca (siehe `docs/DESIGN.md`, Testplan Schritt 1).
- Trotzdem: die ersten Drucke (vor allem mit mehreren Köpfen) **am Drucker beobachten**.
