import Foundation
import Security
import Core

struct URLSessionTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] { headers[String(describing: key)] = String(describing: value) }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}

struct UserDefaultsSettings: SettingsFile {
    private let key = "chief.baseURL"
    func loadBaseURL() -> String? { UserDefaults.standard.string(forKey: key) }
    func saveBaseURL(_ url: String) { UserDefaults.standard.set(url, forKey: key) }
    func clearBaseURL() { UserDefaults.standard.removeObject(forKey: key) }
}

struct KeychainTokenStore: TokenStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "chief.token"]
    }

    func loadToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) {
        deleteToken()
        var request = query
        request[kSecValueData as String] = Data(token.utf8)
        _ = SecItemAdd(request as CFDictionary, nil)
    }

    func deleteToken() { SecItemDelete(query as CFDictionary) }
}
