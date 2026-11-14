# Projekt nach GitHub schieben

Ziel-Repo: https://github.com/Budonist/Sun_Position_App_iOS_New

## Schritt für Schritt (auf deinem Mac)

1. ZIP herunterladen und entpacken.
2. Terminal im entpackten Ordner `sonnenschein_ios` öffnen.
3. Diese Befehle ausführen:

```bash
cd sonnenschein_ios
git init
git add .
git commit -m "Sonnenschein iOS v1.0.1 – aktueller Stand aus Abacus"
git branch -M main
git remote add origin https://github.com/Budonist/Sun_Position_App_iOS_New.git
git push -u origin main
```

Beim `git push` fragt Git nach deinen GitHub-Zugangsdaten
(Benutzername + Personal Access Token als Passwort).

## Danach: Xcode / TestFlight

Siehe `SETUP_XCODE.md` im selben Ordner – dort steht, wie du aus
`swift_space/project.yml` mit XcodeGen die `.xcodeproj` erzeugst,
signierst und nach TestFlight hochlädst.
