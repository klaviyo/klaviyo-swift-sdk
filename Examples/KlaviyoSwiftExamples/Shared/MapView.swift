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
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $locationManager.region,
                    showsUserLocation: true,
                    userTrackingMode: .none,
                    annotationItems: geofenceManager.geofenceAnnotations) { annotation in
                        MapAnnotation(coordinate: annotation.coordinate) {
                            GeofenceAnnotationView(annotation: annotation)
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
                    .ignoresSafeArea()

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

                if locationManager.authorizationStatus == .denied {
                    LocationPermissionView()
                }
            }
            .navigationTitle("Geofence Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Location Permissions") {
                            Label(locationStatusLabel.status, systemImage: locationStatusLabel.systemImage)
                                .foregroundStyle(locationStatusLabel.color, locationStatusLabel.color)

                            Button(locationStatusLabel.actionText) {
                                locationManager.requestLocationPermission()
                            }
                        }

                        Section("Geofence Monitoring") {
                            Button {} label: {
                                Label(geofenceMonitoringLabel.title, systemImage: geofenceMonitoringLabel.systemImage)
                                if locationManager.authorizationStatus != .authorizedAlways {
                                    Text("Location permission must be \"Authorized Always\"")
                                }
                            }
                            .disabled(true)

                            Button {
                                geofenceManager.registerGeofencing()
                            } label: {
                                Text("Register")
                                Text("Begin monitoring for geofence events")
                                Image(systemName: "play")
                            }
                            .disabled(geofenceManager.isLoading)

                            Button {
                                geofenceManager.unregisterGeofencing()
                            } label: {
                                Text("Unregister")
                                Text("Stop monitoring for geofence events")
                                Image(systemName: "stop")
                            }
                            .disabled(geofenceManager.isLoading)
                        }
                    } label: {
                        HStack {
                            Image(systemName: geofenceMonitoringLabel.systemImage)
                                .foregroundColor(geofenceMonitoringLabel.color)

                            Image(systemName: locationStatusLabel.systemImage)
                                .foregroundColor(locationStatusLabel.color)
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var locationStatusLabel: (status: String, actionText: String, systemImage: String, color: Color) {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            return (
                status: "Not determined",
                actionText: "Tap to enable",
                systemImage: "location.slash",
                color: .orange
            )
        case .denied:
            return (
                status: "Denied",
                actionText: "Go to settings",
                systemImage: "location.slash",
                color: .red
            )
        case .restricted:
            return (
                status: "Restricted",
                actionText: "Go to settings",
                systemImage: "location.slash",
                color: .red
            )
        case .authorizedWhenInUse:
            return (
                status: "Authorized when in use",
                actionText: "Tap for Always",
                systemImage: "location",
                color: .yellow
            )
        case .authorizedAlways:
            return (
                status: "Authorized always",
                actionText: "Enabled",
                systemImage: "location.fill",
                color: .green
            )
        @unknown default:
            return (
                status: "Unknown",
                actionText: "Unknown",
                systemImage: "location.slash",
                color: .red
            )
        }
    }

    private var geofenceMonitoringLabel: (title: String, systemImage: String, color: Color) {
        if geofenceManager.isMonitoring {
            return ("Montitoring Active", "mappin.and.ellipse", Color.green)
        } else {
            return ("Not Monitoring", "mappin.slash", Color.gray)
        }
    }
}

struct GeofenceAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let radius: Double
}

struct GeofenceAnnotationView: View {
    let annotation: GeofenceAnnotation

    var body: some View {
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

struct LocationPermissionView: View {
    var body: some View {
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
        .padding(.horizontal, 40)
    }
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

    @MainActor
    func unregisterGeofencing() {
        isLoading = true
        KlaviyoSDK().unregisterGeofencing()

        // Wait a moment for the system to process the unregistration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshGeofences()
        }
    }

    func refreshGeofences() {
        isLoading = true

        DispatchQueue.main.async {
            let monitoredRegions = CLLocationManager().monitoredRegions

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

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()

        case .denied, .restricted:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }

        case .authorizedAlways:
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

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
}

#Preview {
    MapView()
}
