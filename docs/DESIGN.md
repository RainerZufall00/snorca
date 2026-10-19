# Snarwal – Design

Inoffizielle iOS-/iPadOS-App für den **Snapmaker U1**: Modelle auf dem Gerät slicen,
an den Drucker senden und Drucke überwachen. Kein Produkt von Snapmaker.

Stand: 2026-10-19, Ergebnis der Design-Session („grill-me“).

## Produkt

| Thema | Entscheidung |
|---|---|
| Name | **Snarwal** (Narwal-Icon, Stoßzahn = Düse). „Snorca“ ist schon der Community-Spitzname für Snapmaker Orca. |
| Zielgruppe | Open Source (MIT) auf GitHub, kostenlos im App Store |
| Drucker | genau **ein** Snapmaker U1 |
| Geräte | iPhone und iPad gleichwertig, **iOS/iPadOS 18+** |
| Sprachen | Deutsch und Englisch (String Catalog) |
| Priorität | **Slicen zuerst**, danach Senden und Überwachen |

## Slicing

- Engine: **[Kiri:Moto](https://github.com/GridSpace/grid-apps)** (MIT), läuft **offline auf dem Gerät**
  in einem unsichtbaren `WKWebView`. Kein Server.
- Warum nicht Orca: OrcaSlicer/Snapmaker Orca sind AGPL-3.0 → nicht mit dem App Store vereinbar,
  und der C++-Kern (Boost, TBB, CGAL, OpenVDB, OCCT, OpenCV) ist für iOS kaum portierbar.
  Die App enthält deshalb **keinen Orca-Code und keine kopierten Orca-Profile**.
- Kiri wird als Git-Submodul unter `vendor/grid-apps` auf eine feste Version gepinnt.
  Sobald eigene Patches nötig sind, zeigt das Submodul auf einen eigenen Fork. Verbesserungen werden an Kiri zurückgeschickt.
- Eigenes **U1-Profil** (`engine/profiles/snapmaker-u1.js`): Start-, Werkzeugwechsel- und End-G-Code
  rufen die Firmware-Makros des U1 auf (`PRINT_START`, `SM_PRINT_*`, Düsenreinigung, Bed-Mesh, `PRINT_END`).
- **Sicherheitsprüfung**: Die Engine verweigert G-Code, dessen Koordinaten das Druckbett (270 × 270 × 270 mm) verlassen.

### Funktionsumfang v1

- Import: **STL und 3MF** über die Dateien-App und das Teilen-Menü.
- 3MF aus Orca: Die Zuordnung von Objekt zu Kopf wird aus den Orca-Metadaten übernommen.
  Gemalte Mehrfarbmodelle werden mit Hinweis einfarbig geslict.
- Bis zu 4 Köpfe, **aber nur ein Materialtyp pro Druck** (Kiri kennt nur eine Düsentemperatur).
  Die App warnt bei gemischten Typen.
- Filament: Typ und Farbe pro Kopf werden vom U1 gelesen (`print_task_config`, RFID),
  dazu eigene, MIT-lizenzierte Standardwerte (PLA, PETG, ABS, TPU …), die man überschreiben kann.
- Einstellungen: Qualitäts-Preset (fein/normal/schnell), Infill %, Stützen an/aus (normale Stützen,
  **keine Baumstützen**), Brim an/aus.
- Druckplatte: drehen, skalieren, flachlegen, mehrere Objekte, automatisch anordnen.
- Vorschau: Schicht-Vorschau, Druckzeit und Filamentverbrauch pro Kopf.

## Drucker & Überwachung

- Verbindung über **Moonraker** (Port 7125, im LAN ohne Anmeldung).
- Einrichtung: automatische Suche per mDNS (`_snapmaker._tcp`, Hostname `U1`) oder manuelle IP bzw. manueller Hostname.
- Fernzugriff nur über ein VPN wie Tailscale, keine eigene Cloud.
- Nach dem Slicen: Upload per `POST /server/files/upload`, dann die Abfrage **„Jetzt drucken?“**
  mit Übersicht, welches Filament auf welchem Kopf liegt.
- Überwachung: Status, Fortschritt, aktiver Kopf, Pause/Fortsetzen/Abbrechen,
  Temperaturen, Licht, Lüfter.
- Kamera: mit paxx12-Extended-Firmware ein WebRTC-Livestream,
  mit Original-Firmware ein Standbild (`/server/files/camera/monitor.jpg`), das alle paar Sekunden neu geladen wird.
- **Keine Benachrichtigungen** in v1.

## Architektur

```
snarwal/
├── vendor/grid-apps/          Kiri:Moto (Submodul, gepinnt)
├── engine/                    JS-Bundle für den WKWebView
│   ├── build.mjs              baut engine/dist bzw. ios/EngineBundle
│   ├── src/snarwal-engine.js  Brücke: snarwal.loadModel(), snarwal.slice()
│   ├── profiles/              U1-Geräteprofil + Basis-Prozess
│   └── test/                  Headless-Tests (Playwright/Chromium)
├── Packages/SnarwalCore/      Swift-Logik mit Tests (läuft auch unter Linux)
│                              Geometrie, Platte, Materialien, G-Code-Vorschau,
│                              Moonraker-Client
├── ios/                       Xcode-Projekt + SwiftUI-App (siehe ios/README.md)
│   └── EngineBundle/          gebaute Engine (eingecheckt, damit Xcode ohne Node baut)
└── docs/
```

- Die App liefert `EngineBundle` aus und startet einen Mini-HTTP-Server nur auf `127.0.0.1`
  (`LocalEngineServer`). Weder `file://` noch ein eigenes URL-Schema erlauben Kiris Module-Worker zuverlässig.
- Swift ruft `callAsyncJavaScript("return await snarwal.slice(...)")` auf.
  Objekte gehen als Base64-Float32-Dreiecke in Bettkoordinaten hinein, G-Code kommt zurück.
  Den Fortschritt meldet die Engine über `webkit.messageHandlers.snarwal`.
- Der G-Code bekommt einen Orca-kompatiblen Kopf und Footer. Snapmakers Moonraker-Fork liest
  Druckzeit, Schichten und Filament sonst nur aus Prusa-/Orca-Dateien (geprüft mit dessen `metadata.py`).
- Drucker:
  - Erreichbar über HTTP auf Port 80 (nginx → Moonraker), Status per Polling von `printer/objects/query`.
  - Licht: `SET_LED LED=cavity_led WHITE=0/1`. Lüfter: `M106`.
  - Filament pro Kopf kommt aus `print_task_config`.
  - Kamera:
    - Extended-Firmware: WebRTC-Seite `/webcam/webrtc`.
    - Fallback: `/webcam/snapshot.jpg`.
    - Original-Firmware: `monitor.jpg` + `camera.start_monitor` per Websocket.
  - Gerätesuche per mDNS `_snapmaker._tcp`, die IP steht im TXT-Record `ip`.

## Entwicklung & Test

- Den Code schreibt Claude. Gebaut wird lokal in **Xcode** auf dem Mac, mit eigenem Developer-Account (siehe `ios/README.md`).
- Engine-Tests: `cd engine && npm install && npm run build && npm test` (22 Prüfungen).
- Logik-Tests: `cd Packages/SnarwalCore && swift test` (20 Tests).
- CI (GitHub Actions): alles oben plus App-Build, Engine-Test im iOS-Simulator (echtes WebKit:
  STL laden, zwei Köpfe slicen, Thumbnail) und Screenshots von iPhone und iPad.
  Die Screenshots liegen jeweils auf dem Branch `ci-screenshots` (wird bei jedem Lauf überschrieben).
- Testplan am echten Drucker, stufenweise:
  1. Den erzeugten G-Code mit Orca-G-Code vergleichen (ohne Drucker).
  2. Testwürfel mit einem Kopf.
  3. Test mit 2 Köpfen, du stehst dabei am Drucker.
  4. Alle 4 Köpfe.

## Ergebnis Testplan Schritt 1 (G-Code-Vergleich)

`engine/test/compare-orca.py` vergleicht die Firmware-Makros im Start-/End-G-Code mit dem
offiziellen U1-Profil von Snapmaker Orca (Stand 2026-01-28):

- Ende: identisch (`PRINT_END`, `TIMELAPSE_STOP`).
- Start: 32 von 34 Makros in identischer Reihenfolge und mit denselben Parametern
  (Bett-Mesh 11×11, Düsenreinigung, Purge-Linie X85→X185).
- Bewusst weggelassen:
  - `SET_PURIFIER_MODE`: Luftreiniger-Steuerung, optional.
  - `DEFECT_DETECT_NOODLE_FIRST`: Spaghetti-Erkennung, erst in neuerer Firmware.

  Beides ist harmlos, wenn es fehlt. Auf älterer Firmware würde ein unbekanntes Makro
  den Druck dagegen abbrechen.
- Kopfwechsel: wie bei Orca – Z anheben, `M104 T{n}`, `M400`, `T{n}`,
  `SM_PRINT_PREEXTRUDE_FILAMENT INDEX={n}`.

## Meilensteine

1. ✅ **M1 – Engine-Prototyp**: Kiri slict headless mit U1-Profil.
2. ✅ **M2 – Engine komplett**: mehrere Objekte, 3MF mit Orca-Kopfzuordnung, Orca-kompatible Metadaten.
3. ✅ **M3 – SnarwalCore**: Platte, Materialien, Einstellungen, G-Code-Vorschau, Moonraker-Client (getestet).
4. ✅ **M4 – iOS-App**: alle Bildschirme (Start, Platte mit 3D, Einstellungen, Vorschau, Senden,
   Drucker mit Kamera/Steuerung, Verbinden), Thumbnails, englische Übersetzung.
   Baut in der CI mit Xcode, die Engine läuft im iOS-Simulator (SnarwalTests).
5. **M5 – Test am eigenen Gerät**: in Xcode auf iPhone/iPad installieren, mit dem U1 verbinden.
6. **M6 – Testdrucke** nach Testplan (G-Code-Vergleich mit Orca → Würfel → 2 Köpfe → 4 Köpfe).
7. **M7 – App Store**: Englische Übersetzung, Datenschutzangaben, Screenshots, Review.

## Offen / später

- Kiri-Patch: Temperatur pro Kopf (gemischte Materialien).
  Bekannte Lücke: Kiri schreibt Temperaturwechsel ab Schicht 1 nur für T0/T1 explizit.
- Baumstützen, Farbmalen, STEP-Import, Push-Benachrichtigungen, Experteneinstellungen.
- Viele Kiri-Dateien tragen den Kopf „All Rights Reserved“, obwohl das Repo MIT-lizenziert ist.
  Vor dem App-Store-Release den Autor (Stewart Allen) um eine kurze Bestätigung bitten.
- Thumbnail (PNG) im G-Code für Touchscreen und Moonraker.
- Schicht-Vorschau in 3D statt Draufsicht.
