import Foundation
import Observation

public enum LocationPermissionState: String, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var temperatureCelsius: Double
    public var weatherCode: Int
    public var cityLabel: String?
    public var fetchedAt: Date

    public init(
        temperatureCelsius: Double,
        weatherCode: Int,
        cityLabel: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.weatherCode = weatherCode
        self.cityLabel = cityLabel
        self.fetchedAt = fetchedAt
    }

    public var formattedTemperature: String {
        "\(Int(temperatureCelsius.rounded()))°C"
    }

    public var symbolName: String {
        Self.symbolName(for: weatherCode)
    }

    public var conditionLabel: String {
        switch weatherCode {
        case 0: return "Clear"
        case 1...3: return "Partly cloudy"
        case 45...48: return "Fog"
        case 51...67: return "Rain"
        case 71...77: return "Snow"
        case 80...99: return "Storm"
        default: return "Cloudy"
        }
    }

    public static func symbolName(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1...3: return "cloud.sun.fill"
        case 45...48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

private struct WeatherCacheRecord: Codable, Equatable, Sendable {
    var snapshot: WeatherSnapshot?
    var lastLatitude: Double?
    var lastLongitude: Double?
}

private struct OpenMeteoResponse: Decodable {
    let current: CurrentBlock

    struct CurrentBlock: Decodable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }
}

private struct WeatherFileStore: FileStore {
    let folder: URL

    init(folderName: String = "chief") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.folder = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func read(_ name: String) throws -> Data? {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func remove(_ name: String) throws {
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func list() throws -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()) ?? []
    }
}

private struct WeatherWallClock: Clock {
    var now: Date { Date() }
}

/// Local location permission + cached Open-Meteo weather state shared by Home and Settings.
@MainActor @Observable
public final class WeatherLocationModel {
    public static let fileName = "weather-cache.json"
    public static let shared = WeatherLocationModel()

    @ObservationIgnored private let files: any FileStore
    @ObservationIgnored private let clock: any Clock

    public private(set) var permissionState: LocationPermissionState = .notDetermined
    public private(set) var currentWeather: WeatherSnapshot?
    public private(set) var lastLatitude: Double?
    public private(set) var lastLongitude: Double?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public init(files: (any FileStore)? = nil, clock: (any Clock)? = nil) {
        self.files = files ?? WeatherFileStore()
        self.clock = clock ?? WeatherWallClock()
        reload()
    }

    public var badgeTemperatureText: String {
        if let currentWeather { return currentWeather.formattedTemperature }
        switch permissionState {
        case .notDetermined: return isLoading ? "Updating…" : "Enable Weather"
        case .authorized: return isLoading ? "Updating…" : "--°C"
        case .denied: return "Location Off"
        case .unavailable: return "Offline"
        }
    }

    public var badgeSymbolName: String {
        if let currentWeather { return currentWeather.symbolName }
        switch permissionState {
        case .notDetermined: return "location.circle"
        case .authorized: return "cloud.sun.fill"
        case .denied, .unavailable: return "location.slash"
        }
    }

    public var badgeAccessibilityLabel: String {
        if let currentWeather {
            return "Weather \(currentWeather.formattedTemperature), \(currentWeather.conditionLabel). Tap to refresh."
        }
        switch permissionState {
        case .notDetermined: return "Weather unavailable. Tap to enable location services."
        case .authorized: return "Weather loading. Tap to refresh."
        case .denied: return "Location access off. Tap for iOS Settings instructions."
        case .unavailable: return "Location services unavailable."
        }
    }

    public var settingsStatusLabel: String {
        if let currentWeather, permissionState == .authorized {
            return "\(currentWeather.formattedTemperature) · Live"
        }
        switch permissionState {
        case .notDetermined: return "Not Enabled"
        case .authorized: return isLoading ? "Updating…" : "Authorized"
        case .denied: return "Location Off"
        case .unavailable: return "Unavailable"
        }
    }

    public var statusCaption: String {
        switch permissionState {
        case .notDetermined:
            return "Enable While Using App location to show live local weather on Home."
        case .authorized:
            if isLoading { return "Refreshing local weather…" }
            if let errorMessage { return errorMessage }
            if let currentWeather {
                if let city = currentWeather.cityLabel, !city.isEmpty {
                    return "\(currentWeather.conditionLabel) in \(city)"
                }
                return "\(currentWeather.conditionLabel) · Updated from Open-Meteo"
            }
            return "Authorized · Waiting for location fix"
        case .denied:
            return "Location access is off. Open iOS Settings › Kit › Location to enable live weather."
        case .unavailable:
            return "Location services are restricted or unavailable on this device."
        }
    }

    public func updatePermission(_ state: LocationPermissionState) {
        permissionState = state
        if state != .authorized { isLoading = false }
        if state == .authorized { errorMessage = nil }
    }

    public func markRequestingLocation() {
        isLoading = true
        errorMessage = nil
    }

    public func applyWeather(_ snapshot: WeatherSnapshot, latitude: Double, longitude: Double) {
        currentWeather = snapshot
        lastLatitude = Self.coarseCoordinate(latitude)
        lastLongitude = Self.coarseCoordinate(longitude)
        isLoading = false
        errorMessage = nil
        persist()
    }

    public func recordLocationError(_ message: String) {
        isLoading = false
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = trimmed.isEmpty ? "Unable to determine location." : trimmed
    }

    public func recordWeatherError(_ message: String) {
        isLoading = false
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = trimmed.isEmpty ? "Weather refresh failed." : trimmed
    }

    public func shouldRefresh(minInterval: TimeInterval = 900) -> Bool {
        guard permissionState == .authorized else { return false }
        guard let fetchedAt = currentWeather?.fetchedAt else { return true }
        return clock.now.timeIntervalSince(fetchedAt) >= minInterval
    }

    nonisolated public static func coarseCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    nonisolated public static func openMeteoURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        let lat = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), coarseCoordinate(latitude))
        let lon = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), coarseCoordinate(longitude))
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: lat),
            URLQueryItem(name: "longitude", value: lon),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
        ]
        return components?.url
    }

    nonisolated public static func parseOpenMeteo(
        data: Data,
        cityLabel: String? = nil,
        fetchedAt: Date = Date()
    ) -> WeatherSnapshot? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data),
              decoded.current.temperature2m.isFinite
        else { return nil }
        return WeatherSnapshot(
            temperatureCelsius: decoded.current.temperature2m,
            weatherCode: decoded.current.weatherCode,
            cityLabel: cityLabel,
            fetchedAt: fetchedAt
        )
    }

    private func reload() {
        guard let data = try? files.read(Self.fileName) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(WeatherCacheRecord.self, from: data) else { return }
        currentWeather = record.snapshot
        lastLatitude = record.lastLatitude
        lastLongitude = record.lastLongitude
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let record = WeatherCacheRecord(
            snapshot: currentWeather,
            lastLatitude: lastLatitude,
            lastLongitude: lastLongitude
        )
        guard let data = try? encoder.encode(record) else { return }
        try? files.write(data, name: Self.fileName)
    }
}
