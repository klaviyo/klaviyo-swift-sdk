import CoreLocation
import KlaviyoLocation
import KlaviyoSwift
import MapKit
import UIKit

class MapViewController: UIViewController {
    // MARK: - Properties

    private var mapView: MKMapView!
    private var locationManager: CLLocationManager!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMapView()
        setupLocationManager()
        addGeofenceOverlays()
    }

    // MARK: - Setup Methods

    private func setupUI() {
        title = "Delivery Map"
        view.backgroundColor = .systemBackground

        // Add close button
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }

    private func setupMapView() {
        mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none

        view.addSubview(mapView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Request location permission
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            showLocationPermissionAlert()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }

    private func addGeofenceOverlays() {
        // Hardcoded geofence locations with semitransparent circle overlays
        let geofences = [
            GeofenceData(
                coordinate: CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589), // Boston
                radius: 1000, // 1km radius
                title: "Boston Delivery Zone",
                subtitle: "Free delivery within 1km"
            ),
            GeofenceData(
                coordinate: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), // New York
                radius: 1500, // 1.5km radius
                title: "NYC Delivery Zone",
                subtitle: "Free delivery within 1.5km"
            ),
            GeofenceData(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
                radius: 2000, // 2km radius
                title: "SF Delivery Zone",
                subtitle: "Free delivery within 2km"
            ),
            GeofenceData(
                coordinate: CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437), // Los Angeles
                radius: 1200, // 1.2km radius
                title: "LA Delivery Zone",
                subtitle: "Free delivery within 1.2km"
            ),
            GeofenceData(
                coordinate: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298), // Chicago
                radius: 1800, // 1.8km radius
                title: "Chicago Delivery Zone",
                subtitle: "Free delivery within 1.8km"
            )
        ]

        for geofence in geofences {
            // Create circle overlay
            let circle = MKCircle(center: geofence.coordinate, radius: geofence.radius)
            mapView.addOverlay(circle)

            // Add annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = geofence.coordinate
            annotation.title = geofence.title
            annotation.subtitle = geofence.subtitle
            mapView.addAnnotation(annotation)
        }

        // Set initial region to show all geofences
        if let firstGeofence = geofences.first {
            let region = MKCoordinateRegion(
                center: firstGeofence.coordinate,
                latitudinalMeters: 10_000,
                longitudinalMeters: 10_000
            )
            mapView.setRegion(region, animated: true)
        }
    }

    private func showLocationPermissionAlert() {
        let alert = UIAlertController(
            title: "Location Permission Required",
            message: "This app needs location access to show your current location on the delivery map. Please enable location access in Settings.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        present(alert, animated: true)
    }

    @objc
    private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension MapViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circleOverlay = overlay as? MKCircle {
            let circleRenderer = MKCircleRenderer(circle: circleOverlay)
            circleRenderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.3)
            circleRenderer.strokeColor = UIColor.systemBlue
            circleRenderer.lineWidth = 2
            return circleRenderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - CLLocationManagerDelegate

extension MapViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Center map on user location
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
        mapView.setRegion(region, animated: true)

        // Stop updating location after first update to save battery
        locationManager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            showLocationPermissionAlert()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            break
        }
    }
}

// MARK: - Helper Struct

struct GeofenceData {
    let coordinate: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let title: String
    let subtitle: String
}
