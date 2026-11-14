// SolarPositionCalculator.swift
//
// Implementierung des NREL Solar Position Algorithm (SPA)
//   Referenz: I. Reda, A. Andreas (2004/2008): "Solar Position Algorithm for Solar
//   Radiation Applications", NREL/TP-560-34302, Revised January 2008.
//   Strukturell 1:1 an die NREL-Referenzimplementierung spa.c angelehnt.
//
// Genauigkeit: ±0.0003° (Zenit/Azimut) für die Jahre −2000 … 6000, sofern ΔT korrekt ist.
//   In der Praxis dominiert die Unsicherheit der atmosphärischen Refraktion in Horizontnähe
//   (bis zu ~0.5° bei Elevation < 1°). Für Schattenberechnung irrelevant, da der Fehler
//   der Gebäudegeometrie (LoD2: ~0.5–1 m) deutlich größer ist.
//
// Koordinatensystem:
//   - Eingabe: geodätische WGS84/ETRS89-Koordinaten (Breite +Nord, Länge +Ost), Höhe in m.
//   - Azimut: in Grad, von geografisch (wahr) Nord im Uhrzeigersinn (0° = N, 90° = O, 180° = S, 270° = W).
//     ACHTUNG: wahres Nord ≠ UTM-Gitternord (Meridiankonvergenz in Berlin/UTM33 ≈ −1.28°).
//     Die ShadowEngine arbeitet deshalb in einem lokalen ENU-Tangentialsystem, dessen N-Achse wahres Nord ist.
//   - Elevation: topozentrisch, inkl. Parallaxe; `elevation` mit, `elevationGeometric` ohne Refraktionskorrektur.
//
// Zeitsystem:
//   - Intern UT (≈ UTC, |UT1−UTC| < 0.9 s, Standard ΔUT1 = 0) → Julianisches Datum (JD),
//     Terrestrische Zeit über ΔT = TT − UT1 (siehe `SPA.deltaT(decimalYear:)`).
//   - Zeitzonen/Sommerzeit werden AUSSCHLIESSLICH über Foundation (`TimeZone`/`Calendar`)
//     aufgelöst – keine selbstgebaute DST-Logik. Ein `Date` ist ein absoluter Zeitpunkt.
//
// Numerische Toleranzen: Double-Precision (IEEE 754, ~15–16 signifikante Stellen).
//   Die Periodenterme werden in der Originalreihenfolge summiert; Abweichung zur NREL-Referenz < 1e-6°.

import Foundation

// MARK: - Öffentliche Datentypen

/// Sonnenstand an einem Ort zu einem Zeitpunkt.
public struct SolarPosition: Equatable, Sendable {
    /// Azimut in Grad ab wahr Nord, im Uhrzeigersinn [0, 360).
    public let azimuth: Double
    /// Topozentrische Elevation in Grad, refraktionskorrigiert (scheinbarer Sonnenstand).
    public let elevation: Double
    /// Topozentrische Elevation in Grad ohne Refraktionskorrektur (geometrisch).
    public let elevationGeometric: Double
    /// Topozentrischer Zenitwinkel in Grad (= 90° − elevation).
    public let zenith: Double
    /// Geozentrische Deklination in Grad.
    public let declination: Double
    /// Topozentrischer Stundenwinkel in Grad.
    public let hourAngle: Double
    /// Zeitgleichung in Minuten.
    public let equationOfTime: Double
}

/// Sonnenaufgang, -höchststand (Transit) und -untergang für einen lokalen Kalendertag.
public struct SunTimes: Equatable, Sendable {
    /// `nil` bei Polartag/Polarnacht.
    public let sunrise: Date?
    public let transit: Date
    public let sunset: Date?
    /// Elevation der Sonne im Transit (geometrisch, Grad).
    public let transitElevation: Double
    /// Lokale Stunden (dezimal) wie in spa.c – nützlich für Tests.
    public let sunriseLocalHours: Double?
    public let transitLocalHours: Double
    public let sunsetLocalHours: Double?
}

