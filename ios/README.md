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

## Wenn etwas nicht klappt

Der App-Code wurde in einer Linux-Umgebung ohne Xcode geschrieben: Die Logik (`Packages/SnarwalCore`)
und die Engine sind getestet, die SwiftUI-Oberfläche konnte aber nicht kompiliert werden.
Rechne beim ersten Build mit ein paar Compiler-Fehlern. Kopier sie einfach (Xcode: Issue-Navigator,
⌘5) in den Chat, dann behebe ich sie.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `Snarwal/` | SwiftUI-App (wird von Xcode automatisch eingelesen) |
| `Snarwal/Engine/` | WKWebView mit der Kiri:Moto-Engine, lokaler Mini-Server auf 127.0.0.1 |
| `Snarwal/Slice/` | Druckplatte (SceneKit), Einstellungen, Vorschau, Senden |
| `Snarwal/Printer/` | Moonraker-Verbindung, Suche per mDNS, Kamera, Steuerung |
| `EngineBundle/` | gebaute Engine (`cd engine && npm run bundle:ios`) |
| `Info.plist` | Netzwerk-Rechte, Dateitypen STL/3MF |
| `../Packages/SnarwalCore/` | Logik mit Tests (`swift test`) |
