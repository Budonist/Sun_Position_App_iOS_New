# Datenlizenzen und Nachweise

Diese App verwendet amtliche und offene Geodaten. Die folgenden Nachweise sind
verpflichtend und dürfen nicht entfernt werden.

## 1. Berliner LoD2-Gebäudemodell und DGM1-Geländemodell

- **Herausgeber:** Senatsverwaltung für Stadtentwicklung, Bauen und Wohnen Berlin
  (Geoportal Berlin / FIS-Broker).
- **Lizenz:** Datenlizenz Deutschland – Zero – 2.0
  (https://www.govdata.de/dl-de/zero-2-0)
- **Verwendung:** 3D-Gebäudegeometrie (Grundriss, Trauf-/Firsthöhe, Dachform) und
  Geländehöhe als Grundlage der Schattenberechnung für PLZ 10961.
- **Hinweis:** „Datenlizenz Deutschland – Zero – 2.0“ erlaubt die Nutzung ohne
  Namensnennungspflicht; die Quelle wird dennoch aus Transparenzgründen genannt.

## 2. OpenStreetMap

- **Herausgeber:** © OpenStreetMap-Mitwirkende.
- **Lizenz:** Open Database License (ODbL) 1.0
  (https://www.openstreetmap.org/copyright)
- **Verwendung:** Verifizierung der Turandot-Referenzkoordinate,
  Adressbeschriftungen und ein OSM-API-Kartenausschnitt als gekennzeichneter
  Fallback-Datensatz (nur wenn amtliche Daten nicht vorliegen).

## 3. Apple MapKit

- Die Kartendarstellung erfolgt über Apple MapKit und unterliegt den
  Apple-Nutzungsbedingungen. Die Berechnung selbst nutzt ausschließlich die oben
  genannten Geodaten, nicht MapKit.

## Koordinatenreferenz

Rohdaten in EPSG:25833 (ETRS89 / UTM Zone 33N) + Höhenbezug DHHN2016 werden nach
WGS84 und in ein lokales ENU-System (Meter, Nordachse = geografisch Nord)
transformiert. Details: `docs/ADR-001-geodata-sources.md`.