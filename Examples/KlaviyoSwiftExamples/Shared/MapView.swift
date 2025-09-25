import CoreLocation
import MapKit
import SwiftUI
@_spi(KlaviyoPrivate) import KlaviyoSwift
@_spi(KlaviyoPrivate) import KlaviyoLocation
struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()
    @StateObject private var geofenceManager = GeofenceManager()

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                ZStack {
                    Map(coordinateRegion: $locationManager.region,
                        showsUserLocation: true,
                        userTrackingMode: .none,
                        annotationItems: geofenceManager.geofenceAnnotations) { annotation in
                            MapAnnotation(coordinate: annotation.coordinate) {
                                VStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                    VStack(spacing: 2) {
                                        Text(annotation.title)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)

                                        Text("\(Int(annotation.radius))m")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                        .overlay(
                            // Add circular overlays for geofence radii
                            ForEach(geofenceManager.geofenceAnnotations) { annotation in
                                GeofenceCircleOverlay(
                                    center: annotation.coordinate,
                                    radius: annotation.radius,
                                    region: locationManager.region
                                )
                            }
                        )

                    // Header
                    VStack {
                        HStack {
                            Button("Close") {
                                dismiss()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)

                            Spacer()

                            VStack(spacing: 4) {
                                // Status indicator
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(geofenceManager.isMonitoring ? Color.green : Color.gray)
                                        .frame(width: 8, height: 8)

                                    Text(geofenceManager.isMonitoring ? "Monitoring Active" : "Not Monitoring")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                }

                                HStack(spacing: 8) {
                                    Button("Register") {
                                        geofenceManager.registerGeofencing()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.7))
                                    .cornerRadius(8)
                                    .disabled(geofenceManager.isLoading)

                                    Button("Stop") {
                                        geofenceManager.unregisterGeofencing()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.7))
                                    .cornerRadius(8)
                                    .disabled(geofenceManager.isLoading)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)

                            Spacer()

                            // Location status indicator
                            VStack(spacing: 2) {
                                Image(systemName: locationIconName)
                                    .foregroundColor(locationIconColor)
                                    .font(.title3)

                                Text(locationStatusText)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                            .onTapGesture {
                                locationManager.requestLocationPermission()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        Spacer()

                        // Loading indicator for geofences
                        if geofenceManager.isLoading {
                            VStack {
                                Spacer()
                                HStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)

                                    Text("Loading geofences...")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                                .padding(.bottom, 100)
                            }
                        }
                    }

                    if locationManager.authorizationStatus == .denied {
                        VStack(spacing: 20) {
                            Image(systemName: "location.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.red)

                            Text("Location Access Required")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)

                            Text("Please enable location access in Settings to view your location on the map and receive location-based notifications.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            Button("Open Settings") {
                                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsURL)
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(25)
                        }
                        .padding(32)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        .padding(.horizontal, 40)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var geofenceOverlays: [GeofenceOverlay] {
        // This would need to be calculated based on map scale
        // For now, return empty array as overlays are complex in SwiftUI
        []
    }

    private var locationIconName: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "location.slash"
        case .denied, .restricted:
            return "location.slash"
        case .authorizedWhenInUse:
            return "location"
        case .authorizedAlways:
            return "location.fill"
        @unknown default:
            return "location.slash"
        }
    }

    private var locationIconColor: Color {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return .orange
        case .denied, .restricted:
            return .red
        case .authorizedWhenInUse:
            return .yellow
        case .authorizedAlways:
            return .green
        @unknown default:
            return .red
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return "Tap to enable"
        case .denied, .restricted:
            return "Settings"
        case .authorizedWhenInUse:
            return "Tap for Always"
        case .authorizedAlways:
            return "Enabled"
        @unknown default:
            return "Unknown"
        }
    }
}

struct GeofenceAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let radius: Double
}

struct GeofenceOverlay: Identifiable {
    let id = UUID()
    let position: CGPoint
    let radius: CGFloat
}

