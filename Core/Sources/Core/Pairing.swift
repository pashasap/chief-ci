import Foundation

public protocol TokenStore: Sendable {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func deleteToken()
}

public protocol SettingsFile: Sendable {
    func loadBaseURL() -> String?
    func saveBaseURL(_ url: String)
    func clearBaseURL()
}

/// Stores the pairing (base URL in the settings file, token in the token store).
public struct Pairing: Sendable {
    private let tokenStore: any TokenStore
    private let settings: any SettingsFile

    public init(tokenStore: any TokenStore, settings: any SettingsFile) {
        self.tokenStore = tokenStore
        self.settings = settings
    }

    public var baseURL: String? { settings.loadBaseURL() }
    public var token: String? { tokenStore.loadToken() }
    public var isPaired: Bool { baseURL != nil && token != nil }

    public func save(_ link: PairingLink) {
        settings.saveBaseURL(link.baseURL)
        tokenStore.saveToken(link.token)
    }

    public func clear() {
        tokenStore.deleteToken()
        settings.clearBaseURL()
    }
}
