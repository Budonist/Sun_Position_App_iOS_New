# ADR-001: Geodatenquellen für Gebäude, Gelände und Testpunkte

| | |
|---|---|
| **Status** | Angenommen |
| **Datum** | 18.10.2026 |
| **Kontext** | Phase 0–4, Proof-of-Concept Turandot (Bergmannstraße 93, 10961 Berlin) |
| **Betroffene Komponenten** | `scripts/geodata_pipeline.py`, `scripts/sonnen_common.py`, `Sources/ShadowEngine/GeometryStore.swift` |

## 1. Kontext und Problem

Die Schattenberechnung braucht dreidimensionale Gebäudegeometrie mit Dachformen, eine Geländehöhe für Beobachter und Gebäudesockel, sowie Koordinaten der Testpunkte. Alle Quellen müssen

- für Berlin flächendeckend und aktuell sein,
- eine Lizenz haben, die das Bündeln in einer kommerziellen iOS-App erlaubt,
- automatisiert und reproduzierbar abrufbar sein,
- ein dokumentiertes CRS haben.

## 2. Untersuchte Quellen (Recherche am 18.10.2026)

### 2.1 Einstiegsportale

| Portal aus dem Auftrag | Befund am 18.10.2026 |
|---|---|
| `https://www.stadtentwicklung.berlin.de/geoinformation/` | HTTP-Weiterleitung auf `https://www.berlin.de/sen/stadt/` (Geoportal-Inhalte sind umgezogen) |
| `https://fbinter.stadt-berlin.de/` | Weiterleitung auf den neuen Geoportal-Viewer `https://gdi.berlin.de/viewer/main/`. Downloads und Dienste liegen jetzt unter `https://gdi.berlin.de/data/…` (ATOM) und `https://gdi.berlin.de/services/…` (WMS/WFS) |
| `https://daten.berlin.de/` | Liefert HTTP 403 an den automatisierten Abruf aus der Build-VM. Der Datensatz ist dort als „3D-Gebäudemodelle im Level of Detail 2 (LoD 2)“ gelistet: `https://daten.berlin.de/datensaetze/3d-gebaudemodelle-im-level-of-detail-2-lod-2-3c7c49af`. Die maßgeblichen Metadaten wurden stattdessen direkt aus dem ATOM-Feed gelesen |

### 2.2 Amtliches LoD2 (gewählt, primäre Quelle)

| Merkmal | Wert |
|---|---|
| Name | 3D-Gebäudemodelle im Level of Detail 2 (LoD 2), Land Berlin |
| Anbieter | Senatsverwaltung für Stadtentwicklung, Bauen und Wohnen Berlin |
| Metadaten-ID (CSW) | `3c7c49af-00a4-3bcd-bc00-20e7f0f1b7bf` |
| Bezugsweg | INSPIRE-ATOM-Download-Service. Service-Feed `https://gdi.berlin.de/data/a_lod2/atom`, Dataset-Feed `https://gdi.berlin.de/data/a_lod2/atom/0.atom` |
| Kachelung | 925 Kacheln zu 1 × 1 km, Dateinamensschema `LoD2_{E}_{N}.zip` (E/N = UTM-Kilometer), MIME-Typ `application/x-gmz` |
| Format | CityGML 1.0, AdV-Profil (bldg:Building / BuildingPart, `lod2Solid` bzw. Wall-/Roof-/GroundSurface) |
| CRS | EPSG:25833 (ETRS89 / UTM Zone 33N) + Höhen DHHN2016 Normalhöhen, srsName `urn:adv:crs:ETRS89_UTM33*DE_DHHN2016_NH` |
| Aktualität | Feed aktualisiert 26.03.2026, Dateien vom 24.03.2026 |
| Inhalt / Genauigkeit | Grundrisse = ALKIS-Gebäudeumringe; Dächer als generalisierte Standarddachformen (Flach-, Sattel-, Walm-, Mansard-, Pultdach …) aus Laserscanning abgeleitet. Kein Dachüberstand, keine Gauben, keine Balkone/Markisen |
| Lizenz | **Datenlizenz Deutschland – Zero – Version 2.0 (dl-de/zero-2-0)**. Freie Nutzung inkl. kommerziell, ohne Namensnennungspflicht. Wir nennen die Quelle trotzdem freiwillig in der App (Impressum/Datenquellen) |

**Datenvolumen** (gemessen an den vier für den PoC genutzten Kacheln):

| Kachel | ZIP | entpacktes XML |
|---|---|---|
| 390_5816 | 5,75 MB | 49,9 MB |
| 390_5817 | 4,43 MB | 37,6 MB |
| 391_5816 | 3,09 MB | 26,0 MB |
| 391_5817 | 3,66 MB | 31,1 MB |
| **Summe** | **16,9 MB** | **144,5 MB** |