struct GeofenceCircleOverlay: View {
    let center: CLLocationCoordinate2D
    let radius: Double
    let region: MKCoordinateRegion

    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let geofenceScreenPoint = coordinateToScreenPoint(
                coordinate: center,
                region: region,
                screenSize: geometry.size
            )

            let screenRadius = metersToScreenRadius(
                meters: radius,
                region: region,
                screenSize: geometry.size
            )

            Circle()
                .fill(Color.red.opacity(0.2))
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.6), lineWidth: 2)
                )
                .frame(width: screenRadius * 2, height: screenRadius * 2)
                .position(geofenceScreenPoint)
        }
    }

    private func coordinateToScreenPoint(
        coordinate: CLLocationCoordinate2D,
        region: MKCoordinateRegion,
        screenSize: CGSize
    ) -> CGPoint {
        let latDelta = region.span.latitudeDelta
        let lonDelta = region.span.longitudeDelta

        let x = (coordinate.longitude - region.center.longitude) / lonDelta * screenSize.width + screenSize.width / 2
        let y = (region.center.latitude - coordinate.latitude) / latDelta * screenSize.height + screenSize.height / 2

        return CGPoint(x: x, y: y)
    }

    private func metersToScreenRadius(
        meters: Double,
        region: MKCoordinateRegion,
        screenSize: CGSize
    ) -> CGFloat {
        // Convert meters to degrees (approximate)
        let metersPerDegree = 111_000.0 // Rough conversion
        let radiusInDegrees = meters / metersPerDegree

        // Convert to screen pixels
        let screenRadius = radiusInDegrees / region.span.latitudeDelta * screenSize.height

        return CGFloat(screenRadius)
    }
}

class GeofenceManager: ObservableObject {
    @Published var geofenceAnnotations: [GeofenceAnnotation] = []
    @Published var isLoading: Bool = false
    @Published var isMonitoring: Bool = false

    private let locationManager = CLLocationManager()

    // Register geofencing and update display
    @MainActor
    func registerGeofencing() {
        isLoading = true

        // Register geofencing with Klaviyo SDK
        KlaviyoSDK().registerGeofencing()

        // Wait a moment for the system to process the registration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshGeofences()
        }
    }

    // Unregister geofencing and update display
    @MainActor
    func unregisterGeofencing() {
        isLoading = true

        // Unregister geofencing with Klaviyo SDK
        KlaviyoSDK().unregisterGeofencing()

        // Wait a moment for the system to process the unregistration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshGeofences()
        }
    }

    // Refresh the currently monitored geofences
    func refreshGeofences() {
        isLoading = true

        DispatchQueue.main.async {
            // Get currently monitored regions
            let monitoredRegions = KlaviyoSDK().getCurrentGeofences()

            self.geofenceAnnotations = monitoredRegions.compactMap { region in
                guard let circularRegion = region as? CLCircularRegion else { return nil }

                return GeofenceAnnotation(
                    coordinate: circularRegion.center,
                    title: "Monitored: \(circularRegion.identifier)",
                    radius: circularRegion.radius
                )
            }

            self.isMonitoring = !monitoredRegions.isEmpty
            self.isLoading = false
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var hasRequestedWhenInUse: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus

        // Check if we've previously requested when-in-use permission
        hasRequestedWhenInUse = UserDefaults.standard.bool(forKey: "hasRequestedWhenInUseLocation")
    }

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            // First tap: Request "When In Use" permission
            locationManager.requestWhenInUseAuthorization()
            hasRequestedWhenInUse = true
            UserDefaults.standard.set(true, forKey: "hasRequestedWhenInUseLocation")

        case .authorizedWhenInUse:
            // Second tap: Request "Always" permission
            locationManager.requestAlwaysAuthorization()

        case .denied, .restricted:
            // Open settings if permission was denied
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }

        case .authorizedAlways:
            // Already have full permission, start location updates
            locationManager.startUpdatingLocation()

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted, .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

#Preview {
    MapView()
}
