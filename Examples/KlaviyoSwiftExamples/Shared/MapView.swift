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
            ZStack {
                Map(coordinateRegion: $locationManager.region,
                    showsUserLocation: true,
                    userTrackingMode: .none,
                    annotationItems: geofenceAnnotations) { annotation in
                        MapAnnotation(coordinate: annotation.coordinate) {
                            VStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title)
                                Text(annotation.title)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(4)
                                    .background(Color.white)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .overlay(
                        ForEach(geofenceOverlays, id: \.id) { overlay in
                            Circle()
//                            .stroke(Color.blue, lineWidth: 2)
//                            .fill(Color.blue.opacity(0.3))
                                .frame(width: overlay.radius * 2, height: overlay.radius * 2)
                                .position(overlay.position)
                        }
                    )
                    .onAppear {
                        locationManager.requestLocationPermission()
                        KlaviyoSDK().registerGeofencing()
                    }

                if locationManager.authorizationStatus == .denied {
                    VStack {
                        Image(systemName: "location.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                        Text("Location Access Required")
                            .font(.headline)
                        Text("Please enable location access in Settings to view your location on the map.")
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
            .navigationTitle("Delivery Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
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