Nach der Vorverarbeitung (Kreis mit 500 m Radius um Turandot, triangulierte Hülle in lokalen ENU-Metern, siehe Abschnitt 4) bleiben **1330 Gebäude mit 67 331 Dreiecken = 5,6 MB JSON** (gzip: 0,85 MB).
Hochrechnung auf ganz Berlin (Schätzung, nicht gemessen): 925 Kacheln × ≈ 4 MB ZIP ≈ **3,5–4 GB ZIP**. Innenstadtkacheln sind dichter bebaut als Randkacheln, deshalb ist das eine Obergrenze.

### 2.3 WFS oder nur Bulk-Download?

| Dienst | Befund |
|---|---|
| LoD2-WFS `https://gdi.berlin.de/services/wfs/a_lod2` | **Existiert nicht** (HTTP 404). LoD2 gibt es **nur als Bulk-Download** über ATOM (kachelweise ZIP) |
| `https://gdi.berlin.de/services/wfs/alkis_gebaeude` | WFS mit Layer `alkis_gebaeude:gebaeude`: 2D-Gebäudeumringe mit Attributen, u. a. `aog` (Anzahl oberirdischer Geschosse), `hoh`, `gfk` (Gebäudefunktion), `lag`/`hnr` (Adresse). Lizenz dl-de/zero-2-0 |
| `https://gdi.berlin.de/services/wfs/ua_gebaeudehoehen` | WFS 2.0.0 mit Layer `ua_gebaeudehoehen:gebaeudehoehen`: Gebäudehöhen (aus LoD2 abgeleitet), Ausgabe GML oder GeoJSON. Lizenz dl-de/zero-2-0 |

Folge: Ein WFS-Fallback liefert höchstens **LoD1** (Grundriss + Höhe, Flachdach-Extrusion). Volle Dachgeometrie gibt es nur über die vorverarbeiteten ATOM-Kacheln. Siehe ADR-003.

### 2.4 Digitales Geländemodell (DGM)

| Merkmal | Wert |
|---|---|
| Name | ATKIS® DGM (1m-Rasterweite), Land Berlin |
| Bezugsweg | ATOM `https://gdi.berlin.de/data/dgm1/atom` |
| Kachelung / Format | 2 × 2 km, ASCII-XYZ (E N H), 1 m Raster |
| CRS | EPSG:25833 + DHHN2016 |
| Volumen | `DGM1_390_5816.zip` = 17,5 MB, entpackt 120 MB |
| Aktualität | Feed aktualisiert 18.12.2025 |
| Lizenz | dl-de/zero-2-0 |

Verwendung: Im Store landet ein auf 5 m ausgedünntes Höhenraster (209 × 209 Zellen um Turandot). Es dient für die Bodenhöhe der Beobachterpunkte (Augenhöhe 1,2 m über DGM). Gelände ist bewusst **kein** Verdecker. Der Viktoriapark/Kreuzberg liegt südwestlich und bis zu ≈ 19 m über dem Ursprung, verschattet die Bergmannstraße aber nur bei sehr tiefem Sonnenstand. Das ist eine bekannte Einschränkung, siehe Abschnitt 7.

### 2.5 OpenStreetMap (Fallback, gekennzeichnet)

| Merkmal | Wert |
|---|---|
| Inhalt | `building=*`-Polygone mit optional `height` und `building:levels` |
| Lizenz | ODbL 1.0, © OpenStreetMap-Mitwirkende. **Share-Alike für abgeleitete Datenbanken** – beim Bündeln in der App müsste der abgeleitete Store unter ODbL gestellt werden |
| Abruf im PoC | Overpass-API von der Build-VM aus **nicht nutzbar** (overpass-api.de: Timeout; overpass.kumi.systems: HTTP 500). Stattdessen OSM-API-Ausschnitt `map?bbox=13.3895,52.4885,13.3950,52.4905` (1,29 MB XML, 168 Gebäude, ≈ 370 × 220 m), Datei `data/raw/osm/osm_map_turandot_street.osm` |
| Ergebnis | `data/processed/turandot_buildings_osm_fallback.json`: 168 Gebäude, 4506 Dreiecke, 0,34 MB |
| Höhenqualität im Ausschnitt | 0 × `height`, 163 × `building:levels`, 5 × ohne Höhenangabe |

### 2.6 Bewertungsmatrix

