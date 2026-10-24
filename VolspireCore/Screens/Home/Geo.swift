//
//  Geo.swift
//  Volspire
//
//  Port of the web's lib/geo.ts: the curated city table (approximate city
//  centres) the Collab map pins artists against, plus `resolve`,
//  `distanceKm` and `formatDistance`. Profile locations are free text; they
//  match on the full name first, then on the city part before the comma
//  (accent- and punctuation-insensitive). Anything else simply isn't mapped.
//

import Foundation

struct LatLng: Hashable, Sendable {
    let lat: Double
    let lng: Double
}

struct GeoPlace: Hashable, Sendable {
    let name: String
    let lat: Double
    let lng: Double
    var coords: LatLng { LatLng(lat: lat, lng: lng) }
    /// "Los Angeles" from "Los Angeles, CA".
    var city: String { name.split(separator: ",").first.map(String.init) ?? name }
}

enum Geo {
    static let places: [GeoPlace] = [
        .init(name: "Los Angeles, CA", lat: 34.05, lng: -118.24),
        .init(name: "New York, NY", lat: 40.71, lng: -74.01),
        .init(name: "Atlanta, GA", lat: 33.75, lng: -84.39),
        .init(name: "Miami, FL", lat: 25.76, lng: -80.19),
        .init(name: "Chicago, IL", lat: 41.88, lng: -87.63),
        .init(name: "Nashville, TN", lat: 36.16, lng: -86.78),
        .init(name: "Houston, TX", lat: 29.76, lng: -95.37),
        .init(name: "Dallas, TX", lat: 32.78, lng: -96.8),
        .init(name: "Detroit, MI", lat: 42.33, lng: -83.05),
        .init(name: "Philadelphia, PA", lat: 39.95, lng: -75.17),
        .init(name: "San Francisco, CA", lat: 37.77, lng: -122.42),
        .init(name: "Seattle, WA", lat: 47.61, lng: -122.33),
        .init(name: "Portland, OR", lat: 45.52, lng: -122.68),
        .init(name: "Austin, TX", lat: 30.27, lng: -97.74),
        .init(name: "Denver, CO", lat: 39.74, lng: -104.99),
        .init(name: "Las Vegas, NV", lat: 36.17, lng: -115.14),
        .init(name: "Phoenix, AZ", lat: 33.45, lng: -112.07),
        .init(name: "Minneapolis, MN", lat: 44.98, lng: -93.27),
        .init(name: "New Orleans, LA", lat: 29.95, lng: -90.07),
        .init(name: "Memphis, TN", lat: 35.15, lng: -90.05),
        .init(name: "Boston, MA", lat: 42.36, lng: -71.06),
        .init(name: "San Diego, CA", lat: 32.72, lng: -117.16),
        .init(name: "Charlotte, NC", lat: 35.23, lng: -80.84),
        .init(name: "Tampa, FL", lat: 27.95, lng: -82.46),
        .init(name: "Orlando, FL", lat: 28.54, lng: -81.38),
        .init(name: "Baltimore, MD", lat: 39.29, lng: -76.61),
        .init(name: "Washington, DC", lat: 38.91, lng: -77.04),
        .init(name: "St. Louis, MO", lat: 38.63, lng: -90.2),
        .init(name: "Kansas City, MO", lat: 39.1, lng: -94.58),
        .init(name: "Cleveland, OH", lat: 41.5, lng: -81.69),
        .init(name: "Columbus, OH", lat: 39.96, lng: -83.0),
        .init(name: "Indianapolis, IN", lat: 39.77, lng: -86.16),
        .init(name: "Milwaukee, WI", lat: 43.04, lng: -87.91),
        .init(name: "Raleigh, NC", lat: 35.78, lng: -78.64),
        .init(name: "Salt Lake City, UT", lat: 40.76, lng: -111.89),
        .init(name: "Toronto, Canada", lat: 43.65, lng: -79.38),
        .init(name: "Vancouver, Canada", lat: 49.28, lng: -123.12),
        .init(name: "Montreal, Canada", lat: 45.5, lng: -73.57),
        .init(name: "London, UK", lat: 51.51, lng: -0.13),
        .init(name: "Manchester, UK", lat: 53.48, lng: -2.24),
        .init(name: "Birmingham, UK", lat: 52.49, lng: -1.89),
        .init(name: "Bristol, UK", lat: 51.45, lng: -2.59),
        .init(name: "Berlin, Germany", lat: 52.52, lng: 13.41),
        .init(name: "Hamburg, Germany", lat: 53.55, lng: 9.99),
        .init(name: "Munich, Germany", lat: 48.14, lng: 11.58),
        .init(name: "Paris, France", lat: 48.86, lng: 2.35),
        .init(name: "Lyon, France", lat: 45.76, lng: 4.84),
        .init(name: "Marseille, France", lat: 43.3, lng: 5.37),
        .init(name: "Amsterdam, Netherlands", lat: 52.37, lng: 4.9),
        .init(name: "Rotterdam, Netherlands", lat: 51.92, lng: 4.48),
        .init(name: "Stockholm, Sweden", lat: 59.33, lng: 18.07),
        .init(name: "Copenhagen, Denmark", lat: 55.68, lng: 12.57),
        .init(name: "Oslo, Norway", lat: 59.91, lng: 10.75),
        .init(name: "Helsinki, Finland", lat: 60.17, lng: 24.94),
        .init(name: "Madrid, Spain", lat: 40.42, lng: -3.7),
        .init(name: "Barcelona, Spain", lat: 41.39, lng: 2.17),
        .init(name: "Lisbon, Portugal", lat: 38.72, lng: -9.14),
        .init(name: "Rome, Italy", lat: 41.9, lng: 12.5),
        .init(name: "Milan, Italy", lat: 45.46, lng: 9.19),
        .init(name: "Zurich, Switzerland", lat: 47.38, lng: 8.54),
        .init(name: "Vienna, Austria", lat: 48.21, lng: 16.37),
        .init(name: "Warsaw, Poland", lat: 52.23, lng: 21.01),
        .init(name: "Prague, Czech Republic", lat: 50.08, lng: 14.44),
        .init(name: "Dublin, Ireland", lat: 53.35, lng: -6.26),
        .init(name: "Brussels, Belgium", lat: 50.85, lng: 4.35),
        .init(name: "Lagos, Nigeria", lat: 6.52, lng: 3.38),
        .init(name: "Accra, Ghana", lat: 5.6, lng: -0.19),
        .init(name: "Johannesburg, South Africa", lat: -26.2, lng: 28.05),
        .init(name: "Cape Town, South Africa", lat: -33.92, lng: 18.42),
        .init(name: "Nairobi, Kenya", lat: -1.29, lng: 36.82),
        .init(name: "Cairo, Egypt", lat: 30.04, lng: 31.24),
        .init(name: "Tokyo, Japan", lat: 35.68, lng: 139.69),
        .init(name: "Seoul, South Korea", lat: 37.57, lng: 126.98),
        .init(name: "Beijing, China", lat: 39.9, lng: 116.41),
        .init(name: "Shanghai, China", lat: 31.23, lng: 121.47),
        .init(name: "Mumbai, India", lat: 19.08, lng: 72.88),
        .init(name: "Delhi, India", lat: 28.61, lng: 77.21),
        .init(name: "Bangkok, Thailand", lat: 13.76, lng: 100.5),
        .init(name: "Singapore", lat: 1.35, lng: 103.82),
        .init(name: "Jakarta, Indonesia", lat: -6.21, lng: 106.85),
        .init(name: "Kuala Lumpur, Malaysia", lat: 3.14, lng: 101.69),
        .init(name: "Sydney, Australia", lat: -33.87, lng: 151.21),
        .init(name: "Melbourne, Australia", lat: -37.81, lng: 144.96),
        .init(name: "Auckland, New Zealand", lat: -36.85, lng: 174.76),
        .init(name: "São Paulo, Brazil", lat: -23.55, lng: -46.63),
        .init(name: "Rio de Janeiro, Brazil", lat: -22.91, lng: -43.17),
        .init(name: "Buenos Aires, Argentina", lat: -34.6, lng: -58.38),
        .init(name: "Bogotá, Colombia", lat: 4.71, lng: -74.07),
        .init(name: "Medellín, Colombia", lat: 6.24, lng: -75.58),
        .init(name: "Mexico City, Mexico", lat: 19.43, lng: -99.13),
        .init(name: "Monterrey, Mexico", lat: 25.69, lng: -100.32),
        .init(name: "Lima, Peru", lat: -12.05, lng: -77.04),
        .init(name: "Santiago, Chile", lat: -33.45, lng: -70.67),
        .init(name: "San Juan, Puerto Rico", lat: 18.47, lng: -66.11),
        .init(name: "Kingston, Jamaica", lat: 18.02, lng: -76.8),
    ]