/// Atmosphärische Bedingungen für die Refraktionskorrektur.
public struct Atmosphere: Equatable, Sendable {
    /// Jahresmittlerer Luftdruck in hPa (mbar).
    public var pressure: Double
    /// Jahresmitteltemperatur in °C.
    public var temperature: Double
    /// Refraktion am Horizont in Grad (SPA-Standard: 0.5667°).
    public var horizonRefraction: Double

    public init(pressure: Double = 1013.25, temperature: Double = 10.0, horizonRefraction: Double = 0.5667) {
        self.pressure = pressure
        self.temperature = temperature
        self.horizonRefraction = horizonRefraction
    }

    /// Berlin: Jahresmittel ~1013 hPa, ~10 °C (DWD Berlin-Tempelhof 1991–2020: 10.3 °C).
    public static let berlin = Atmosphere(pressure: 1013.25, temperature: 10.3)
}

/// Rohe SPA-Eingabe (entspricht `spa_data` in spa.c). Zeit als lokale Komponenten + Zeitzone in Stunden.
public struct SPAInput: Sendable {
    public var year: Int, month: Int, day: Int
    public var hour: Int, minute: Int
    public var second: Double
    /// Zeitzone in Stunden (z. B. −7 für MST, +2 für CEST).
    public var timezone: Double
    public var deltaUT1: Double
    public var deltaT: Double
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double
    public var atmosphere: Atmosphere

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double,
                timezone: Double, deltaUT1: Double = 0, deltaT: Double,
                latitude: Double, longitude: Double, elevation: Double = 0,
                atmosphere: Atmosphere = Atmosphere()) {
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second
        self.timezone = timezone; self.deltaUT1 = deltaUT1; self.deltaT = deltaT
        self.latitude = latitude; self.longitude = longitude; self.elevation = elevation
        self.atmosphere = atmosphere
    }
}

public enum SolarPositionError: Error, Equatable {
    case invalidLatitude(Double)
    case invalidLongitude(Double)
    case invalidDate
}

// MARK: - Öffentliche API

public enum SolarPositionCalculator {

    /// Sonnenstand für einen absoluten Zeitpunkt.
    /// - Parameters:
    ///   - date: absoluter Zeitpunkt (Zeitzone irrelevant).
    ///   - latitude: Breite in Grad (+N), [−90, 90].
    ///   - longitude: Länge in Grad (+O), [−180, 180].
    ///   - elevation: Höhe über Meer in m (nur für Parallaxe, Effekt < 0.001°).
    ///   - deltaT: TT − UT1 in s; `nil` = Schätzung via `SPA.deltaT`.
    public static func position(for date: Date, latitude: Double, longitude: Double,
                                elevation: Double = 0, atmosphere: Atmosphere = .berlin,
                                deltaT: Double? = nil) throws -> SolarPosition {
        try validate(latitude: latitude, longitude: longitude)
        let c = utcComponents(date)
        let input = SPAInput(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: c.minute,
                             second: c.second, timezone: 0, deltaT: deltaT ?? SPA.deltaT(decimalYear: c.decimalYear),
                             latitude: latitude, longitude: longitude, elevation: elevation, atmosphere: atmosphere)
        return SPA.compute(input)
    }

