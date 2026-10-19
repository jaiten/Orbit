import XCTest
import SwiftData
@testable import Orbit

@MainActor final class SyncTests: XCTestCase {
    func testMutationAndTombstoneArePersistedTogether() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let task = PlannerTask(title: "One clear step")
        context.insert(task); try Mutations.save(context)
        let entries = try context.fetch(FetchDescriptor<SyncEntry>())
        XCTAssertEqual(entries.count, 1); XCTAssertTrue(entries[0].dirty)
        let mutation = entries[0].mutation
        context.delete(task); try Mutations.save(context)
        XCTAssertTrue(entries[0].tombstone); XCTAssertNotEqual(entries[0].mutation, mutation)
    }
    func testRemoteTaskPreservesLocalDayAndSubtasks() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let id = UUID().uuidString.lowercased(), subID = UUID().uuidString.lowercased()
        try SyncRecords.apply(["key": "tasks/" + id, "deleted": false, "payload": ["id": id, "title": "Plan", "hasTime": false, "localDate": "2026-10-19", "durationMinutes": 20, "subtasks": [["id": subID, "title": "First step", "completed": true]]]], context: context)
        try context.save()
        let task = try XCTUnwrap(context.fetch(FetchDescriptor<PlannerTask>()).first)
        XCTAssertEqual(PlannerLogic.dayKey(try XCTUnwrap(task.dueDate)), "2026-10-19")
        XCTAssertEqual(task.subtasks.first?.title, "First step"); XCTAssertEqual(task.subtasks.first?.completed, true)
        XCTAssertNotNil(try SyncRecords.snapshots(context)["tasks/" + id])
    }
    func testCaptureDoesNotRequeueUnchangedRecords() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(Habit(title: "Read")); try Mutations.save(context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncEntry>()).first)
        entry.dirty = false; try context.save(); let mutation = entry.mutation
        try SyncRecords.capture(context)
        XCTAssertFalse(entry.dirty); XCTAssertEqual(entry.mutation, mutation)
    }
    func testAccountBindingRejectsDifferentUser() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try SyncRecords.bind("alice", context: container.mainContext)
        XCTAssertThrowsError(try SyncRecords.bind("bob", context: container.mainContext))
    }
}
