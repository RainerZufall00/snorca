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
├── vendor/grid-apps/        Kiri:Moto (Submodul, gepinnt)
├── engine/                  JS-Bundle für den WKWebView
│   ├── build.mjs            baut engine/dist (Engine, Worker, WASM)
│   ├── src/snarwal-engine.js  Brücke: window.snarwal.slice({ stl, process, tool })
│   ├── profiles/            U1-Geräteprofil + Basis-Prozess
│   └── test/                Headless-Test (Playwright/Chromium)
├── ios/                     SwiftUI-App (folgt)
└── docs/
```

- Die App liefert `engine/dist` als Ressource aus und lädt sie über einen `WKURLSchemeHandler`
  (z. B. `snarwal://engine/`). Ein `file://` geht nicht, weil Module-Worker und das Laden der WASM-Dateien dort scheitern.
- Swift ruft `callAsyncJavaScript("return await snarwal.slice(...)")` auf und erhält G-Code und Statistiken zurück.

## Entwicklung & Test

- Den Code schreibt Claude. Gebaut wird lokal in **Xcode** auf dem Mac, mit eigenem Developer-Account.
- Engine-Test: `cd engine && npm install && npm run build && npm test`.
- Testplan am echten Drucker, stufenweise:
  1. Den erzeugten G-Code mit Orca-G-Code vergleichen (ohne Drucker).
  2. Testwürfel mit einem Kopf.
  3. Test mit 2 Köpfen, du stehst dabei am Drucker.
  4. Alle 4 Köpfe.

## Meilensteine

1. ✅ **M1 – Engine-Prototyp**: Kiri slict headless einen 20-mm-Würfel mit U1-Profil (Test grün).
2. **M2 – iOS-Hülle**: Xcode-Projekt, Engine im WKWebView, STL öffnen → G-Code teilen.
3. **M3 – Drucker**: Verbindung, Upload, „Jetzt drucken?“, Status.
4. **M4 – Druckplatte & Vorschau**: 3D-Ansicht, mehrere Objekte, Schichtvorschau.
5. **M5 – Mehrere Köpfe**: Kopfzuordnung, 3MF-Metadaten, Filament vom Drucker.
6. **M6 – Überwachung komplett**: Kamera, Steuerung, Temperaturen.
7. **M7 – App Store**: Icon, Lokalisierung, Datenschutz, Review.

## Offen / später

- Kiri-Patch: Temperatur pro Kopf (gemischte Materialien).
  Bekannte Lücke: Kiri schreibt Temperaturwechsel ab Schicht 1 nur für T0/T1 explizit.
- Baumstützen, Farbmalen, STEP-Import, Push-Benachrichtigungen, Experteneinstellungen.
- Viele Kiri-Dateien tragen den Kopf „All Rights Reserved“, obwohl das Repo MIT-lizenziert ist.
  Vor dem App-Store-Release den Autor (Stewart Allen) um eine kurze Bestätigung bitten.
- Moonraker-Metadaten: prüfen, ob Moonraker Druckzeit und Layer aus Kiri-G-Code erkennt. Falls nicht, Header ergänzen.
