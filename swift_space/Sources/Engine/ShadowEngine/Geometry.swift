// Geometry.swift – minimale 3D-Primitive (plattformunabhängig, ohne simd für Linux-Kompatibilität).
import Foundation

/// 3D-Vektor im lokalen ENU-System (x = Ost, y = Nord (wahr), z = Oben), Meter.
public struct Vec3: Equatable, Sendable, CustomStringConvertible {
    public var x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vec3(0, 0, 0)

    @inline(__always) public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inline(__always) public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inline(__always) public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    @inline(__always) public func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    @inline(__always) public func cross(_ b: Vec3) -> Vec3 {
        Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
    public var description: String { String(format: "(%.3f, %.3f, %.3f)", x, y, z) }
}

public struct Ray: Sendable {
    public let origin: Vec3
    /// Einheitsvektor
    public let direction: Vec3
    public init(origin: Vec3, direction: Vec3) { self.origin = origin; self.direction = direction.normalized }
    public func point(at t: Double) -> Vec3 { origin + direction * t }
}

public struct Triangle: Sendable, Equatable {
    public let a: Vec3, b: Vec3, c: Vec3
    public init(_ a: Vec3, _ b: Vec3, _ c: Vec3) { self.a = a; self.b = b; self.c = c }
}

public struct AABB: Sendable, Equatable {
    public var min: Vec3, max: Vec3
    public init(min: Vec3, max: Vec3) { self.min = min; self.max = max }
    public init(triangles: [Triangle]) {
        var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
        for t in triangles {
            for p in [t.a, t.b, t.c] {
                lo = Vec3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = Vec3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
        }
        self.min = lo; self.max = hi
    }
}

/// Numerische Toleranzen der Shadow Engine (identisch in scripts/sonnen_common.py).
public enum Tolerances {
    /// Strahl beginnt erst bei t = 1 cm: verhindert Selbstschnitt mit einer Fassade, an der der Beobachter steht.
    public static let rayTMin = 0.01
    /// Möller–Trumbore: |Determinante| darunter ⇒ Strahl (nahezu) parallel zur Dreiecksebene ⇒ kein Treffer.
    public static let determinantEpsilon = 1e-12
    /// Barycentrische Toleranz: Kanten zählen als Treffer (inklusive), damit zwischen benachbarten Dreiecken keine Lücke
    /// entsteht. Folge: Ein Strahl, der eine Gebäudekante exakt trifft, gilt als blockiert (konservativ → Schatten).
    public static let barycentricEpsilon = 1e-9
    /// Punkt-in-Gebäude: liegt der Beobachter weniger als 1 cm von einer Footprint-Kante entfernt, gilt er als außen.
    public static let insideEpsilon = 0.01
    /// AABB-Slab-Test: Boxen werden um 1 mm aufgeweitet, damit achsparallele Flächen nicht durch Rundung herausfallen.
    public static let aabbPadding = 0.001
    /// Zwei Treffer gelten als gleich weit, wenn sie ≤ 1 mm auseinanderliegen (koinzidente Flächen benachbarter
    /// LoD2-Objekte). Dann gewinnt deterministisch das Gebäude mit dem kleineren Store-Index.
    public static let hitTieEpsilon = 0.001
}

public enum Intersection {
    /// Möller–Trumbore Ray-Triangle-Schnitt (Möller & Trumbore 1997).
    /// - Returns: Strahlparameter t (Meter entlang des Einheitsstrahls) oder `nil`.
    @inline(__always)
    public static func rayTriangle(_ ray: Ray, _ tri: Triangle, tMin: Double = Tolerances.rayTMin) -> Double? {
        let e1 = tri.b - tri.a
        let e2 = tri.c - tri.a
        let p = ray.direction.cross(e2)
        let det = e1.dot(p)
        if abs(det) < Tolerances.determinantEpsilon { return nil }
        let inv = 1.0 / det
        let s = ray.origin - tri.a
        let u = s.dot(p) * inv
        if u < -Tolerances.barycentricEpsilon || u > 1 + Tolerances.barycentricEpsilon { return nil }
        let q = s.cross(e1)
        let v = ray.direction.dot(q) * inv
        if v < -Tolerances.barycentricEpsilon || u + v > 1 + Tolerances.barycentricEpsilon { return nil }
        let t = e2.dot(q) * inv
        return t >= tMin ? t : nil
    }

