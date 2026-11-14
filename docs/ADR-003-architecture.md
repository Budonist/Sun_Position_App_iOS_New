# ADR-003: Architektur – On-Device vs. Backend

| | |
|---|---|
| **Status** | Angenommen für MVP (PLZ 10961) |
| **Datum** | 18.10.2026 |
| **Bezug** | ADR-001 (Geodaten), ADR-002 (SPA) |

## 1. Kontext

Die App beantwortet für einen Punkt und eine Zeit, ob direkte Sonne ankommt. Typische Nutzung:

- Tagesverlauf für einen Tisch: 288 Abfragen à 5 min.
- Karte mit Sonnen-/Schattenfarbe für viele Punkte.
- „Wo ist jetzt Sonne?“ in der Umgebung.

Rahmenbedingungen:

- LoD2 gibt es **nur als Bulk-Download** (CityGML-Kacheln, kein LoD2-WFS, siehe ADR-001). Rohdaten sind für die App zu groß (4 Kacheln = 144,5 MB XML) und müssen vorverarbeitet werden.
- Nutzung draußen, oft mit schlechtem Netz (Biergarten, Hinterhof).
- MVP-Gebiet: PLZ 10961 (Kreuzberg, Bergmannkiez). Fläche ≈ 1,44 km² laut suche-postleitzahl.org (Stand 12/2025).

## 2. Messwerte aus dem PoC (Grundlage der Schätzung)

| Messgröße | Wert | Quelle |
|---|---|---|
| Store 500-m-Kreis um Turandot (0,785 km²) | 1330 Gebäude, 67 331 Dreiecke | `data/processed/turandot_buildings.json` |
| Größe JSON / gzip | 5,6 MB / 0,85 MB | `ls`, `gzip -c \| wc -c` |
| Ladezeit Store (JSON-Decode + Gitterindex) | ≈ 0,3 s | `shadow-cli batch`, Release, Linux x86-64 |
| Schattenabfrage inkl. SPA | ≈ 120 µs | `shadow-cli batch`, Release, Linux x86-64 |
| Kreuzvalidierung Swift vs. Python | 3080/3080 identisch | `scripts/shadow_validation.py` |

Auf einem iPhone (ARM, Release) wurde **noch nicht** gemessen. Erwartung: gleiche Größenordnung, denn der Code ist reine Double-Arithmetik ohne Abhängigkeiten. Die Messung folgt in Phase 5.

## 3. Datenmengen-Schätzung für PLZ 10961

Schattenwerfer können außerhalb der PLZ stehen. Deshalb rechnen wir mit der PLZ-Fläche plus einem Rand von 300 m. Ein 25 m hohes Gebäude in 300 m Abstand verschattet erst unter ≈ 4,8° Elevation.

| Größe | Annahme | Ergebnis (Schätzung) |
|---|---|---|
| Abgedeckte Fläche | PLZ ≈ 1,44 km², vereinfacht als Quadrat ≈ 1,2 × 1,2 km, plus 300 m Rand ⇒ 1,8 × 1,8 km | ≈ 3,2 km² ≈ 4,1 × PoC-Kreis |
| Gebäude | Dichte wie im PoC-Kreis (≈ 1700 /km²) | ≈ 5 500 |
| Dreiecke | ≈ 86 000 /km² | ≈ 280 000 |
| JSON (PoC-Format) | 7,1 MB/km² | **≈ 23 MB** |
| JSON gzip | 1,1 MB/km² | **≈ 3,5 MB** |
| Binärformat (Float32-Vertices, indizierte Dreiecke, Metadaten) | ≈ 36 B/Dreieck unindiziert, ≈ 50 % mit Indizes | **≈ 5–10 MB**, komprimiert ≈ 2–4 MB |
| Nur PLZ ohne Rand | 1,44 km² | ≈ 10 MB JSON |

Damit liegt der MVP klar im erwarteten Bereich von **5–50 MB nach Preprocessing**. Zum Vergleich ganz Berlin (≈ 892 km², davon großer Anteil unbebaut): grob 1–3 GB im Binärformat. Das ist für On-Device nur kachelweise nachladbar möglich, nicht als Bündel.

Unsicherheit: Der PoC-Kreis enthält Teile von Viktoriapark und Friedhöfen und ist daher eher dünner bebaut als der Kiez-Kern. Die Schätzung kann um ±30 % abweichen.

## 4. Optionen

### Option A – Komplett on-device

Vorverarbeiteter Geometry-Store (Binär, ENU-Kacheln) wird mit der App gebündelt. SPA und Ray-Casting laufen lokal.

- **Pro:** offline, keine Latenz (≈ 0,1 ms/Abfrage ⇒ Tagesverlauf < 50 ms, interaktives Zeit-Scrubbing in Echtzeit), keine Serverkosten, Datenschutz (Standort verlässt das Gerät nicht), schon im PoC als Swift Package umgesetzt.
- **Contra:** App-Größe wächst mit dem Gebiet; Datenaktualisierung nur per App-Update oder Asset-Download; jede Stadt braucht eine Offline-Pipeline.

### Option B – Hybrid

