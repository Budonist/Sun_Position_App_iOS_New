# Genauigkeit & Fehlerbudget

Die Berechnung ist mathematisch hochgenau; der **begrenzende Faktor sind die
Eingangsdaten** (LoD2-Geometrie). Ergebnisse werden deshalb bewusst nicht
scheingenauer dargestellt, als die Daten hergeben.

## Fehlerquellen

| Fehlerquelle | Geschätzter Beitrag |
|---|---|
| Sonnenposition (NREL SPA) | ±0,0003° (vernachlässigbar) |
| LoD2-Gebäudegeometrie (Grundriss) | ±0,3–1,0 m |
| LoD2-Gebäudehöhe | ±0,5–1,5 m |
| Refraktion nahe Horizont (< 1° Elevation) | bis ±0,2° (wetterabhängig) |
| Karten-Tap-Präzision | ±1–3 m (zoomabhängig) |
| Beobachterhöhe (Standard 1,2 m) | ±0,3 m |
| Geländemodell (DGM1) | ±0,1 m |
| **Praktische Genauigkeit der Schattenkante (Zeit)** | **±2–5 Minuten** |

## Numerische Toleranzen (Engine)

| Konstante | Wert | Bedeutung |
|---|---|---|
| `rayTMin` | 0,01 m | Mindestdistanz eines Treffers (keine Selbsttreffer) |
| `determinantEpsilon` | 1e-12 | Strahl parallel zum Dreieck |
| `barycentricEpsilon` | 1e-9 | Kanten zählen als Treffer (konservativ Schatten) |
| `insideEpsilon` | 0,01 m | Beobachter-im-Gebäude-Test |
| `aabbPadding` | 0,001 m | Aufweitung der Bounding-Boxen |
| `hitTieEpsilon` | 0,001 m | deterministischer Tie-Break bei koinzidenten Flächen |

## Confidence

- **high**: vollständiges LoD2, eindeutige Lage.
- **niedriger**: Datenlücken, Grenzlagen, oder gekennzeichneter OSM-Fallback.

Ergebnisse nahe einer Schattenkante (±0,05° Sonnenrichtung) werden in der
Regression als `robust: false` markiert. Kriterien im Detail:
`ADR-001-geodata-sources.md`. Vollständiger Validierungsbericht:
`turandot_validation.md`.
