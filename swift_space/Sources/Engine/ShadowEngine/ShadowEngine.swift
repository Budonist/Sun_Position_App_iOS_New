// ShadowEngine.swift – Ray-Casting: Erreicht direkte Sonne einen Beobachterpunkt oder blockiert ein Gebäude?
//
// Algorithmus:
//  1. Beobachter P (WGS84 lat/lon + Höhe über Gelände, Default 1.2 m) → lokales ENU (Meter, N = wahr Nord).
//  2. Sonnenstand via SolarPositionCalculator (NREL SPA). Elevation ≤ 0° ⇒ `.night`.
//     Verwendet wird die refraktionskorrigierte (scheinbare) Elevation – das ist die Richtung, aus der Licht ankommt.
//  3. Strahl P + t·s, s = (sin A·cos e, cos A·cos e, sin e).
//  4. Maximale relevante Strahllänge: (höchster Gebäudepunkt − P.z) / sin e  (darüber kann nichts mehr blockieren).
//  5. Broad Phase: Rasterindex entlang der horizontalen Strahlprojektion → Kandidaten → Ray-AABB (Slab-Test).
//  6. Narrow Phase: Möller–Trumbore gegen alle Dreiecke der Kandidaten; nächster Treffer t > tMin gewinnt.
//  7. Treffer ⇒ `.buildingShadow` mit blockierendem Gebäude, sonst `.sun`.
//  Sonderfall: Beobachter innerhalb eines Footprints (unterhalb des Firsts) ⇒ `.insideBuilding` (keine Aussage).
//
// Bekannte Grenzen (MVP): keine Bäume/Vegetation, keine Markisen/Schirme, kein Gelände als Verdecker,
// Gebäude außerhalb des Store-Radius werden ignoriert (relevant erst bei Elevation < ~3°).
import Foundation

public enum ShadowStatus: Equatable, Sendable {
    case sun
    case buildingShadow(buildingIndex: Int, distance: Double)
    case night
    case insideBuilding(buildingIndex: Int)

    public var isSunny: Bool { self == .sun }
    public var label: String {
        switch self {
        case .sun: return "sun"
        case .buildingShadow: return "shadow"
        case .night: return "night"
        case .insideBuilding: return "inside_building"
        }
    }
}

public struct ShadowResult: Sendable {
    public let status: ShadowStatus
    public let solar: SolarPosition?
    public let observer: Vec3
    /// Blockierendes / umschließendes Gebäude (falls vorhanden).
    public let building: Building?
    public let hitPoint: Vec3?
}

public final class ShadowEngine: @unchecked Sendable {
    public let store: GeometryStore
    public let index: SpatialGridIndex
    public let atmosphere: Atmosphere
    private let maxTopZ: Double

    public init(store: GeometryStore, atmosphere: Atmosphere = .berlin, cellSize: Double = 20) {
        self.store = store
        self.atmosphere = atmosphere
        self.index = SpatialGridIndex(buildings: store.buildings, cellSize: cellSize)
        self.maxTopZ = store.buildings.map(\.bounds.max.z).max() ?? 0
    }

    /// Beobachterposition im ENU-System: Geländehöhe (DGM) + Augenhöhe.
    public func observerPosition(latitude: Double, longitude: Double, heightAboveGround: Double = 1.2) -> Vec3 {
        let p = store.frame.enu(lat: latitude, lon: longitude, h: store.frame.h0)
        let ground = store.terrain.height(e: p.x, n: p.y)
        return Vec3(p.x, p.y, p.z + ground + heightAboveGround)
    }

    /// Hauptfunktion: Sonne oder Schatten am Punkt (lat, lon) zum Zeitpunkt `date`.
    public func evaluate(latitude: Double, longitude: Double, date: Date, heightAboveGround: Double = 1.2) throws -> ShadowResult {
        let observer = observerPosition(latitude: latitude, longitude: longitude, heightAboveGround: heightAboveGround)
        let solar = try SolarPositionCalculator.position(for: date, latitude: latitude, longitude: longitude,
                                                         elevation: store.frame.h0, atmosphere: atmosphere)
        return evaluate(observer: observer, solar: solar)
    }

