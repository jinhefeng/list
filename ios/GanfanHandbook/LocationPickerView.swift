import CoreLocation
@preconcurrency import MapKit
import SwiftUI

@MainActor
private final class CurrentLocationModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var updateID = 0
    @Published private(set) var statusMessage: String?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            statusMessage = "定位权限未开启；仍可搜索或直接点选地图。"
        @unknown default:
            statusMessage = "暂时无法定位；仍可搜索或直接点选地图。"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestCurrentLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            self?.updateID += 1
            self?.statusMessage = "已定位到当前位置；搜索结果优先显示附近地点。"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.statusMessage = "暂时无法获取当前位置；仍可搜索或直接点选地图。"
        }
    }
}

struct MapLocationSelection {
    let storeName: String
    let address: String
    let latitude: Double
    let longitude: Double
}

private struct MapLocationCandidate: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D

    var selection: MapLocationSelection {
        MapLocationSelection(
            storeName: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}

struct MapLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @StateObject private var currentLocation = CurrentLocationModel()

    let onSelect: (MapLocationSelection) -> Void

    @State private var query: String
    @State private var cameraPosition: MapCameraPosition
    @State private var searchResults: [MapLocationCandidate] = []
    @State private var isShowingSearchResults = false
    @State private var selectedLocation: MapLocationCandidate?
    @State private var isSearching = false
    @State private var didCenterOnCurrentLocation = false
    @State private var statusMessage = "地图优先定位到当前位置；也可以搜索或直接点选。"

    init(onSelect: @escaping (MapLocationSelection) -> Void) {
        self.onSelect = onSelect
        _query = State(initialValue: "")

        let center = CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 18)
        )
        _cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索餐厅、商店或地址", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit(performSearch)
                Button("搜索", action: performSearch)
                    .buttonStyle(.borderedProminent)
                    .tint(GanfanPalette.forest)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GanfanPalette.canvas)

            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    if let selectedLocation {
                        Annotation(
                            selectedLocation.name.isEmpty ? "已选地点" : selectedLocation.name,
                            coordinate: selectedLocation.coordinate
                        ) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        Task { await selectMapPoint(coordinate) }
                    }
                )
                .frame(minHeight: 220, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: .infinity)

            if isShowingSearchResults && !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { result in
                            Button {
                                select(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name.isEmpty ? result.address : result.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !result.address.isEmpty, result.address != result.name {
                                        Text(result.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            if result.id != searchResults.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                if isSearching { ProgressView() }
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("选择地图地址")
        .navigationBarTitleDisplayMode(.inline)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
        .onChange(of: query) { _, _ in
            searchResults = []
            isShowingSearchResults = false
        }
        .onChange(of: currentLocation.updateID) { _, _ in
            guard !didCenterOnCurrentLocation,
                  selectedLocation == nil,
                  let coordinate = currentLocation.coordinate else { return }
            didCenterOnCurrentLocation = true
            cameraPosition = .region(Self.region(centeredOn: coordinate))
            statusMessage = currentLocation.statusMessage ?? "已定位到当前位置；搜索结果优先显示附近地点。"
        }
        .onChange(of: currentLocation.statusMessage) { _, message in
            guard currentLocation.coordinate == nil, let message else { return }
            statusMessage = message
        }
        .task {
            currentLocation.requestCurrentLocation()
            await Task.yield()
            isSearchFocused = true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("使用此位置") {
                    guard let selectedLocation else { return }
                    onSelect(selectedLocation.selection)
                    dismiss()
                }
                .disabled(selectedLocation == nil)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedLocation?.id)
    }

    private func performSearch() {
        isSearchFocused = false
        Task { await search() }
    }

    @MainActor
    private func search() async {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        if let coordinate = currentLocation.coordinate {
            request.region = Self.region(centeredOn: coordinate, span: 0.15)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            let candidates = response.mapItems.map { item in
                MapLocationCandidate(
                    name: item.name ?? "",
                    address: item.placemark.title ?? "",
                    coordinate: item.placemark.coordinate
                )
            }
            if let coordinate = currentLocation.coordinate {
                let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                searchResults = candidates.sorted {
                    origin.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
                        < origin.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
                }
            } else {
                searchResults = candidates
            }
            isShowingSearchResults = !searchResults.isEmpty
            statusMessage = searchResults.isEmpty ? "没有找到地点；可以继续搜索或直接点选地图。" : "选择一个搜索结果，或在地图上点选位置。"
        } catch {
            searchResults = []
            statusMessage = "地图搜索暂不可用；仍可直接点选地图位置。"
        }
    }

    @MainActor
    private func selectMapPoint(_ coordinate: CLLocationCoordinate2D) async {
        isSearching = true
        defer { isSearching = false }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.name ?? ""
        let address = Self.address(from: placemark)
        let result = MapLocationCandidate(name: name, address: address, coordinate: coordinate)
        select(result)
        statusMessage = address.isEmpty ? "位置已选；地址由地图自动补充。" : "已确认地图位置。"
    }

    private func select(_ candidate: MapLocationCandidate) {
        selectedLocation = candidate
        isShowingSearchResults = false
        cameraPosition = .region(Self.region(centeredOn: candidate.coordinate, span: 0.015))
        if !candidate.address.isEmpty {
            statusMessage = "已确认地图位置。"
        }
    }

    static func address(from placemark: CLPlacemark?) -> String {
        guard let placemark else { return "" }
        let parts = [
            placemark.name,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        let uniqueParts = parts.reduce(into: [String]()) { result, part in
            if !result.contains(part) { result.append(part) }
        }
        return uniqueParts.joined()
    }

    private static func region(centeredOn coordinate: CLLocationCoordinate2D, span: CLLocationDegrees = 0.03) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }
}

struct StaticRecordLocationMap: View {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        ) {
            Marker(name.isEmpty ? (address.isEmpty ? "记录地点" : address) : name, coordinate: coordinate)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(address.isEmpty ? name : address)
    }
}
