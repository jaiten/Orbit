import Foundation

/// Realtime messages invalidate the local cache; authenticated REST still applies
/// revision checks and owner-scoped data, including missed changes after reconnect.
@MainActor final class RealtimeWakeup {
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var accessToken: String?
    func start(token: String, userID: String, changed: @escaping @MainActor () -> Void) {
        guard !token.isEmpty, socket == nil || accessToken != token else { return }
        stop(); accessToken = token
        var url = URLComponents(string: "wss://uwcwnjwijvawvvffaxdr.supabase.co/realtime/v1/websocket")!
        url.queryItems = [URLQueryItem(name: "apikey", value: "sb_publishable_m0nf1UT5Q2vLryIVocVbXA_-q5tDD53"), URLQueryItem(name: "vsn", value: "2.0.0")]
        let connection = URLSession.shared.webSocketTask(with: url.url!)
        socket = connection; connection.resume()
        reader = Task { [weak self] in
            do {
                let payload: [String: Any] = ["config": ["broadcast": ["ack": false, "self": false], "presence": ["enabled": false], "private": false, "postgres_changes": [["event": "*", "schema": "public", "table": "orbit_records", "filter": "user_id=eq." + userID]]], "access_token": token]
                try await connection.send(.string(Self.frame(join: "1", ref: "1", topic: "realtime:orbit", event: "phx_join", payload: payload)))
                while !Task.isCancelled {
                    let message = try await connection.receive()
                    let data: Data
                    switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: continue }
                    guard let frame = try JSONSerialization.jsonObject(with: data) as? [Any], frame.count == 5, let event = frame[3] as? String else { continue }
                    if event == "postgres_changes" { changed() }
                    if event == "phx_reply", frame[1] as? String == "1" {
                        guard (frame[4] as? [String: Any])?["status"] as? String == "ok" else { throw URLError(.cannotConnectToHost) }
                        changed()
                    }
                    if event == "phx_error" || event == "phx_close" { throw URLError(.networkConnectionLost) }
                }
            } catch { if self?.socket === connection { self?.stop() } }
        }
        heartbeat = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(20))
                    try await connection.send(.string(Self.frame(join: nil, ref: UUID().uuidString, topic: "phoenix", event: "heartbeat", payload: [:])))
                }
            } catch { if self?.socket === connection { self?.stop() } }
        }
    }
    func stop() { reader?.cancel(); heartbeat?.cancel(); socket?.cancel(with: .normalClosure, reason: nil); socket = nil; accessToken = nil }
    private static func frame(join: String?, ref: String, topic: String, event: String, payload: [String: Any]) throws -> String {
        let frame: [Any] = [join.map { $0 as Any } ?? NSNull(), ref, topic, event, payload]
        return String(data: try JSONSerialization.data(withJSONObject: frame), encoding: .utf8)!
    }
}