    /// Ray-Casting für einen ENU-Punkt und gegebenen Sonnenstand.
    public func evaluate(observer: Vec3, solar: SolarPosition) -> ShadowResult {
        if let inside = buildingContaining(observer) {
            return ShadowResult(status: .insideBuilding(buildingIndex: inside), solar: solar, observer: observer,
                                building: store.buildings[inside], hitPoint: nil)
        }
        guard solar.elevation > 0 else {
            return ShadowResult(status: .night, solar: solar, observer: observer, building: nil, hitPoint: nil)
        }
        let ray = Ray(origin: observer, direction: ShadowEngine.sunDirection(azimuth: solar.azimuth, elevation: solar.elevation))
        if let hit = firstHit(ray) {
            return ShadowResult(status: .buildingShadow(buildingIndex: hit.index, distance: hit.t), solar: solar,
                                observer: observer, building: store.buildings[hit.index], hitPoint: ray.point(at: hit.t))
        }
        return ShadowResult(status: .sun, solar: solar, observer: observer, building: nil, hitPoint: nil)
    }

    /// Einheitsvektor zur Sonne (ENU). Azimut ab wahr Nord im Uhrzeigersinn.
    public static func sunDirection(azimuth: Double, elevation: Double) -> Vec3 {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        return Vec3(sin(a) * cos(e), cos(a) * cos(e), sin(e))
    }

    /// Nächster Gebäudetreffer entlang des Strahls.
    public func firstHit(_ ray: Ray) -> (index: Int, t: Double)? {
        let dz = ray.direction.z
        let tLimit: Double = dz > 1e-9 ? max(0, (maxTopZ - ray.origin.z) / dz) + 1 : 2 * store.radius + 1000
        let horizontal = tLimit * (ray.direction.x * ray.direction.x + ray.direction.y * ray.direction.y).squareRoot()
        var best: (index: Int, t: Double)?
        for i in index.candidates(originX: ray.origin.x, originY: ray.origin.y, dirX: ray.direction.x,
                                  dirY: ray.direction.y, maxHorizontal: horizontal + index.cellSize) {
            let b = store.buildings[i]
            let tie = Tolerances.hitTieEpsilon
            guard let (tEnter, _) = Intersection.rayAABB(ray, b.bounds, tMax: best.map { $0.t + tie } ?? tLimit) else { continue }
            if let cur = best, tEnter > cur.t + tie { continue }
            for tri in b.triangles {
                guard let t = Intersection.rayTriangle(ray, tri) else { continue }
                // Deterministischer Tie-Break bei koinzidenten Flächen (z. B. Überdachung an Hauswand):
                // gleich weit (≤ hitTieEpsilon) ⇒ kleinerer Store-Index gewinnt – unabhängig von der Traversierungsreihenfolge.
                if let cur = best {
                    if t < cur.t - tie || (abs(t - cur.t) <= tie && i < cur.index) { best = (i, min(t, cur.t)) }
                } else { best = (i, t) }
            }
        }
        return best
    }

    /// Index des Gebäudes, dessen Footprint den Punkt (mit > insideEpsilon Abstand zur Kante) enthält
    /// und dessen First über dem Punkt liegt.
    public func buildingContaining(_ p: Vec3) -> Int? {
        for i in index.candidates(originX: p.x, originY: p.y, dirX: 0, dirY: 0, maxHorizontal: 0) {
            let b = store.buildings[i]
            guard p.x >= b.bounds.min.x, p.x <= b.bounds.max.x, p.y >= b.bounds.min.y, p.y <= b.bounds.max.y,
                  p.z <= b.bounds.max.z else { continue }
            for fp in b.footprints where Polygon2D.contains(fp, x: p.x, y: p.y) {
                if Polygon2D.distanceToBoundary(fp, x: p.x, y: p.y) > Tolerances.insideEpsilon { return i }
            }
        }
        return nil
    }
}
