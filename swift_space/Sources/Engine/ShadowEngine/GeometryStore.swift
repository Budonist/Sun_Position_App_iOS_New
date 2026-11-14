// GeometryStore.swift – vorverarbeiteter, lokal gebündelter Gebäude-Store (Format: scripts/geodata_pipeline.py).
import Foundation

/// Ein Gebäude (LoD2-Building inkl. BuildingParts) im lokalen ENU-System.
public struct Building: Sendable {
    public let id: String
    public let functionName: String
    public let labels: [String]
    /// "high" (amtliches LoD2), "medium"/"low"/"very_low" (OSM-Fallback)
    public let confidence: String
    public let groundZ: Double
    public let eaveZ: Double
    public let ridgeZ: Double
    public let footprints: [[(Double, Double)]]
    public let triangles: [Triangle]
    public let bounds: AABB

    public init(id: String, functionName: String = "", labels: [String] = [], confidence: String = "high",
                footprints: [[(Double, Double)]], triangles: [Triangle]) {
        self.id = id; self.functionName = functionName; self.labels = labels; self.confidence = confidence
        self.footprints = footprints; self.triangles = triangles
        self.bounds = AABB(triangles: triangles)
        self.groundZ = bounds.min.z; self.eaveZ = bounds.max.z; self.ridgeZ = bounds.max.z
    }

    init(dto: BuildingDTO) {
        id = dto.id; functionName = dto.function_name ?? ""; labels = dto.labels; confidence = dto.confidence
        groundZ = dto.ground_z; eaveZ = dto.eave_z; ridgeZ = dto.ridge_z
        footprints = dto.footprints.map { ring in ring.map { ($0[0], $0[1]) } }
        var tris: [Triangle] = []
        tris.reserveCapacity(dto.triangles.count / 9)
        let t = dto.triangles
        var i = 0
        while i + 8 < t.count {
            tris.append(Triangle(Vec3(t[i], t[i + 1], t[i + 2]), Vec3(t[i + 3], t[i + 4], t[i + 5]), Vec3(t[i + 6], t[i + 7], t[i + 8])))
            i += 9
        }
        triangles = tris
        bounds = AABB(min: Vec3(dto.aabb[0], dto.aabb[1], dto.aabb[2]), max: Vec3(dto.aabb[3], dto.aabb[4], dto.aabb[5]))
    }

    /// Lesbarer Name für Ausgaben ("Bergmannstraße 16 (Wohnhaus)").
    public var displayName: String {
        let addr = labels.first { $0.range(of: #"^\D+ \d+\w*$"#, options: .regularExpression) != nil } ?? labels.first
        return addr.map { "\($0) (\(functionName))" } ?? "\(id) (\(functionName))"
    }
}

/// Regelmäßiges Gelände-Raster (Höhe relativ zu h0).
public struct TerrainGrid: Sendable {
    public let originE: Double, originN: Double, cellSize: Double
    public let cols: Int, rows: Int
    public let heights: [Double]

    public init(originE: Double, originN: Double, cellSize: Double, cols: Int, rows: Int, heights: [Double]) {
        self.originE = originE; self.originN = originN; self.cellSize = cellSize
        self.cols = cols; self.rows = rows; self.heights = heights
    }

    public static func flat(halfExtent: Double = 1000) -> TerrainGrid {
        TerrainGrid(originE: -halfExtent, originN: -halfExtent, cellSize: 2 * halfExtent, cols: 2, rows: 2, heights: [0, 0, 0, 0])
    }

    /// Bilineare Interpolation; außerhalb wird auf den Rand geklemmt.
    public func height(e: Double, n: Double) -> Double {
        let x = (e - originE) / cellSize, y = (n - originN) / cellSize
        let x0 = max(0, min(cols - 2, Int(floor(x)))), y0 = max(0, min(rows - 2, Int(floor(y))))
        let fx = max(0, min(1, x - Double(x0))), fy = max(0, min(1, y - Double(y0)))
        let h = { (c: Int, r: Int) in self.heights[r * self.cols + c] }
        return h(x0, y0) * (1 - fx) * (1 - fy) + h(x0 + 1, y0) * fx * (1 - fy) +
            h(x0, y0 + 1) * (1 - fx) * fy + h(x0 + 1, y0 + 1) * fx * fy
    }
}

public struct GeometryStore: Sendable {
    public let frame: ENUFrame
    public let radius: Double
    public let buildings: [Building]
    public let terrain: TerrainGrid

    public init(frame: ENUFrame, radius: Double, buildings: [Building], terrain: TerrainGrid) {
        self.frame = frame; self.radius = radius; self.buildings = buildings; self.terrain = terrain
    }

    public static func load(from data: Data) throws -> GeometryStore {
        let dto = try JSONDecoder().decode(StoreDTO.self, from: data)
        return GeometryStore(frame: ENUFrame(lat0: dto.origin.lat, lon0: dto.origin.lon, h0: dto.origin.h0_nhn),
                             radius: dto.radius_m,
                             buildings: dto.buildings.map(Building.init(dto:)),
                             terrain: TerrainGrid(originE: dto.terrain.origin_e, originN: dto.terrain.origin_n, cellSize: dto.terrain.cell_size,
                                                  cols: dto.terrain.cols, rows: dto.terrain.rows, heights: dto.terrain.heights))
    }

    public static func load(from url: URL) throws -> GeometryStore {
        let data = try Data(contentsOf: url)
        let dto = try JSONDecoder().decode(StoreDTO.self, from: data)
        let t = dto.terrain
        return GeometryStore(frame: ENUFrame(lat0: dto.origin.lat, lon0: dto.origin.lon, h0: dto.origin.h0_nhn),
                             radius: dto.radius_m,
                             buildings: dto.buildings.map(Building.init(dto:)),
                             terrain: TerrainGrid(originE: t.origin_e, originN: t.origin_n, cellSize: t.cell_size,
                                                  cols: t.cols, rows: t.rows, heights: t.heights))
    }
}

// MARK: - JSON-DTOs (snake_case wie im Python-Output)

struct StoreDTO: Decodable {
    struct Origin: Decodable { let lat: Double; let lon: Double; let h0_nhn: Double }
    struct Terrain: Decodable {
        let origin_e: Double, origin_n: Double, cell_size: Double
        let cols: Int, rows: Int
        let heights: [Double]
    }
    let schema_version: Int
    let origin: Origin
    let radius_m: Double
    let terrain: Terrain
    let buildings: [BuildingDTO]
}

struct BuildingDTO: Decodable {
    let id: String
    let function_name: String?
    let confidence: String
    let ground_z: Double, eave_z: Double, ridge_z: Double
    let footprints: [[[Double]]]
    let aabb: [Double]
    let triangles: [Double]
    let labels: [String]
}
