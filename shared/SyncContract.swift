// Phase 2 boundary, deliberately excluded from the local-only iOS target.
import Foundation

struct SyncEnvelope: Codable, Sendable {
    let id: UUID
    let userID: UUID
    let entity: Entity
    let payload: Data
    let baseRevision: String?
    let mutationID: UUID
    let deleted: Bool
    enum Entity: String, Codable, Sendable {
        case lists, tasks, habits
        case habitLogs = "habit_logs"
        case ideaPrompts = "idea_prompts"
    }
}

/// Implement with authenticated Supabase transport only after UX validation.
/// Realtime is an invalidation signal; reconnect must always perform a durable pull.
protocol SyncTransport: Sendable {
    func push(_ changes: [SyncEnvelope]) async throws
    func pull(after cursor: String?) async throws -> (changes: [SyncEnvelope], cursor: String)
    func invalidations() -> AsyncThrowingStream<Void, Error>
}

/// Commit entity + outbox together. Never clear a newer mutation when an older
/// in-flight request is acknowledged. Outbox is scoped to the signed-in user.
protocol SyncRepository: Sendable {
    func pendingChanges() async throws -> [SyncEnvelope]
    func acknowledge(mutationIDs: [UUID]) async throws
    func applyRemote(_ changes: [SyncEnvelope], cursor: String) async throws
}