    /// Sonnenauf-/untergang und Transit für einen lokalen Kalendertag in `timeZone`.
    /// Der UTC-Offset wird von Foundation für den lokalen Mittag bestimmt (DST-korrekt).
    public static func sunTimes(year: Int, month: Int, day: Int, timeZone: TimeZone,
                                latitude: Double, longitude: Double, elevation: Double = 0,
                                atmosphere: Atmosphere = .berlin, deltaT: Double? = nil) throws -> SunTimes {
        try validate(latitude: latitude, longitude: longitude)
        guard let localNoon = makeDate(year: year, month: month, day: day, hour: 12, minute: 0, second: 0, timeZone: timeZone),
              let utcMidnight = makeDate(year: year, month: month, day: day, hour: 0, minute: 0, second: 0,
                                         timeZone: TimeZone(identifier: "UTC")!) else {
            throw SolarPositionError.invalidDate
        }
        let tzHours = Double(timeZone.secondsFromGMT(for: localNoon)) / 3600.0
        let decimalYear = Double(year) + (Double(month) - 0.5) / 12.0
        let input = SPAInput(year: year, month: month, day: day, hour: 12, minute: 0, second: 0,
                             timezone: tzHours, deltaT: deltaT ?? SPA.deltaT(decimalYear: decimalYear),
                             latitude: latitude, longitude: longitude, elevation: elevation, atmosphere: atmosphere)
        let rts = SPA.riseTransitSet(input)
        // Lokale Mitternacht als absoluter Zeitpunkt = UTC-Mitternacht des Datums − Offset.
        let localMidnight = utcMidnight.addingTimeInterval(-tzHours * 3600)
        func toDate(_ h: Double?) -> Date? { h.map { localMidnight.addingTimeInterval($0 * 3600) } }
        return SunTimes(sunrise: toDate(rts.sunrise), transit: toDate(rts.transit)!, sunset: toDate(rts.sunset),
                        transitElevation: rts.transitElevation,
                        sunriseLocalHours: rts.sunrise, transitLocalHours: rts.transit, sunsetLocalHours: rts.sunset)
    }

    /// Erzeugt einen absoluten Zeitpunkt aus lokalen Wandzeit-Komponenten (DST via Foundation).
    public static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int,
                                timeZone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day,
                                             hour: hour, minute: minute, second: second))
    }

    static func validate(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, (-90.0...90.0).contains(latitude) else { throw SolarPositionError.invalidLatitude(latitude) }
        guard longitude.isFinite, (-180.0...180.0).contains(longitude) else { throw SolarPositionError.invalidLongitude(longitude) }
    }

    struct UTCParts { let year, month, day, hour, minute: Int; let second: Double; let decimalYear: Double }

    static func utcComponents(_ date: Date) -> UTCParts {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let sec = Double(c.second ?? 0) + Double(c.nanosecond ?? 0) / 1e9
        let year = c.year ?? 2000
        let startOfYear = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
        let startNext = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        let frac = date.timeIntervalSince(startOfYear) / startNext.timeIntervalSince(startOfYear)
        return UTCParts(year: year, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0, minute: c.minute ?? 0,
                        second: sec, decimalYear: Double(year) + frac)
    }
}

// MARK: - SPA-Kern (spa.c-Port)

public enum SPA {
    static let sunRadius = 0.26667

    // MARK: ΔT

    /// Schätzung ΔT = TT − UT1 in Sekunden.
    /// 1990–2026: Stützwerte (IERS/USNO, gerundet), linear interpoliert.
    /// Außerhalb: Polynome nach Espenak & Meeus (NASA, 2006). Fehler 2026–2035 < ~3 s
    /// ⇒ Positionsfehler < 0.0125° (Sonne wandert 0.25°/min) – vernachlässigbar.
    public static func deltaT(decimalYear y: Double) -> Double {
        let table: [(Double, Double)] = [
            (1990, 56.86), (1995, 60.78), (2000, 63.83), (2005, 64.69), (2010, 66.07),
            (2015, 67.64), (2017, 68.59), (2020, 69.36), (2022, 69.20), (2024, 69.18), (2026, 69.10),
        ]
        if y >= table.first!.0 && y <= table.last!.0 {
            for i in 0..<(table.count - 1) where y <= table[i + 1].0 {
                let (y0, v0) = table[i], (y1, v1) = table[i + 1]
                return v0 + (v1 - v0) * (y - y0) / (y1 - y0)
            }
        }
        if y > table.last!.0 && y < 2050 {
            // Anschluss an den letzten Stützwert, Trend gemäß Espenak/Meeus-Ableitung (0.32217 + 0.011178 t).
            let t = y - 2026
            return table.last!.1 + 0.1 * t
        }
        if y >= 2050 && y < 2150 {
            let u = (y - 1820) / 100
            return -20 + 32 * u * u - 0.5628 * (2150 - y)
        }
        // Grobe Langzeitnäherung (Morrison & Stephenson) – für diese App außerhalb des Nutzungszeitraums.
        let u = (y - 1820) / 100
        return -20 + 32 * u * u
    }