| Kriterium | LoD2 Berlin (ATOM) | ALKIS-/Höhen-WFS (LoD1) | OSM |
|---|---|---|---|
| Dachformen | ja (generalisiert) | nein | nein |
| Höhengenauigkeit | ≈ 0,5–1 m (Laserscanning) | Höhe aus LoD2, aber nur ein Wert pro Gebäude | geschätzt aus Geschossen, ±3 m und mehr |
| Abdeckung Berlin | 100 % | 100 % | lückenhaft bei Höhenattributen |
| Lizenz für App | dl-de/zero-2-0, unproblematisch | dl-de/zero-2-0 | ODbL, Share-Alike |
| Online-Abfrage | nein (nur Bulk) | ja (WFS 2.0) | ja (Overpass, aber unzuverlässig) |
| CRS | EPSG:25833 + DHHN2016 | EPSG:25833 | EPSG:4326, keine Höhenbezugsfläche |

## 3. Entscheidung

1. **Primäre Gebäudequelle: amtliches Berliner LoD2 (CityGML) aus dem ATOM-Feed**, offline vorverarbeitet zu einem Geometry-Store. Es war im PoC technisch abrufbar; der Fallback war daher für das Ergebnis **nicht** nötig.
2. **Gelände: ATKIS DGM1**, ausgedünnt auf 5 m, nur für Bodenhöhen.
3. **OSM nur als gekennzeichneter Fallback** (`--source osm`), mit Confidence `medium`/`low`/`very_low` (Abschnitt 5). Der Fallback ist implementiert und wurde gegen LoD2 verglichen, wird aber nicht ausgeliefert.
4. **Online-Fallback später (ADR-003): WFS `ua_gebaeudehoehen` + `alkis_gebaeude`** als LoD1-Extrusion mit Confidence `medium` für Gebiete außerhalb des gebündelten Stores.
5. **Testpunkt-Koordinaten:** Nominatim/OSM (nur Punktkoordinate, keine Datenbank-Übernahme).

## 4. Koordinatenreferenzsysteme und Transformationen

| Stufe | CRS | Wo |
|---|---|---|
| Rohdaten LoD2 und DGM | EPSG:25833 (ETRS89 / UTM 33N), Höhe DHHN2016 Normalhöhe (NHN) | `data/raw/lod2`, `data/raw/dgm1` |
| Rohdaten OSM, Testpunkte, Sonnenstand | EPSG:4326 (WGS84 geographisch), ETRS89 ≈ WGS84 auf < 1 m | `data/raw/osm`, `Tests/fixtures/turandot_points.json`, SPA-Eingabe |
| Geometry-Store und ShadowEngine | lokales **ENU** (East-North-Up, Meter). Ursprung = Turandot 52.4894903 N / 13.3922155 E, h0 = 36,277 m NHN (DGM am Ursprung). UTM33 des Ursprungs: E 390 836,322 / N 5 816 698,08 | `data/processed/*.json`, `Sources/ShadowEngine` |

**Transformationskette** (in `scripts/sonnen_common.py`):

```
UTM33 (E, N) + H_NHN
  └─ pyproj EPSG:25833 → EPSG:4326        → (φ, λ)
       └─ geodätisch → ECEF (WGS84-Ellipsoid, h := H_NHN)
            └─ ECEF → ENU (Rotation um Ursprung φ0, λ0; Translation auf Ursprung, Up := H − h0)
```

Begründung:

- **Warum nicht direkt in UTM rechnen?** Die UTM-Gitter-Nordrichtung weicht in Berlin um ≈ 1,28° (Meridiankonvergenz) von der geografischen Nordrichtung ab. Der SPA-Azimut bezieht sich auf **geografisch Nord**. Ohne Korrektur wäre jede Schattenrichtung um 1,28° verdreht, bei 30 m Gebäudeabstand ≈ 0,7 m seitlicher Versatz. Das ENU-System ist per Konstruktion an geografisch Nord ausgerichtet.
- **Höhenbezug:** NHN-Höhen werden als Ellipsoidhöhen eingesetzt. Dadurch ist Up absolut um die Geoidundulation (≈ 39 m) verschoben, aber Höhen**differenzen** bleiben exakt. Der Lage-/Richtungsfehler durch die falsche Ellipsoidhöhe ist < 1 mm im 500-m-Radius.
- **Erdkrümmung:** Ist durch ECEF→ENU enthalten. Bei 500 m Abstand fällt die Tangentialebene ≈ 2 cm ab.
- In der App (ADR-003) wird nur die Transformation WGS84 → ENU benötigt. Sie ist in Swift als WGS84 → ECEF → ENU umgesetzt (`ENUFrame` in `Sources/ShadowEngine/Geometry.swift`). In der Kreuzvalidierung (Phase 3, 3080 Abfragen) stimmen Python-Referenz und Swift-Engine im Ergebnis zu 100 % überein; die Blocker-Distanzen weichen um höchstens 0,5 mm ab.

