import CoreLocation
import Foundation
import UIKit
import Core

/// CoreLocation + Open-Meteo adapter updating WeatherLocationModel without extra capture payload keys.
@MainActor
final class LocationWeatherAdapter: NSObject, CLLocationManagerDelegate {
    static let shared = LocationWeatherAdapter()

    private let model: WeatherLocationModel
    private let manager: CLLocationManager
    private let session: URLSession
    private var fetchTask: _Concurrency.Task<Void, Never>?
    private var lastFetchAt: Date?

    init(model: WeatherLocationModel = .shared, session: URLSession = .shared) {
        self.model = model
        self.session = session
        self.manager = CLLocationManager()
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        syncPermissionState()
    }

    func requestLocationAndRefresh() {
        syncPermissionState()
        switch manager.authorizationStatus {
        case .notDetermined:
            model.markRequestingLocation()
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            model.markRequestingLocation()
            manager.requestLocation()
        case .denied:
            openAppSettings()
        case .restricted:
            model.updatePermission(.unavailable)
        @unknown default:
            model.updatePermission(.unavailable)
        }
    }

    func refreshIfAuthorized() {
        syncPermissionState()
        guard model.permissionState == .authorized, model.shouldRefresh() else { return }
        model.markRequestingLocation()
        if let lat = model.lastLatitude, let lon = model.lastLongitude, model.currentWeather == nil {
            fetchWeather(latitude: lat, longitude: lon)
        }
        manager.requestLocation()
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        _Concurrency.Task { @MainActor [weak self] in
            self?.handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let lat = latest.coordinate.latitude
        let lon = latest.coordinate.longitude
        _Concurrency.Task { @MainActor [weak self] in
            self?.handleCoordinate(latitude: lat, longitude: lon)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        _Concurrency.Task { @MainActor [weak self] in
            self?.model.recordLocationError(message)
        }
    }

    private func syncPermissionState() {
        model.updatePermission(Self.mapPermission(manager.authorizationStatus))
    }

    private func handleAuthorizationChange() {
        syncPermissionState()
        if model.permissionState == .authorized {
            model.markRequestingLocation()
            manager.requestLocation()
        }
    }

    private func handleCoordinate(latitude: Double, longitude: Double) {
        let coarseLat = WeatherLocationModel.coarseCoordinate(latitude)
        let coarseLon = WeatherLocationModel.coarseCoordinate(longitude)
        if let lastFetchAt, Date().timeIntervalSince(lastFetchAt) < 60,
           model.lastLatitude == coarseLat, model.lastLongitude == coarseLon,
           model.currentWeather != nil {
            return
        }
        fetchWeather(latitude: coarseLat, longitude: coarseLon)
    }

    private func fetchWeather(latitude: Double, longitude: Double) {
        guard let url = WeatherLocationModel.openMeteoURL(latitude: latitude, longitude: longitude) else {
            model.recordWeatherError("Invalid weather request URL.")
            return
        }
        fetchTask?.cancel()
        let urlSession = session
        fetchTask = _Concurrency.Task { [weak self] in
            do {
                let (data, response) = try await urlSession.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status),
                      let snapshot = WeatherLocationModel.parseOpenMeteo(data: data, fetchedAt: Date())
                else {
                    self?.model.recordWeatherError("Weather update unavailable.")
                    return
                }
                self?.lastFetchAt = Date()
                self?.model.applyWeather(snapshot, latitude: latitude, longitude: longitude)
            } catch is CancellationError {
                return
            } catch {
                self?.model.recordWeatherError("Weather update failed.")
            }
        }
    }

    private static func mapPermission(_ status: CLAuthorizationStatus) -> LocationPermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .unavailable
        @unknown default: return .unavailable
        }
    }
}