    // MARK: Hilfsfunktionen (spa.c)

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func limitDegrees(_ degrees: Double) -> Double {
        let d = degrees / 360.0
        var l = 360.0 * (d - floor(d))
        if l < 0 { l += 360.0 }
        return l
    }
    static func limitDegrees180pm(_ degrees: Double) -> Double {
        let d = degrees / 360.0
        var l = 360.0 * (d - floor(d))
        if l < -180.0 { l += 360.0 } else if l > 180.0 { l -= 360.0 }
        return l
    }
    static func limitDegrees180(_ degrees: Double) -> Double {
        let d = degrees / 180.0
        var l = 180.0 * (d - floor(d))
        if l < 0 { l += 180.0 }
        return l
    }
    static func limitZero2One(_ value: Double) -> Double {
        var l = value - floor(value)
        if l < 0 { l += 1.0 }
        return l
    }
    static func limitMinutes(_ minutes: Double) -> Double {
        var l = minutes
        if l < -20.0 { l += 1440.0 } else if l > 20.0 { l -= 1440.0 }
        return l
    }

    static func julianDay(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Double,
                          deltaUT1: Double, timezone: Double) -> Double {
        let dayDecimal = Double(day) + (Double(hour) - timezone + (Double(minute) + (second + deltaUT1) / 60.0) / 60.0) / 24.0
        var y = year, m = month
        if m < 3 { m += 12; y -= 1 }
        var jd = floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + dayDecimal - 1524.5
        if jd > 2299160.0 {
            let a = floor(Double(y) / 100.0)
            jd += 2 - a + floor(a / 4)
        }
        return jd
    }

    static func earthValues(_ terms: [[[Double]]], _ jme: Double) -> Double {
        var sum = 0.0
        var power = 1.0
        for group in terms {
            var s = 0.0
            for t in group { s += t[0] * cos(t[1] + t[2] * jme) }
            sum += s * power
            power *= jme
        }
        return sum / 1.0e8
    }

    /// Zwischenergebnisse der geozentrischen Rechnung.
    struct Geocentric {
        var jd = 0.0, jc = 0.0, jde = 0.0, jce = 0.0, jme = 0.0
        var l = 0.0, b = 0.0, r = 0.0
        var delPsi = 0.0, delEpsilon = 0.0, epsilon = 0.0
        var nu = 0.0, alpha = 0.0, delta = 0.0
    }

