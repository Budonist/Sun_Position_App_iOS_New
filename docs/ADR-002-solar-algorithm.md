# ADR-002: Algorithmus für den Sonnenstand

| | |
|---|---|
| **Status** | Angenommen, umgesetzt in Phase 1 |
| **Datum** | 18.10.2026 |
| **Betroffene Komponenten** | `Sources/SolarEngine/SolarPositionCalculator.swift`, `Sources/SolarEngine/SPATables.swift`, `Tests/SolarEngineTests/SolarPositionTests.swift`, `scripts/solar_algorithm_comparison.py` |

## 1. Kontext

Die ShadowEngine schickt vom Beobachter einen Strahl in Richtung Sonne (Azimut, Elevation). Ein Winkelfehler Δe verschiebt die Schattenkante einer Traufe der Höhe H um

```
Δs ≈ H · Δe[rad] / sin²(e)
```

Bei tiefem Sonnenstand wird schon ein kleiner Winkelfehler zu Dezimetern. Zusätzlich muss der Algorithmus Zeitzonen und Sommerzeit (CET/CEST) korrekt behandeln und auf iOS ohne Netz und schnell laufen.

## 2. Betrachtete Optionen

| | A: NREL SPA | B: Vereinfachter Meeus | C: NOAA-Tabellenkalkulation |
|---|---|---|---|
| Quelle | Reda & Andreas (2004, rev. 2008), NREL/TP-560-34302 | Meeus, *Astronomical Algorithms*, 2. Aufl., Kap. 25 (niedrige Genauigkeit) + Kap. 12/13 | NOAA Solar Calculator (basiert auf Meeus) |
| Spezifizierte Genauigkeit | **±0,0003°** Zenit/Azimut, Jahre −2000 … 6000 | ≈ 0,01° | ≈ 0,0167° (1′) für ±800 Jahre |
| Inhalt | VSOP87-Periodenterme (Erde L/B/R), Nutation (63 Terme), Aberration, topozentrische Parallaxe, Refraktion | Mittlere Anomalie + Mittelpunktsgleichung, Nutation nur über Ω-Term, keine Parallaxe | wie Meeus |
| Code-Umfang | ≈ 450 Zeilen + Tabellen (≈ 1150 Zahlenwerte in `SPATables.swift`) | ≈ 40 Zeilen | ≈ 60 Zeilen |
| Referenz-Testfall | offizieller NREL-Testfall mit 6 Nachkommastellen | keiner mit SPA-Präzision | Online-Rechner |
| Lizenz | Algorithmus im NREL-Report publiziert; eigene Swift-Neuimplementierung, strukturell an der Referenz `spa.c` orientiert. Die Koeffizienten stammen aus dem Report. Vor App-Store-Release prüft Phase 9 die NREL-Nutzungsbedingungen | frei | frei |

## 3. Messung: Meeus vs. SPA am Standort Turandot

`scripts/solar_algorithm_comparison.py` vergleicht B gegen A (Referenz `pvlib.spa`, 0.16.1). Bedingungen: 52.4894903 N / 13.3922155 E, Jahr 2025 stündlich, ΔT = 69,12 s für beide, geometrische Elevation ohne Refraktion, 4405 Stunden mit Sonne über dem Horizont. Ergebnis in `data/processed/solar_algorithm_comparison.json`:

| Größe | Mittel | 95 %-Quantil | Maximum |
|---|---|---|---|
| \|Δ Elevation\| Meeus − SPA | 0,0031° | 0,0079° | 0,0104° |
| \|Δ Azimut\| Meeus − SPA | 0,0039° | 0,0098° | 0,0156° |
| Versatz Schattenkante, 20 m Traufe, e ≥ 5° | 0,03 m | – | **0,47 m** |

Interpretation: Im Mittel reicht Meeus für Schatten aus. Bei flachem Sonnenstand (Morgen/Abend, Winter) erreicht der Versatz aber fast einen halben Meter. Genau dort entscheidet sich „Sonne noch auf dem Tisch oder nicht“. SPA reduziert den Algorithmusanteil um den Faktor ≈ 30 auf < 2 cm. Danach dominieren nur noch die Gebäudedaten (LoD2 ≈ 0,5–1 m) und die Refraktion in Horizontnähe.

## 4. Entscheidung

**Option A: NREL SPA**, eigene Swift-Implementierung ohne externe Abhängigkeiten (nur Foundation). Gründe:

1. Genauigkeit ±0,0003°, damit ist der Sonnenstand im Fehlerbudget vernachlässigbar.
2. Offizieller Referenztestfall ermöglicht einen harten Regressionstest auf 1e-5°.
3. Rechenaufwand ist unkritisch: Eine komplette Schattenabfrage **inklusive** SPA-Berechnung dauert ≈ 120 µs (Release-Build, Linux, Swift 6.0.3, gemessen mit `shadow-cli batch`). Ein Tagesverlauf in 5-min-Schritten (288 Abfragen) braucht < 0,05 s.
4. Dieselbe Formulierung gibt es in pvlib (Python). Dadurch ist eine unabhängige Kreuzvalidierung möglich.