    /// "Bogotá, Colombia" → "bogota colombia".
    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        var lastSpace = true
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch), ch.isASCII {
                out.unicodeScalars.append(ch)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static let byName: [String: GeoPlace] =
        Dictionary(places.map { (norm($0.name), $0) }, uniquingKeysWith: { a, _ in a })
    private static let byCity: [String: GeoPlace] =
        Dictionary(places.map { (norm($0.city), $0) }, uniquingKeysWith: { a, _ in a })

    /// The curated place a free-text profile location refers to, if any.
    static func resolve(_ raw: String?) -> GeoPlace? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let hit = byName[norm(raw)] { return hit }
        let city = raw.split(separator: ",").first.map(String.init) ?? raw
        return byCity[norm(city)]
    }

    /// Great-circle distance in km (haversine, R = 6371).
    static func distanceKm(_ a: LatLng, _ b: LatLng) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad
        let dLng = (b.lng - a.lng) * rad
        let h = pow(sin(dLat / 2), 2) + cos(a.lat * rad) * cos(b.lat * rad) * pow(sin(dLng / 2), 2)
        return 2 * 6371 * asin(sqrt(h))
    }

    /// "Same city" / "12 km" / "1.2k km".
    static func formatDistance(_ km: Double, unit: DistanceUnit = .metric) -> String {
        if km < 25 { return "Same city" }
        let value = unit == .imperial ? km * 0.621371 : km
        let suffix = unit == .imperial ? "mi" : "km"
        if value < 1000 { return "\(Int(value.rounded())) \(suffix)" }
        var s = String(format: "%.1f", value / 1000)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return "\(s)k \(suffix)"
    }
}
