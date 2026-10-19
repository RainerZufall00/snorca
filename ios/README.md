# Snarwal – iOS-App bauen

## Voraussetzungen

- Mac mit **Xcode 16** oder neuer
- iPhone oder iPad mit **iOS/iPadOS 18+**
- Apple-Developer-Account (für den App Store; zum Testen auf dem eigenen Gerät reicht ein kostenloser Account)

## Erster Start

1. Repo klonen (oder auf GitHub „Code → Download ZIP“).
2. `ios/Snarwal.xcodeproj` in Xcode öffnen.
   Xcode löst das lokale Swift-Paket `Packages/SnarwalCore` automatisch auf.
3. Links das Projekt **Snarwal** → Target **Snarwal** → Reiter **Signing & Capabilities**:
   - **Team** auswählen (dein Developer-Account).
   - Falls Xcode meckert, dass die Bundle-ID vergeben ist: `io.github.rainerzufall00.snarwal`
     durch eine eigene ersetzen (z. B. `de.deinname.snarwal`).
4. Oben dein iPhone/iPad als Ziel wählen (per Kabel oder WLAN verbunden) und **▶︎ Run** drücken.
5. Beim ersten Start fragt iOS nach **„Lokales Netzwerk“** – erlauben, sonst findet die App den U1 nicht.

Die Slicing-Engine liegt fertig gebaut in `ios/EngineBundle` – Node.js wird zum Bauen der App **nicht** gebraucht.

## Automatische Prüfung (CI)

Bei jedem Push baut GitHub Actions die App mit Xcode, lässt die Tests laufen und macht Screenshots:

- **SnarwalCore-Tests** (macOS)
- **App-Build + SnarwalTests im iOS-Simulator**: startet die echte Kiri-Engine in WebKit,
  lädt ein STL und slict zwei Köpfe inklusive Thumbnail
- **Engine-Tests** in Chromium (Linux)
- **Screenshots** (iPhone und iPad) als Artefakt „screenshots“ am jeweiligen Lauf unter
  *Actions* → *CI*

Falls beim Bauen auf deinem Mac trotzdem etwas hakt, kopier die Fehlermeldung
(Xcode: Issue-Navigator, ⌘5) in den Chat.

## Debug-Startargumente

Nur in Debug-Builds (Xcode: Product → Scheme → Edit Scheme → Run → Arguments):

| Argument | Wirkung |
|---|---|
| `-SnarwalDemo` | Beispiel-Platte mit drei Objekten |
| `-SnarwalAutoSlice` | slict nach dem Start automatisch |
| `-SnarwalPrinterTab` | zeigt den Drucker-Tab mit simuliertem Druck |

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Snarwal/` | SwiftUI-App (wird von Xcode automatisch eingelesen) |
| `Snarwal/Engine/` | WKWebView mit der Kiri:Moto-Engine, lokaler Mini-Server auf 127.0.0.1 |
| `SnarwalTests/` | Engine-Tests im Simulator |
| `Snarwal/Localizable.xcstrings` | Englische Übersetzung (Quellsprache Deutsch) |
| `Snarwal/Slice/` | Druckplatte (SceneKit), Einstellungen, Vorschau, Senden |
| `Snarwal/Printer/` | Moonraker-Verbindung, Suche per mDNS, Kamera, Steuerung |
| `EngineBundle/` | gebaute Engine (`cd engine && npm run bundle:ios`) |
| `Info.plist` | Netzwerk-Rechte, Dateitypen STL/3MF |
| `../Packages/SnarwalCore/` | Logik mit Tests (`swift test`) |