## 5. Umsetzungsdetails

| Aspekt | Festlegung |
|---|---|
| Eingabe | `Date` (absoluter Zeitpunkt), Breite/Länge in Grad WGS84 (+N, +O), Höhe in m. Bequem-API `makeDate(year:month:day:hour:minute:second:timeZone:)` |
| Zeitzonen / Sommerzeit | **Ausschließlich über Foundation** (`TimeZone(identifier: "Europe/Berlin")`, `Calendar`). Keine eigene DST-Logik. Intern wird auf UTC zerlegt; ΔUT1 = 0 (\|UT1 − UTC\| < 0,9 s ⇒ < 0,004°). Getestet: 21.06. CEST (UTC+2), 21.12. CET (UTC+1), Umstellungen 30.03.2025 und 26.10.2025 (25-h-Tag) |
| ΔT = TT − UT1 | `SPA.deltaT(decimalYear:)`: Stützwerte 1990–2026 (IERS/USNO, gerundet; 2025,5 ⇒ 69,12 s), linear interpoliert; danach Trend +0,1 s/Jahr bis 2050, dann Espenak-&-Meeus-Polynome. Fehler 2026–2035 geschätzt < 3 s ⇒ < 0,0125° |
| Ausgabe | Azimut 0…360° **von geografisch Nord im Uhrzeigersinn**; topozentrische Elevation mit (`elevation`) und ohne (`elevationGeometric`) Refraktion; Zenit; Zeitgleichung |
| Refraktion | SPA-Refraktionsformel (Sæmundsson-Typ, `1.02 / (60·tan(e0 + 10.3/(e0 + 5.11)))`, skaliert mit Druck/Temperatur) mit `Atmosphere.berlin` = 1013,25 hPa, 10,3 °C (Berliner Jahresmittel). Korrektur nur für e ≥ −(Sonnenradius + Horizontrefraktion) = −0,8334°. Für Schattenstrahlen wird die **refraktierte** Elevation verwendet, denn das Licht kommt scheinbar von dort |
| Auf-/Untergang, Transit | SPA-Anhang A.2 (`sunTimes`); Toleranz gegen pvlib 30 s |
| Numerik | Double (IEEE 754). Periodenterme in Original-Reihenfolge summiert; Winkel über `limitDegrees` normiert |
| Eingabeprüfung | \|Breite\| ≤ 90°, \|Länge\| ≤ 180°, sonst `throw` |

## 6. Validierung (Phase 1, `swift test`: 12 Tests grün)

| Test | Referenz | Toleranz | Ergebnis |
|---|---|---|---|
| NREL-Testfall 17.10.2003 12:30:30 Ortszeit (UTC−7), 39.742476 N / −105.1786 E, 1830,14 m, 820 hPa, 11 °C, ΔT = 67 s | Zenit 50,111622°, Azimut 194,340241°, Elevation 39,888378° | 1e-5° | bestanden |
| NREL-Testfall: Auf-/Untergang, Transit | 06:12:43 / 11:46:04 / 17:20:19 | 1 s | bestanden |
| Berlin 21.06.2025 17:00 CEST (Turandot) | pvlib: Azimut 259,482367°, Elevation 37,769606° | 2e-3° | bestanden |
| Berlin 21.06. 12:00 CEST, 21.12. 12:00 CET | pvlib | 2e-3° | bestanden |
| Sonnenauf-/-untergang Berlin (mehrere Daten, inkl. DST-Wechsel) | pvlib | 30 s | bestanden |
| Plausibilität: Transit-Azimut 180°, Nacht e < 0, Zenit + Elevation = 90° | Geometrie | 0,05° / 1e-9 | bestanden |

Die 2e-3°-Toleranz gegen pvlib erklärt sich durch leicht abweichende Rundung der ΔT-Stützwerte. Mit identischem ΔT liefern Swift und pvlib in der Phase-3-Kreuzvalidierung **dieselben Winkel** (Differenz 0° bei Validierungstoleranz 0,005°, 3080 Abfragen).

## 7. Konsequenzen

- ΔT-Tabelle muss etwa jährlich gepflegt werden (eine Codezeile). Ohne Pflege wächst der Fehler um ≈ 0,004° pro Jahr Abweichung von 1 s, also unkritisch.
- Refraktion bei Elevation < 1° ist wetterabhängig und auf ≈ 0,5° unsicher. In diesem Bereich steht die Sonne in der Bergmannstraße ohnehin hinter Gebäuden.
- Keine Abhängigkeit von Netz oder Drittbibliotheken; läuft identisch auf iOS und Linux. Die Tests liefen bisher nur unter Linux (Swift 6.0.3). Ein Lauf unter Xcode/iOS-Simulator steht noch aus (Phase 5).
