# Snarwal 🐋

Unofficial iOS/iPadOS app for the **Snapmaker U1**: slice models on your iPhone or iPad,
send them to the printer and watch the print. Not affiliated with Snapmaker.

Slicing runs fully on-device with the [Kiri:Moto](https://github.com/GridSpace/grid-apps) engine (MIT).

**Status:** early prototype. The slicing engine bundle works; the iOS app is next.
See [docs/DESIGN.md](docs/DESIGN.md) (German) for the plan.

## Engine

```sh
git submodule update --init
cd engine
npm install
npm run build   # writes engine/dist
npm test        # slices a 20 mm cube in headless Chromium
```

## License

MIT, see [LICENSE](LICENSE). Kiri:Moto is MIT licensed by Stewart Allen.
