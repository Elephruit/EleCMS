import SwiftUI
import MapKit

struct CountyMapView: View {
    let footprintFIPS: Set<String>
    let states: Set<String>
    
    // Static cache to avoid reloading and re-parsing GeoJSON multiple times
    private static var cachedGeoJSON: GeoJSON?
    private static var isDownloading = false
    
    @State private var countyFeatures: [CountyFeature] = []
    @State private var isLoading = false
    @State private var boundingBox: MKMapRect?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.1)
                
                if isLoading {
                    ProgressView().tint(.white)
                } else if let box = boundingBox, !countyFeatures.isEmpty {
                    Canvas { context, size in
                        let scale = calculateScale(for: box, in: size)
                        
                        for feature in countyFeatures {
                            let isServiceArea = footprintFIPS.contains(feature.fips)
                            
                            for polygon in feature.polygons {
                                var path = Path()
                                guard let firstPoint = polygon.first else { continue }
                                
                                let start = project(firstPoint, box: box, size: size, scale: scale)
                                path.move(to: start)
                                
                                for i in 1..<polygon.count {
                                    let next = project(polygon[i], box: box, size: size, scale: scale)
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
        .task { await loadAndFilter() }
        .onChange(of: states) { _ in Task { await loadAndFilter() } }
    }
    
    private func project(_ coord: CLLocationCoordinate2D, box: MKMapRect, size: CGSize, scale: Double) -> CGPoint {
        let point = MKMapPoint(coord)
        let x = (point.x - box.origin.x) * scale
        let y = (point.y - box.origin.y) * scale
        return CGPoint(x: x, y: y)
    }
    
    private func calculateScale(for box: MKMapRect, in size: CGSize) -> Double {
        if box.size.width == 0 || box.size.height == 0 { return 1.0 }
        let scaleX = size.width / box.size.width
        let scaleY = size.height / box.size.height
        return min(scaleX, scaleY)
    }
    
    private func loadAndFilter() async {
        guard !states.isEmpty else { 
            await MainActor.run { 
                self.countyFeatures = []
                self.boundingBox = nil
            }
            return 
        }
        
        isLoading = true
        
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
            
            guard let geoJSON = CountyMapView.cachedGeoJSON else { return }
            let activeStateFIPS = StateFIPS.getFIPS(for: states)
            
            var features: [CountyFeature] = []
            var combinedRect = MKMapRect.null
            
            for feature in geoJSON.features {
                let stateFips = String(feature.id.prefix(2))
                guard activeStateFIPS.contains(stateFips) else { continue }
                
                if let county = CountyFeature(from: feature) {
                    features.append(county)
                    // Expand bounding box only for features we are drawing
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
                self.countyFeatures = features
                self.boundingBox = combinedRect.isNull ? nil : combinedRect
                self.isLoading = false
            }
        } catch {
            print("Failed to load/filter GeoJSON: \(error)")
            isLoading = false
        }
    }
}

// MARK: - Models (Keeping them in the same file for now)

struct CountyFeature: Identifiable {
    var id: String { fips }
    let fips: String
    let polygons: [[CLLocationCoordinate2D]]
    
    init?(from feature: GeoJSON.Feature) {
        self.fips = feature.id
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
        let geometry: Geometry
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
    static func getFIPS(for states: Set<String>) -> Set<String> {
        Set(states.compactMap { map[$0.uppercased()] })
    }
}