    /// Slab-Test (Kay & Kajiya). Liefert (tEnter, tExit), falls der Strahl die Box im Intervall [0, tMax] trifft.
    @inline(__always)
    public static func rayAABB(_ ray: Ray, _ box: AABB, tMax: Double = .infinity) -> (Double, Double)? {
        var t0 = 0.0, t1 = tMax
        let pad = Tolerances.aabbPadding
        @inline(__always) func slab(_ o: Double, _ d: Double, _ lo: Double, _ hi: Double) -> Bool {
            if abs(d) < 1e-15 { return o >= lo - pad && o <= hi + pad }
            let inv = 1.0 / d
            var tn = (lo - pad - o) * inv, tf = (hi + pad - o) * inv
            if tn > tf { swap(&tn, &tf) }
            t0 = Swift.max(t0, tn); t1 = Swift.min(t1, tf)
            return t0 <= t1
        }
        guard slab(ray.origin.x, ray.direction.x, box.min.x, box.max.x),
              slab(ray.origin.y, ray.direction.y, box.min.y, box.max.y),
              slab(ray.origin.z, ray.direction.z, box.min.z, box.max.z) else { return nil }
        return (t0, t1)
    }
}

/// 2D-Polygon-Hilfsfunktionen (Footprints, Ost/Nord).
public enum Polygon2D {
    /// Ray-Crossing-Test (gerade/ungerade Regel).
    public static func contains(_ poly: [(Double, Double)], x: Double, y: Double) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (xi, yi) = poly[i], (xj, yj) = poly[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    public static func distanceToBoundary(_ poly: [(Double, Double)], x: Double, y: Double) -> Double {
        var best = Double.infinity
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (ax, ay) = poly[j], (bx, by) = poly[i]
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / len2)) : 0
            let px = ax + t * dx - x, py = ay + t * dy - y
            best = min(best, (px * px + py * py).squareRoot())
            j = i
        }
        return best
    }
}

/// WGS84 → lokales ENU (identische Formeln wie scripts/sonnen_common.py `ENUFrame`).
public struct ENUFrame: Sendable {
    public static let a = 6378137.0
    public static let f = 1.0 / 298.257223563
    public static let e2 = f * (2.0 - f)

    public let lat0: Double, lon0: Double, h0: Double
    private let origin: Vec3
    private let r: [[Double]]

    public init(lat0: Double, lon0: Double, h0: Double) {
        self.lat0 = lat0; self.lon0 = lon0; self.h0 = h0
        origin = ENUFrame.ecef(lat: lat0, lon: lon0, h: h0)
        let la = lat0 * .pi / 180, lo = lon0 * .pi / 180
        r = [[-sin(lo), cos(lo), 0],
             [-sin(la) * cos(lo), -sin(la) * sin(lo), cos(la)],
             [cos(la) * cos(lo), cos(la) * sin(lo), sin(la)]]
    }

    public static func ecef(lat: Double, lon: Double, h: Double) -> Vec3 {
        let la = lat * .pi / 180, lo = lon * .pi / 180
        let n = a / (1 - e2 * sin(la) * sin(la)).squareRoot()
        return Vec3((n + h) * cos(la) * cos(lo), (n + h) * cos(la) * sin(lo), (n * (1 - e2) + h) * sin(la))
    }

    public func enu(lat: Double, lon: Double, h: Double) -> Vec3 {
        let d = ENUFrame.ecef(lat: lat, lon: lon, h: h) - origin
        return Vec3(r[0][0] * d.x + r[0][1] * d.y + r[0][2] * d.z,
                    r[1][0] * d.x + r[1][1] * d.y + r[1][2] * d.z,
                    r[2][0] * d.x + r[2][1] * d.y + r[2][2] * d.z)
    }
}