Engine on-device, Geometrie-Kacheln (z. B. 500 × 500 m, Binär, gzip) werden von einem statischen CDN geladen und gecacht. Ein Backend-Job erzeugt die Kacheln aus den ATOM-Feeds (Python-Pipeline aus Phase 2).

- **Pro:** kleine App, skaliert auf ganz Berlin bzw. andere Städte, Aktualisierung ohne App-Release, rechnet nach dem ersten Laden offline weiter.
- **Contra:** erste Nutzung braucht Netz; Kachelverwaltung, Cache-Invalidierung und Versionierung; CDN-Betrieb (geringe Kosten, da statisch).

### Option C – Server

App sendet Standort und Zeit, Server rechnet und antwortet.

- **Pro:** minimale App, zentrale Datenhaltung, einfache Aktualisierung.
- **Contra:** ohne Netz nutzlos; Latenz 100–500 ms pro Anfrage macht Zeit-Scrubbing zäh; Serverkosten skalieren mit Nutzern; Standortdaten verlassen das Gerät (DSGVO-Aufwand); Engine liegt ohnehin schon in Swift vor.

### Bewertung (1 = schlecht, 5 = gut)

| Kriterium | Gewicht | A on-device | B Hybrid | C Server |
|---|---|---|---|---|
| Offline-Fähigkeit | 3 | 5 | 4 | 1 |
| Interaktivität/Latenz | 3 | 5 | 5 | 2 |
| Skalierung auf weitere Gebiete | 2 | 2 | 5 | 5 |
| App-Größe | 1 | 3 (MVP 5–10 MB) | 5 | 5 |
| Betriebsaufwand/Kosten | 2 | 5 | 4 | 2 |
| Datenschutz | 2 | 5 | 5 | 2 |
| Aufwand bis MVP | 3 | 5 | 3 | 3 |
| **Gewichtete Summe** (max. 80) | | **72** | **69** | **41** |

Rechnung: A = 3·5 + 3·5 + 2·2 + 1·3 + 2·5 + 2·5 + 3·5 = 72; B = 3·4 + 3·5 + 2·5 + 1·5 + 2·4 + 2·5 + 3·3 = 69; C = 3·1 + 3·2 + 2·5 + 1·5 + 2·2 + 2·2 + 3·3 = 41. A und B liegen nah beieinander. Den Ausschlag gibt der Aufwand bis zum MVP, deshalb wird B als Ausbaustufe geplant (Abschnitt 5).

## 5. Entscheidung

**MVP: Option A – on-device mit vorverarbeitetem, lokal gebündeltem Geometry-Store für PLZ 10961 (+300 m Rand).** Die Architektur wird so geschnitten, dass der Übergang zu Option B ohne Engine-Änderung möglich ist:

1. **Store-Format:** Der PoC nutzt JSON (5,6 MB, 0,3 s Ladezeit). Für das MVP kommt ein Binärformat mit Kacheln zu 500 × 500 m in einem gemeinsamen ENU-Ursprung pro Kachelset. Kopf mit Datenstand (ATOM-`updated`), Lizenzvermerk dl-de/zero-2-0 und Confidence pro Gebäude. Ziel: ≤ 10 MB gebündelt, Ladezeit < 0,1 s per Memory-Mapping.
2. **Store-Abstraktion:** Heute ist `GeometryStore` ein konkreter Typ, der aus JSON lädt. Die Engine greift aber nur über `SpatialGridIndex` und die Gebäudeliste darauf zu. In Phase 5 wird daraus ein Protokoll mit zwei Implementierungen: gebündelt (A) und CDN-Kachel-Cache (B). Die Ray-Casting-Logik ändert sich dabei nicht.
3. **Fallback außerhalb des gebündelten Gebiets:** Online-Abfrage der WFS-Dienste `https://gdi.berlin.de/services/wfs/ua_gebaeudehoehen` (Höhe) und `https://gdi.berlin.de/services/wfs/alkis_gebaeude` (Grundriss, Geschosse). Daraus wird on-device eine LoD1-Flachdach-Extrusion mit Confidence `medium` gebaut (ADR-001, Abschnitt 5). Ohne Netz und außerhalb des Gebiets lautet die Antwort „keine Gebäudedaten“, nicht „Sonne“.
4. **Preprocessing bleibt offline in Python** (`scripts/geodata_pipeline.py`). Dieselbe Pipeline erzeugt später die CDN-Kacheln für Option B.
5. **Wechsel zu B**, sobald mehr als ≈ 3 PLZ-Gebiete oder > 30 MB Geometrie gebündelt würden.

## 6. Konsequenzen

- Die Swift Packages `SolarEngine` und `ShadowEngine` werden unverändert in die iOS-App eingebunden. UI erst ab Phase 5.
- App-Bundle wächst um ≈ 5–10 MB (Schätzung, Abschnitt 3).
- Datenaktualisierung im MVP per App-Update. LoD2 Berlin wird etwa jährlich aktualisiert (letzter Stand 24.03.2026), das reicht.
- Offene Messungen für Phase 5: Lade- und Abfragezeit auf iPhone-Hardware, Speicherbedarf des Index, Größe des Binärformats.
