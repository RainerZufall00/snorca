# Snarwal 🐋

[![CI](https://github.com/RainerZufall00/snorca/actions/workflows/ci.yml/badge.svg)](https://github.com/RainerZufall00/snorca/actions/workflows/ci.yml)

Unofficial iOS/iPadOS app for the **Snapmaker U1**: slice models on your iPhone or iPad,
send them to the printer and watch the print. Not affiliated with Snapmaker.

Slicing runs fully on-device with the [Kiri:Moto](https://github.com/GridSpace/grid-apps) engine (MIT).

**Status:** early development. Engine, core logic and the app build are checked in CI (including
slicing inside WebKit on the iOS simulator); not yet tested against a real printer. See [docs/DESIGN.md](docs/DESIGN.md) (German) for the plan and
[ios/README.md](ios/README.md) for building the app. German user guide: [docs/ANLEITUNG.md](docs/ANLEITUNG.md).

## Engine

```sh
git submodule update --init
cd engine
npm install
npm run build   # writes engine/dist
npm test        # slicing tests in headless Chromium
npm run bundle:ios   # refreshes ios/EngineBundle
```

## Core logic

```sh
cd Packages/SnarwalCore
swift test
```

## License

MIT, see [LICENSE](LICENSE). Kiri:Moto is MIT licensed by Stewart Allen.
