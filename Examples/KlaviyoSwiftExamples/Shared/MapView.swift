import CoreLocation
import KlaviyoLocation
import KlaviyoSwift
import MapKit
import SwiftUI

struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                ZStack {
                    Map(coordinateRegion: $locationManager.region,
                        showsUserLocation: true,
                        userTrackingMode: .none,
                        annotationItems: geofenceAnnotations) { annotation in
                            MapAnnotation(coordinate: annotation.coordinate) {
                                VStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                                    Text(annotation.title)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red)
                                        .cornerRadius(8)
                                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                }
                            }
                        }
                        .onAppear {
                            locationManager.requestLocationPermission()
                            KlaviyoSDK().registerGeofencing()
                        }

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

                            Text("Delivery Map")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)

                            Spacer()

                            // Location status indicator
                            Image(systemName: locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways ? "location.fill" : "location.slash")
                                .foregroundColor(locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways ? .green : .red)
                                .font(.title3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        Spacer()
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

    private var geofenceAnnotations: [GeofenceAnnotation] {
        [
            GeofenceAnnotation(coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589), title: "Boston Delivery Zone"),
            GeofenceAnnotation(coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), title: "NYC Delivery Zone"),
            GeofenceAnnotation(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), title: "SF Delivery Zone"),
            GeofenceAnnotation(coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), title: "LA Delivery Zone"),
            GeofenceAnnotation(coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298), title: "Chicago Delivery Zone")
        ]
    }

    private var geofenceOverlays: [GeofenceOverlay] {
        // This would need to be calculated based on map scale
        // For now, return empty array as overlays are complex in SwiftUI
        []
    }
}

struct GeofenceAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

struct GeofenceOverlay: Identifiable {
    let id = UUID()
    let position: CGPoint
    let radius: CGFloat
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
        case .denied, .restricted:
            break
        case .authorizedWhenInUse, .authorizedAlways:
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
        case .denied, .restricted:
            break
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}

#Preview {
    MapView()
}