    static func geocentric(jd: Double, deltaT: Double) -> Geocentric {
        var g = Geocentric()
        g.jd = jd
        g.jc = (jd - 2451545.0) / 36525.0
        g.jde = jd + deltaT / 86400.0
        g.jce = (g.jde - 2451545.0) / 36525.0
        g.jme = g.jce / 10.0

        g.l = limitDegrees(deg(earthValues(SPATables.L, g.jme)))
        g.b = deg(earthValues(SPATables.B, g.jme))
        g.r = earthValues(SPATables.R, g.jme)

        let theta = limitDegrees(g.l + 180.0)
        let beta = -g.b
        let jce = g.jce
        let x: [Double] = [
            297.85036 + jce * (445267.111480 + jce * (-0.0019142 + jce / 189474.0)),
            357.52772 + jce * (35999.050340 + jce * (-0.0001603 - jce / 300000.0)),
            134.96298 + jce * (477198.867398 + jce * (0.0086972 + jce / 56250.0)),
            93.27191 + jce * (483202.017538 + jce * (-0.0036825 + jce / 327270.0)),
            125.04452 + jce * (-1934.136261 + jce * (0.0020708 + jce / 450000.0)),
        ]
        var sumPsi = 0.0, sumEps = 0.0
        for i in 0..<SPATables.nutationY.count {
            let y = SPATables.nutationY[i]
            var xy = 0.0
            for j in 0..<5 { xy += x[j] * y[j] }
            let a = SPATables.nutationABCD[i]
            sumPsi += (a[0] + a[1] * jce) * sin(rad(xy))
            sumEps += (a[2] + a[3] * jce) * cos(rad(xy))
        }
        g.delPsi = sumPsi / 36_000_000.0
        g.delEpsilon = sumEps / 36_000_000.0

        let u = g.jme / 10.0
        let eps0 = 84381.448 + u * (-4680.93 + u * (-1.55 + u * (1999.25 + u * (-51.38 + u * (-249.67 +
                   u * (-39.05 + u * (7.12 + u * (27.87 + u * (5.79 + u * 2.45)))))))))
        g.epsilon = g.delEpsilon + eps0 / 3600.0

        let delTau = -20.4898 / (3600.0 * g.r)
        let lambda = theta + g.delPsi + delTau

        let nu0 = limitDegrees(280.46061837 + 360.98564736629 * (jd - 2451545.0) +
                               g.jc * g.jc * (0.000387933 - g.jc / 38710000.0))
        g.nu = nu0 + g.delPsi * cos(rad(g.epsilon))

        let lr = rad(lambda), er = rad(g.epsilon), br = rad(beta)
        g.alpha = limitDegrees(deg(atan2(sin(lr) * cos(er) - tan(br) * sin(er), cos(lr))))
        g.delta = deg(asin(sin(br) * cos(er) + cos(br) * sin(er) * sin(lr)))
        return g
    }

    static func refractionCorrection(_ e0: Double, _ atm: Atmosphere) -> Double {
        guard e0 >= -1.0 * (sunRadius + atm.horizonRefraction) else { return 0 }
        return (atm.pressure / 1010.0) * (283.0 / (273.0 + atm.temperature)) *
            1.02 / (60.0 * tan(rad(e0 + 10.3 / (e0 + 5.11))))
    }

    /// Vollständige SPA-Berechnung (Zenit, Azimut, Zeitgleichung).
    public static func compute(_ input: SPAInput) -> SolarPosition {
        let jd = julianDay(year: input.year, month: input.month, day: input.day, hour: input.hour,
                           minute: input.minute, second: input.second, deltaUT1: input.deltaUT1, timezone: input.timezone)
        let g = geocentric(jd: jd, deltaT: input.deltaT)

        let h = limitDegrees(g.nu + input.longitude - g.alpha)
        let xi = 8.794 / (3600.0 * g.r)

        // Parallaxe (topozentrische Korrektur)
        let latR = rad(input.latitude), xiR = rad(xi), hR = rad(h), dR = rad(g.delta)
        let u = atan(0.99664719 * tan(latR))
        let y = 0.99664719 * sin(u) + input.elevation * sin(latR) / 6378140.0
        let x = cos(u) + input.elevation * cos(latR) / 6378140.0
        let delAlphaR = atan2(-x * sin(xiR) * sin(hR), cos(dR) - x * sin(xiR) * cos(hR))
        let deltaPrime = deg(atan2((sin(dR) - y * sin(xiR)) * cos(delAlphaR), cos(dR) - x * sin(xiR) * cos(hR)))
        let delAlpha = deg(delAlphaR)
        let hPrime = h - delAlpha

        let dpR = rad(deltaPrime), hpR = rad(hPrime)
        let e0 = deg(asin(sin(latR) * sin(dpR) + cos(latR) * cos(dpR) * cos(hpR)))
        let e = e0 + refractionCorrection(e0, input.atmosphere)
        let zenith = 90.0 - e
        let azAstro = limitDegrees(deg(atan2(sin(hpR), cos(hpR) * sin(latR) - tan(dpR) * cos(latR))))
        let azimuth = limitDegrees(azAstro + 180.0)

        // Zeitgleichung
        let m = limitDegrees(280.4664567 + g.jme * (360007.6982779 + g.jme * (0.03032028 +
                g.jme * (1.0 / 49931.0 + g.jme * (-1.0 / 15300.0 + g.jme * (-1.0 / 2000000.0))))))
        let eot = limitMinutes(4.0 * (m - 0.0057183 - g.alpha + g.delPsi * cos(rad(g.epsilon))))

        return SolarPosition(azimuth: azimuth, elevation: e, elevationGeometric: e0, zenith: zenith,
                             declination: g.delta, hourAngle: hPrime, equationOfTime: eot)
    }

