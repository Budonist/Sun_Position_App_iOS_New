# Sonnenschein – Lokaler Build & TestFlight-Deploy über Xcode

Diese Anleitung beschreibt, wie du das Projekt auf deinem Mac in Xcode öffnest,
signierst und selbst nach TestFlight hochlädst – unabhängig vom Deploy-Dialog der
Abacus-Plattform.

> **Team ID:** `8ZKX2W54FA` (dein Apple Developer Account)

---

## ⚠️ Wichtig: Es gibt KEINE `.xcodeproj`-Datei im Repo

Dieses Projekt enthält **kein** fertiges `SonnenscheinIos.xcodeproj`. Die Projektdatei
wird aus der Spezifikation `swift_space/project.yml` mit dem Werkzeug **XcodeGen**
erzeugt. Das ist Absicht (so bleibt das Repo sauber und mergefähig). Du musst die
`.xcodeproj` also einmalig lokal generieren, bevor du Xcode öffnest.

---

## 1. Voraussetzungen

```bash
# Homebrew (falls noch nicht vorhanden): https://brew.sh
# XcodeGen installieren:
brew install xcodegen
```

- Xcode (aktuelle Version) installiert
- In Xcode unter *Settings → Accounts* mit deiner Apple ID angemeldet
  (Team `8ZKX2W54FA`)

---

## 2. Xcode-Projekt generieren und öffnen

```bash
cd swift_space
xcodegen generate          # erzeugt SonnenscheinIos.xcodeproj
open SonnenscheinIos.xcodeproj
```

---

## 3. Signing & Bundle Identifier anpassen

Die im Repo hinterlegte Bundle-ID (`com.abacusai.sonnenscheinios.…`) gehört zur
Abacus-Plattform und **kann nicht in deinem Account verwendet werden**. Du brauchst
eine eigene:

1. Registriere eine eigene Bundle-ID in App Store Connect / im Developer-Portal,
   z. B. `de.kaldenbach.sonnenschein`.
2. In Xcode: Target **SonnenscheinIos → Signing & Capabilities**
   - **Team:** deinen Account (8ZKX2W54FA) wählen
   - **Bundle Identifier:** auf deine eigene ID setzen
   - *Automatically manage signing* aktiviert lassen

> Tipp: Damit die Änderung beim nächsten `xcodegen generate` nicht verloren geht,
> kannst du `PRODUCT_BUNDLE_IDENTIFIER` und `DEVELOPMENT_TEAM` direkt in
> `swift_space/project.yml` eintragen.

---

## 4. Nach TestFlight hochladen

1. Oben im Xcode-Schema als Ziel **"Any iOS Device (arm64)"** wählen
   (nicht den Simulator).
2. Menü **Product → Archive**.
3. Im Organizer-Fenster: **Distribute App → App Store Connect → Upload**.
4. Nach der Verarbeitung erscheint der Build in App Store Connect unter
   **TestFlight** → dort dich/Tester hinzufügen und per TestFlight-App installieren.

---

## 5. Hinweise zum Projekt

- **Deployment Target:** iOS 18.0
- **Kein Backend:** `API_BASE_URL` in `Config.xcconfig` ist bewusst leer.
- **Geodaten sind eingebettet:** Die amtlichen Berliner LoD2-Gebäudedaten liegen in
  `swift_space/Assets.xcassets/TurandotBuildings.dataset/` bzw.
  `swift_space/Resources/turandot_buildings.json` und werden automatisch mit
  gebündelt.
- **Rechen-Engine:** `swift_space/Sources/Engine/` (SolarEngine = NREL SPA,
  ShadowEngine = Möller–Trumbore Ray-Casting).
- **Anzeigename:** `CFBundleDisplayName` in `project.yml` (aktuell
  "SonnenscheinIos"). Für den Home-Screen-Namen "Sonnenschein" dort anpassen.

---

## 6. Auf dein eigenes GitHub schieben

Von deinem Mac aus, nachdem du das Projekt heruntergeladen hast:

```bash
# im Projektordner
git init            # nur falls noch kein .git vorhanden
git add .
git commit -m "Sonnenschein iOS – Import aus Abacus"
git branch -M main
git remote add origin https://github.com/Budonist/<dein-repo>.git
git push -u origin main
```
