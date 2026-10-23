import XCTest
import SwiftData
@testable import Orbit

@MainActor final class SyncTests: XCTestCase {
    func testTaskProgressSurvivesSyncAndDoesNotCompleteUntilFinished() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let task = PlannerTask(title: "Laundry"); context.insert(task)
        try Mutations.setProgress(task, enabled: true, start: true, in: context)
        XCTAssertNotNil(task.startedAt); XCTAssertNil(task.completedAt)
        let key = "tasks/" + task.id.uuidString.lowercased()
        let payload = try SyncRecords.object(XCTUnwrap(SyncRecords.snapshots(context)[key]))
        let otherContainer = try Persistence.makeContainer(inMemory: true)
        let other = otherContainer.mainContext
        try SyncRecords.apply(["key": key, "payload": payload], context: other)
        let restored = try XCTUnwrap(other.fetch(FetchDescriptor<PlannerTask>()).first)
        XCTAssertEqual(restored.progressTracking, true)
        XCTAssertEqual(try XCTUnwrap(restored.startedAt).timeIntervalSince1970, try XCTUnwrap(task.startedAt).timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(restored.completedAt)
        try Mutations.toggle(restored, in: other); XCTAssertNotNil(restored.completedAt)
        try Mutations.toggle(restored, in: other); XCTAssertNil(restored.startedAt)
        try Mutations.setProgress(restored, enabled: false, in: other)
        XCTAssertEqual(restored.progressTracking, false)
    }

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
