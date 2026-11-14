// SpatialGridIndex.swift – uniformes 2D-Raster über Gebäude-AABBs + Amanatides-Woo-Traversierung entlang des Strahls.
//
// Warum kein R-Tree? Für ~1.300 Gebäude / 500 m Radius ist ein Raster mit 20-m-Zellen einfacher, cache-freundlich
// und liefert entlang eines Strahls direkt die Kandidaten in Distanzreihenfolge (Early-Exit möglich).
import Foundation

public struct SpatialGridIndex: Sendable {
    public let cellSize: Double
    public let minX: Double, minY: Double
    public let cols: Int, rows: Int
    private let cells: [[Int32]]

    public init(buildings: [Building], cellSize: Double = 20) {
        self.cellSize = cellSize
        let lo = buildings.reduce((Double.infinity, Double.infinity)) { (min($0.0, $1.bounds.min.x), min($0.1, $1.bounds.min.y)) }
        let hi = buildings.reduce((-Double.infinity, -Double.infinity)) { (max($0.0, $1.bounds.max.x), max($0.1, $1.bounds.max.y)) }
        minX = lo.0.isFinite ? lo.0 - cellSize : -cellSize
        minY = lo.1.isFinite ? lo.1 - cellSize : -cellSize
        cols = max(1, Int(ceil(((hi.0.isFinite ? hi.0 : 0) + cellSize - minX) / cellSize)))
        rows = max(1, Int(ceil(((hi.1.isFinite ? hi.1 : 0) + cellSize - minY) / cellSize)))
        var c = [[Int32]](repeating: [], count: cols * rows)
        for (i, b) in buildings.enumerated() {
            let c0 = Int(floor((b.bounds.min.x - minX) / cellSize)), c1 = Int(floor((b.bounds.max.x - minX) / cellSize))
            let r0 = Int(floor((b.bounds.min.y - minY) / cellSize)), r1 = Int(floor((b.bounds.max.y - minY) / cellSize))
            for r in max(0, r0)...min(rows - 1, r1) { for col in max(0, c0)...min(cols - 1, c1) { c[r * cols + col].append(Int32(i)) } }
        }
        cells = c
    }

    /// Gebäudeindizes aller Zellen, die das horizontale Strahlsegment [0, maxHorizontal] schneidet
    /// (Reihenfolge = Traversierungsreihenfolge, ohne Duplikate).
    public func candidates(originX: Double, originY: Double, dirX: Double, dirY: Double, maxHorizontal: Double) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int32>()
        var cx = Int(floor((originX - minX) / cellSize)), cy = Int(floor((originY - minY) / cellSize))
        let len = (dirX * dirX + dirY * dirY).squareRoot()
        func visit(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < cols, y < rows else { return }
            for i in cells[y * cols + x] where seen.insert(i).inserted { result.append(Int(i)) }
        }
        visit(cx, cy)
        guard len > 1e-12 else { return result } // Sonne im Zenit: nur Startzelle
        let dx = dirX / len, dy = dirY / len
        let stepX = dx > 0 ? 1 : -1, stepY = dy > 0 ? 1 : -1
        let nextBoundX = minX + Double(cx + (stepX > 0 ? 1 : 0)) * cellSize
        let nextBoundY = minY + Double(cy + (stepY > 0 ? 1 : 0)) * cellSize
        var tMaxX = abs(dx) > 1e-12 ? (nextBoundX - originX) / dx : .infinity
        var tMaxY = abs(dy) > 1e-12 ? (nextBoundY - originY) / dy : .infinity
        let tDeltaX = abs(dx) > 1e-12 ? cellSize / abs(dx) : .infinity
        let tDeltaY = abs(dy) > 1e-12 ? cellSize / abs(dy) : .infinity
        while min(tMaxX, tMaxY) <= maxHorizontal {
            if abs(tMaxX - tMaxY) < 1e-9 {
                // Strahl durch eine Zellecke: beide Nachbarzellen besuchen (kein "Corner Cutting")
                visit(cx + stepX, cy); visit(cx, cy + stepY)
                cx += stepX; cy += stepY; tMaxX += tDeltaX; tMaxY += tDeltaY
            } else if tMaxX < tMaxY { cx += stepX; tMaxX += tDeltaX } else { cy += stepY; tMaxY += tDeltaY }
            if cx < -1 || cy < -1 || cx > cols || cy > rows { break }
            visit(cx, cy)
        }
        return result
    }
}
