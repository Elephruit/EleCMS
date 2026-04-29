import SwiftUI
import MapKit

struct CountyMapView: View {
    let footprintFIPS: Set<String>
    let footprintCounties: Set<CountyMapCounty>
    let states: Set<String>
    
    // Static cache to avoid reloading and re-parsing GeoJSON multiple times
    private static var cachedGeoJSON: GeoJSON?
    private static var isDownloading = false
    
    @State private var countyFeatures: [CountyFeature] = []
    @State private var isLoading = false
    @State private var boundingBox: MKMapRect?
    @State private var loadID = UUID()

    private var normalizedFootprintFIPS: Set<String> {
        Set(footprintFIPS.compactMap { CountyMapView.normalizedFIPS($0) })
    }

    private var normalizedFootprintCounties: Set<CountyMapCounty> {
        Set(footprintCounties.map { $0.normalized })
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.1)
                
                if isLoading {
                    ProgressView().tint(.white)
                } else if let box = boundingBox, !countyFeatures.isEmpty {
                    Canvas { context, size in
                        let scale = calculateScale(for: box, in: size)
                        let offset = calculateOffset(for: box, in: size, scale: scale)
                        let activeFIPS = normalizedFootprintFIPS
                        let activeCounties = normalizedFootprintCounties
                        
                        for feature in countyFeatures {
                            let isServiceArea = activeFIPS.contains(feature.fips)
                                || activeCounties.contains(feature.identity)
                            
                            for polygon in feature.polygons {
                                var path = Path()
                                guard let firstPoint = polygon.first else { continue }
                                
                                let start = project(firstPoint, box: box, scale: scale, offset: offset)
                                path.move(to: start)
                                
                                for i in 1..<polygon.count {
                                    let next = project(polygon[i], box: box, scale: scale, offset: offset)
                                    path.addLine(to: next)
                                }
                                path.closeSubpath()
                                
                                if isServiceArea {
                                    context.fill(path, with: .color(Color.blue.opacity(0.7)))
                                    context.stroke(path, with: .color(Color.white.opacity(0.8)), lineWidth: 0.8)
                                } else {
                                    context.fill(path, with: .color(Color.white.opacity(0.05)))
                                    context.stroke(path, with: .color(Color.white.opacity(0.15)), lineWidth: 0.4)
                                }
                            }
                        }
                    }
                } else {
                    VStack {
                        Image(systemName: "map").font(.largeTitle).foregroundColor(.gray.opacity(0.4))
                        Text(states.isEmpty ? "Waiting for data..." : "No Geographic Data").font(.caption).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { reload() }
        .onChange(of: states) { _ in reload() }
        .onChange(of: footprintFIPS) { _ in reload() }
        .onChange(of: footprintCounties) { _ in reload() }
    }

    private func reload() {
        let id = UUID()
        loadID = id
        countyFeatures = []
        boundingBox = nil
        Task { await loadAndFilter(loadID: id) }
    }
    
    private func project(_ coord: CLLocationCoordinate2D, box: MKMapRect, scale: Double, offset: CGPoint) -> CGPoint {
        let point = MKMapPoint(coord)
        let x = offset.x + (point.x - box.origin.x) * scale
        let y = offset.y + (point.y - box.origin.y) * scale
        return CGPoint(x: x, y: y)
    }
    
    private func calculateScale(for box: MKMapRect, in size: CGSize) -> Double {
        if box.size.width == 0 || box.size.height == 0 { return 1.0 }
        let scaleX = size.width / box.size.width
        let scaleY = size.height / box.size.height
        return min(scaleX, scaleY) * 0.92
    }

    private func calculateOffset(for box: MKMapRect, in size: CGSize, scale: Double) -> CGPoint {
        let renderedWidth = box.size.width * scale
        let renderedHeight = box.size.height * scale
        return CGPoint(
            x: (size.width - renderedWidth) / 2,
            y: (size.height - renderedHeight) / 2
        )
    }
    
    private func loadAndFilter(loadID currentLoadID: UUID) async {
        guard !footprintFIPS.isEmpty || !footprintCounties.isEmpty || !states.isEmpty else {
            await MainActor.run {
                guard self.loadID == currentLoadID else { return }
                self.countyFeatures = []
                self.boundingBox = nil
                self.isLoading = false
            }
            return 
        }
        
        await MainActor.run {
            guard self.loadID == currentLoadID else { return }
            self.isLoading = true
        }
        
        do {
            if CountyMapView.cachedGeoJSON == nil {
                if CountyMapView.isDownloading {
                    // Wait for other instance to finish
                    while CountyMapView.isDownloading { try? await Task.sleep(nanoseconds: 100_000_000) }
                } else {
                    CountyMapView.isDownloading = true
                    let url = URL(string: "https://raw.githubusercontent.com/plotly/datasets/master/geojson-counties-fips.json")!
                    let (data, _) = try await URLSession.shared.data(from: url)
                    CountyMapView.cachedGeoJSON = try JSONDecoder().decode(GeoJSON.self, from: data)
                    CountyMapView.isDownloading = false
                }
            }
            
            guard let geoJSON = CountyMapView.cachedGeoJSON else {
                await MainActor.run {
                    guard self.loadID == currentLoadID else { return }
                    self.isLoading = false
                }
                return
            }
            let normalizedFootprint = Set(footprintFIPS.compactMap { CountyMapView.normalizedFIPS($0) })
            let countyFootprint = normalizedFootprintCounties
            let activeStateFIPS = normalizedFootprint.isEmpty
                ? StateFIPS.getFIPS(for: states).union(Set(countyFootprint.compactMap { StateFIPS.getFIPS(for: $0.state) }))
                : Set(normalizedFootprint.map { String($0.prefix(2)) })
            let displayedStateFIPS = displayStateFIPS(from: activeStateFIPS)
            
            var features: [CountyFeature] = []
            var combinedRect = MKMapRect.null
            
            for feature in geoJSON.features {
                let stateFips = String(feature.id.prefix(2))
                guard displayedStateFIPS.contains(stateFips) else { continue }
                
                if let county = CountyFeature(from: feature) {
                    features.append(county)
                    for polygon in county.polygons {
                        for coord in polygon {
                            let point = MKMapPoint(coord)
                            combinedRect = combinedRect.union(MKMapRect(origin: point, size: MKMapSize(width: 0.1, height: 0.1)))
                        }
                    }
                }
            }
            
            // Add padding
            if !combinedRect.isNull {
                let padding = combinedRect.size.width * 0.1
                combinedRect = combinedRect.insetBy(dx: -padding, dy: -padding)
            }
            
            await MainActor.run {
                guard self.loadID == currentLoadID else { return }
                self.countyFeatures = features
                self.boundingBox = combinedRect.isNull ? nil : combinedRect
                self.isLoading = false
            }
        } catch {
            print("Failed to load/filter GeoJSON: \(error)")
            await MainActor.run {
                guard self.loadID == currentLoadID else { return }
                self.isLoading = false
            }
        }
    }

    private static func normalizedFIPS(_ value: String) -> String? {
        let digits = String(value.filter { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(5)).leftPadding(toLength: 5, withPad: "0")
    }

    private func displayStateFIPS(from activeStateFIPS: Set<String>) -> Set<String> {
        let nonContiguous: Set<String> = ["02", "15", "72"]
        let hasContiguousStates = activeStateFIPS.contains { !nonContiguous.contains($0) }
        guard hasContiguousStates else { return activeStateFIPS }
        return activeStateFIPS.subtracting(nonContiguous)
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(character), count: toLength - count) + self
    }
}

// MARK: - Models (Keeping them in the same file for now)

struct CountyFeature: Identifiable {
    var id: String { fips }
    let fips: String
    let name: String
    let stateFIPS: String
    let polygons: [[CLLocationCoordinate2D]]