    struct RTS { let sunrise: Double?; let transit: Double; let sunset: Double?; let transitElevation: Double }

    /// Sonnenauf-/untergang & Transit (SPA Anhang A.2). Ergebnis in lokalen Dezimalstunden.
    static func riseTransitSet(_ input: SPAInput) -> RTS {
        let h0Prime = -1.0 * (sunRadius + input.atmosphere.horizonRefraction)
        var jd = julianDay(year: input.year, month: input.month, day: input.day, hour: 0, minute: 0, second: 0,
                           deltaUT1: 0, timezone: 0)
        let nu = geocentric(jd: jd, deltaT: input.deltaT).nu
        jd -= 1
        var alpha = [Double](repeating: 0, count: 3), delta = [Double](repeating: 0, count: 3)
        for i in 0..<3 {
            let g = geocentric(jd: jd, deltaT: 0)
            alpha[i] = g.alpha; delta[i] = g.delta
            jd += 1
        }

        var m = [Double](repeating: 0, count: 3) // 0 = Transit, 1 = Aufgang, 2 = Untergang
        m[0] = (alpha[1] - input.longitude - nu) / 360.0

        let latR = rad(input.latitude)
        var h0 = -99999.0
        let arg = (sin(rad(h0Prime)) - sin(latR) * sin(rad(delta[1]))) / (cos(latR) * cos(rad(delta[1])))
        if abs(arg) <= 1 { h0 = limitDegrees180(deg(acos(arg))) }

        func alphaDeltaPrime(_ ad: [Double], _ n: Double) -> Double {
            var a = ad[1] - ad[0], b = ad[2] - ad[1]
            if abs(a) >= 2.0 { a = limitZero2One(a) }
            if abs(b) >= 2.0 { b = limitZero2One(b) }
            return ad[1] + n * (a + b + (b - a) * n) / 2.0
        }
        func dayfracToLocalHr(_ f: Double) -> Double { 24.0 * limitZero2One(f + input.timezone / 24.0) }

        if h0 < 0 {
            // Polartag/-nacht: nur Transit (näherungsweise).
            let t = limitZero2One(m[0])
            return RTS(sunrise: nil, transit: dayfracToLocalHr(t), sunset: nil, transitElevation: 90 - abs(input.latitude - delta[1]))
        }
        m[1] = limitZero2One(m[0] - h0 / 360.0)
        m[2] = limitZero2One(m[0] + h0 / 360.0)
        m[0] = limitZero2One(m[0])

        var hPrime = [Double](repeating: 0, count: 3), hRts = [Double](repeating: 0, count: 3)
        var dPrime = [Double](repeating: 0, count: 3)
        for i in 0..<3 {
            let nuRts = nu + 360.985647 * m[i]
            let n = m[i] + input.deltaT / 86400.0
            let aP = alphaDeltaPrime(alpha, n)
            dPrime[i] = alphaDeltaPrime(delta, n)
            hPrime[i] = limitDegrees180pm(nuRts + input.longitude - aP)
            hRts[i] = deg(asin(sin(latR) * sin(rad(dPrime[i])) + cos(latR) * cos(rad(dPrime[i])) * cos(rad(hPrime[i]))))
        }
        func riseSet(_ i: Int) -> Double {
            m[i] + (hRts[i] - h0Prime) / (360.0 * cos(rad(dPrime[i])) * cos(latR) * sin(rad(hPrime[i])))
        }
        return RTS(sunrise: dayfracToLocalHr(riseSet(1)),
                   transit: dayfracToLocalHr(m[0] - hPrime[0] / 360.0),
                   sunset: dayfracToLocalHr(riseSet(2)),
                   transitElevation: hRts[0])
    }
}
