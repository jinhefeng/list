import CoreLocation
import MapKit
import SwiftUI

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

    let initialAddress: String
    let initialLatitude: Double?
    let initialLongitude: Double?
    let onSelect: (MapLocationSelection) -> Void

    @State private var query: String
    @State private var cameraPosition: MapCameraPosition
    @State private var searchResults: [MapLocationCandidate] = []
    @State private var selectedLocation: MapLocationCandidate?
    @State private var isSearching = false
    @State private var statusMessage = "先搜索地点，地图会移到结果附近；也可以直接点选地图。"

    init(
        initialAddress: String = "",
        initialLatitude: Double? = nil,
        initialLongitude: Double? = nil,
        onSelect: @escaping (MapLocationSelection) -> Void
    ) {
        self.initialAddress = initialAddress
        self.initialLatitude = initialLatitude
        self.initialLongitude = initialLongitude
        self.onSelect = onSelect
        _query = State(initialValue: initialAddress)

        let center: CLLocationCoordinate2D
        if let latitude = initialLatitude, let longitude = initialLongitude,
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            center = CLLocationCoordinate2D(latitude: 35.86, longitude: 104.19)
        }
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
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                Button("搜索") { Task { await search() } }
                    .buttonStyle(.borderedProminent)
                    .tint(GanfanPalette.forest)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding()

            MapReader { proxy in
                Map(position: $cameraPosition) {
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
                    MapCompass()
                    MapScaleView()
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                        Task { await selectMapPoint(coordinate) }
                    }
                )
                .frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
            }

            if !searchResults.isEmpty {
                List(searchResults) { result in
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
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .frame(maxHeight: 220)
            }

            HStack(spacing: 8) {
                if isSearching { ProgressView() }
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GanfanPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding()
        }
        .navigationTitle("选择地图地址")
        .navigationBarTitleDisplayMode(.inline)
        .background(GanfanPalette.canvas)
        .tint(GanfanPalette.forest)
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

    @MainActor
    private func search() async {
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems.map { item in
                MapLocationCandidate(
                    name: item.name ?? "",
                    address: item.placemark.title ?? "",
                    coordinate: item.placemark.coordinate
                )
            }
            statusMessage = searchResults.isEmpty ? "没有找到地点；可以继续搜索或手动填写地址。" : "选择一个搜索结果，或在地图上点选位置。"
        } catch {
            searchResults = []
            statusMessage = "地图搜索暂不可用；仍可在记录表单中手动填写地址。"
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
        statusMessage = address.isEmpty ? "位置已选；地址可返回表单后手动填写。" : "已确认地图位置。"
    }

    private func select(_ candidate: MapLocationCandidate) {
        selectedLocation = candidate
        let region = MKCoordinateRegion(
            center: candidate.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
        cameraPosition = .region(region)
        if !candidate.address.isEmpty {
            statusMessage = "已确认地图位置。"
        }
    }

    private static func address(from placemark: CLPlacemark?) -> String {
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