    var identity: CountyMapCounty {
        CountyMapCounty(state: stateFIPS, name: name).normalized
    }
    
    init?(from feature: GeoJSON.Feature) {
        self.fips = feature.id
        self.name = feature.properties.name
        self.stateFIPS = feature.properties.state
        var polys: [[CLLocationCoordinate2D]] = []
        if feature.geometry.type == "Polygon" {
            for ring in feature.geometry.coordinates {
                polys.append(ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
            }
        } else if feature.geometry.type == "MultiPolygon" {
            for polygonCoords in feature.geometry.coordinates {
                polys.append(polygonCoords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) })
            }
        }
        guard !polys.isEmpty else { return nil }
        self.polygons = polys
    }
}

struct GeoJSON: Decodable {
    let features: [Feature]
    struct Feature: Decodable {
        let id: String
        let properties: Properties
        let geometry: Geometry
    }
    struct Properties: Decodable {
        let name: String
        let state: String

        struct DynamicKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init?(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                return nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            self.name = container.stringValue(for: ["NAME", "name"]) ?? ""
            self.state = container.stringValue(for: ["STATE", "state"]) ?? ""
        }
    }
    struct Geometry: Decodable {
        let type: String
        let coordinates: [[[Double]]]
        enum CodingKeys: String, CodingKey { case type, coordinates }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            if type == "Polygon" {
                coordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
            } else if type == "MultiPolygon" {
                let multiCoords = try container.decode([[[[Double]]]].self, forKey: .coordinates)
                coordinates = multiCoords.flatMap { $0 }
            } else { coordinates = [] }
        }
    }
}

