import Foundation
import Observation

private struct HealthBody: Decodable {
    var ok: Bool
}

@MainActor
@Observable
public final class PairingModel {
    public private(set) var status: String
    public private(set) var message: String?

    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let pairing: Pairing

    public init(transport: any HTTPTransport, tokenStore: any TokenStore, settings: any SettingsFile) {
        self.transport = transport
        self.pairing = Pairing(tokenStore: tokenStore, settings: settings)
        self.status = pairing.isPaired ? "Paired" : "Not paired"
    }

    public func pair(link: String) async {
        let parsed: PairingLink
        do {
            parsed = try PairingLink.parse(link)
        } catch {
            message = "This link is not valid"
            return
        }
        message = nil
        pairing.save(parsed)
        await checkHealth(parsed)
    }

    private func checkHealth(_ link: PairingLink) async {
        guard let url = URL(string: link.baseURL + "/v1/health") else {
            pairing.clear()
            status = "Not paired"
            message = "This link is not valid"
            return
        }
        let request = HTTPRequest(
            method: "GET", url: url, headers: ["Authorization": "Bearer " + link.token])
        do {
            let response = try await transport.send(request)
            handle(response)
        } catch {
            status = "Not checked"
            message = "The server did not answer"
        }
    }

    private func handle(_ response: HTTPResponse) {
        if response.status == 401 || response.status == 403 {
            pairing.clear()
            status = "Not paired"
            message = "The server did not accept this link"
            return
        }
        let body = try? JSONDecoder().decode(HealthBody.self, from: response.body)
        if response.status == 200, body?.ok == true {
            status = "Paired"
            message = nil
        } else {
            status = "Not checked"
            message = "The server gave an unexpected answer"
        }
    }
}