## 5. Confidence-Kriterien LoD2 vs. OSM-Fallback

Jedes Gebäude im Store trägt ein Feld `confidence`, das in Swift als `Building.confidence` geladen wird. Bei „Schatten“ liefert `ShadowResult.building` das blockierende Gebäude und damit dessen Confidence (implementiert). Für „Sonne“ wird ab Phase 5 die schlechteste Confidence aller Gebäude übernommen, deren AABB der Strahl geschnitten hat. Im PoC ist das nicht nötig, weil der Turandot-Store vollständig `high` ist.

| Stufe | Kriterium | Höhenmodell | Erwarteter Höhenfehler | Verwendung |
|---|---|---|---|---|
| `high` | Amtliches LoD2 (CityGML), Dachform vorhanden | Echte Dachgeometrie | ≈ 0,5–1 m | Standard; Ergebnis ohne Einschränkung anzeigen |
| `medium` | OSM mit `height`-Tag **oder** künftiger WFS-Fallback (`ua_gebaeudehoehen`) | Flachdach-Extrusion bis gemessener Höhe | ±1–3 m, Dachform fehlt | Anzeigen mit Hinweis „vereinfachtes Gebäudemodell“ |
| `low` | OSM nur mit `building:levels` | Höhe = 3,0 m × Geschosse + 1,0 m | ±3–5 m (Altbau-Geschosse 3,5–4 m) | Anzeigen mit deutlicher Warnung |
| `very_low` | OSM ohne Höhenangabe | pauschal 15 m | > 5 m | nur Debug; nicht für Nutzerantwort |

Validierung der Kriterien am Turandot-Szenario (`docs/turandot_validation.md`, Abschnitt 5): Von 294 Abfragen stimmen 250 (85,0 %) zwischen LoD2 und OSM-Fallback überein. Alle 44 Abweichungen sind „LoD2 Schatten / OSM Sonne“. Die OSM-Extrusion unterschätzt also systematisch die Verschattung (fehlende Firste, zu niedrige Geschosshöhen der Gründerzeitbauten). Damit ist die Einstufung `low` gerechtfertigt.

## 6. Turandot-Koordinaten und Testpunkte

- **Turandot:** OSM-Node 2245836213 (`amenity=pub`, Bergmannstraße 93), **52.4894903 N, 13.3922155 E** (Nominatim, abgerufen 18.10.2026).
- Gastgebäude im LoD2: `DEBE02YY400001V1` (Eckgebäude Solmsstraße 29 / Bergmannstraße 93).
- Straßenfassade aus LoD2: Richtung 103,14° / 283,14°, Länge 20,9 m, Außennormale 193,14° (Süd-Südwest). Die Bergmannstraße verläuft also wie erwartet ungefähr West–Ost.
- **Testpunkte** (nördlicher Gehweg, südexponiert, Augenhöhe 1,2 m über DGM), gespeichert in `Tests/fixtures/turandot_points.json`:

| ID | Breite | Länge | Abstand zur Fassade | Position entlang Fassade |
|---|---|---|---|---|
| T1 | 52.48944828 | 13.39221455 | 1,5 m | 1,91 m |
| T2 | 52.48944653 | 13.39225923 | 1,0 m | 4,91 m |
| T3 | 52.48943778 | 13.39225589 | 2,0 m | 4,91 m |
| T4 | 52.48942902 | 13.39225254 | 3,0 m | 4,91 m |
| T5 | 52.48943398 | 13.39231490 | 1,5 m | 8,91 m |

Die Punkte wurden geometrisch aus der LoD2-Fassade abgeleitet (senkrecht zur Fassade versetzt). Ein Kontrollpunkt S1 auf dem gegenüberliegenden Südgehweg ist in `scripts/turandot_poc.py` definiert.

## 7. Konsequenzen und bekannte Einschränkungen

- Bündel-Lizenz unproblematisch (dl-de/zero-2-0). OSM-Daten werden **nicht** gebündelt, um ODbL-Share-Alike zu vermeiden.
- LoD2 ist nur als Bulk verfügbar. Aktualisierung erfordert eine Offline-Pipeline (ATOM-Feed auf `updated` prüfen, betroffene Kacheln neu verarbeiten).
- Nicht modelliert: Bäume (in der Bergmannstraße relevant!), Markisen, Schirme, Dachüberstände, Gauben, Gelände als Verdecker. Ergebnis gilt für „Sonne durch Gebäude unverdeckt“.
- Radius 500 m: Ein 25 m hohes Gebäude außerhalb des Radius kann den Punkt nur bei Elevation < ≈ 3° verschatten.
- Reproduktion: `python3 scripts/geodata_pipeline.py --download` (LoD2) bzw. `--source osm` (Fallback).