struct CountyMapCounty: Hashable {
    let state: String
    let name: String

    var normalized: CountyMapCounty {
        CountyMapCounty(
            state: StateFIPS.getFIPS(for: state) ?? state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            name: name
                .replacingOccurrences(of: " County", with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
    }
}

struct StateFIPS {
    static let map: [String: String] = [
        "AL": "01", "AK": "02", "AZ": "04", "AR": "05", "CA": "06",
        "CO": "08", "CT": "09", "DE": "10", "FL": "12", "GA": "13",
        "HI": "15", "ID": "16", "IL": "17", "IN": "18", "IA": "19",
        "KS": "20", "KY": "21", "LA": "22", "ME": "23", "MD": "24",
        "MA": "25", "MI": "26", "MN": "27", "MS": "28", "MO": "29",
        "MT": "30", "NE": "31", "NV": "32", "NH": "33", "NJ": "34",
        "NM": "35", "NY": "36", "NC": "37", "ND": "38", "OH": "39",
        "OK": "40", "OR": "41", "PA": "42", "RI": "44", "SC": "45",
        "SD": "46", "TN": "47", "TX": "48", "UT": "49", "VT": "50",
        "VA": "51", "WA": "53", "WV": "54", "WI": "55", "WY": "56",
        "DC": "11", "PR": "72"
    ]
    static let names: [String: String] = [
        "ALABAMA": "01", "ALASKA": "02", "ARIZONA": "04", "ARKANSAS": "05",
        "CALIFORNIA": "06", "COLORADO": "08", "CONNECTICUT": "09", "DELAWARE": "10",
        "DISTRICT OF COLUMBIA": "11", "FLORIDA": "12", "GEORGIA": "13", "HAWAII": "15",
        "IDAHO": "16", "ILLINOIS": "17", "INDIANA": "18", "IOWA": "19",
        "KANSAS": "20", "KENTUCKY": "21", "LOUISIANA": "22", "MAINE": "23",
        "MARYLAND": "24", "MASSACHUSETTS": "25", "MICHIGAN": "26", "MINNESOTA": "27",
        "MISSISSIPPI": "28", "MISSOURI": "29", "MONTANA": "30", "NEBRASKA": "31",
        "NEVADA": "32", "NEW HAMPSHIRE": "33", "NEW JERSEY": "34", "NEW MEXICO": "35",
        "NEW YORK": "36", "NORTH CAROLINA": "37", "NORTH DAKOTA": "38", "OHIO": "39",
        "OKLAHOMA": "40", "OREGON": "41", "PENNSYLVANIA": "42", "RHODE ISLAND": "44",
        "SOUTH CAROLINA": "45", "SOUTH DAKOTA": "46", "TENNESSEE": "47", "TEXAS": "48",
        "UTAH": "49", "VERMONT": "50", "VIRGINIA": "51", "WASHINGTON": "53",
        "WEST VIRGINIA": "54", "WISCONSIN": "55", "WYOMING": "56", "PUERTO RICO": "72"
    ]
    static func getFIPS(for states: Set<String>) -> Set<String> {
        Set(states.compactMap { getFIPS(for: $0) })
    }

    static func getFIPS(for state: String) -> String? {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.count == 2, normalized.allSatisfy(\.isNumber) {
            return normalized
        }
        return map[normalized] ?? names[normalized]
    }
}

private extension KeyedDecodingContainer where Key == GeoJSON.Properties.DynamicKey {
    func stringValue(for keys: [String]) -> String? {
        for keyName in keys {
            guard let key = Key(stringValue: keyName),
                  let value = try? decode(String.self, forKey: key) else { continue }
            return value
        }
        return nil
    }
}
