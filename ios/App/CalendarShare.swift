import CryptoKit
import EventKit
import Foundation

/// Shares the calendars Orbit reads on this iPhone with Orbit's other devices through sync, and applies
/// changes made there. Each calendar is a `calendars/<id>` record and each event occurrence in a window
/// around today an `events/<id>` record. Windows can't reach the calendar itself, so it asks for an edit
/// or a delete by adding a `request` to an event record; this device makes the change in the calendar,
/// then writes the event back without the request. Records are written only by the device that shares
/// them, so a second iPhone or iPad never removes another device's calendars.
@MainActor enum CalendarShare {
    static let daysBack = 14, daysAhead = 120
    typealias Put = (_ key: String, _ payload: [String: Any], _ deleted: Bool, _ base: Int) async throws -> Void
    private struct Record { let payload: [String: Any]; let revision: Int; let deleted: Bool }

    static func owns(_ key: String) -> Bool { key.hasPrefix("calendars/") || key.hasPrefix("events/") }

    /// This installation's id, so records shared by other devices are left alone.
    static var device: String {
        if let value = UserDefaults.standard.string(forKey: "calendarShareDevice") { return value }
        let value = UUID().uuidString.lowercased(); UserDefaults.standard.set(value, forKey: "calendarShareDevice"); return value
    }
    /// Sharing is on while calendars are connected, unless it was turned off in Settings.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "calendarShareEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "calendarShareEnabled") }
    }

    static func hash(_ text: String) -> String { String(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)) }
    static func calendarID(_ calendar: EKCalendar) -> String { hash("calendar|" + calendar.calendarIdentifier) }
    static func occurrence(_ event: EKEvent) -> Date { (event.occurrenceDate as Date?) ?? event.startDate }
    static func eventID(_ event: EKEvent) -> String {
        hash("event|" + (event.eventIdentifier ?? event.calendarItemIdentifier) + "|" + String(Int64(occurrence(event).timeIntervalSince1970 * 1000)))
    }
    static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func day(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    static func hex(_ color: CGColor?) -> String {
        guard let color, let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, rgb.count >= 3 else { return "#8e8e93" }
        return String(format: "#%02x%02x%02x", Int(max(0, min(1, rgb[0])) * 255), Int(max(0, min(1, rgb[1])) * 255), Int(max(0, min(1, rgb[2])) * 255))
    }

    static func payload(_ calendar: EKCalendar, shown: Bool) -> [String: Any] {
        ["id": calendarID(calendar), "device": device, "title": calendar.title, "account": calendar.source?.title ?? "", "color": hex(calendar.cgColor), "writable": calendar.allowsContentModifications, "shown": shown]
    }
    static func payload(_ event: EKEvent) -> [String: Any] {
        var value: [String: Any] = ["id": eventID(event), "device": device, "ref": event.eventIdentifier ?? event.calendarItemIdentifier, "occurrence": ms(occurrence(event)), "calendarID": calendarID(event.calendar), "title": event.title ?? "Event", "allDay": event.isAllDay, "recurring": event.hasRecurrenceRules]
        if event.isAllDay {
            // EventKit ends an all-day event at the end of its last day; Orbit stores the day after.
            let last = event.endDate.addingTimeInterval(-1) > event.startDate ? event.endDate.addingTimeInterval(-1) : event.startDate
            value["startDay"] = dayKey(event.startDate)
            value["endDay"] = dayKey(Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last)
        } else {
            value["start"] = ms(event.startDate); value["end"] = ms(max(event.endDate, event.startDate))
        }
        return value
    }

    /// Runs after each sync's download with the calendar records it received.
    static func sync(_ records: [[String: Any]], put: Put) async throws {
        let bridge = CalendarBridge.shared
        var server: [String: Record] = [:]
        for record in records {
            guard let key = record["key"] as? String, owns(key), let payload = record["payload"] as? [String: Any] else { continue }
            server[key] = Record(payload: payload, revision: record["revision"] as? Int ?? 0, deleted: record["deleted"] as? Bool ?? false)
        }
        let mine = server.filter { !$0.value.deleted && ($0.value.payload["device"] as? String) == device }
        guard bridge.connected, enabled else {
            // Disconnected or sharing turned off: take this device's calendars off the other devices.
            for (key, record) in mine { try await put(key, record.payload, true, record.revision) }
            return
        }
        // Changes asked for on another device.
        var changed = false
        for (key, record) in mine where key.hasPrefix("events/") {
            if let request = record.payload["request"] as? [String: Any] { apply(request, to: record.payload, store: bridge.store); changed = true }
        }
        if changed { bridge.reload() }
        // Calendars, keeping a show/hide choice made on another device.
        var desired: [String: [String: Any]] = [:]
        var synced = UserDefaults.standard.dictionary(forKey: "calendarShownSynced") as? [String: Bool] ?? [:]
        for calendar in bridge.store.calendars(for: .event) {
            let id = calendarID(calendar), local = bridge.isShown(calendar), last = synced[id]
            var shown = local
            if let remote = server["calendars/" + id], !remote.deleted, let value = remote.payload["shown"] as? Bool, let last, local == last, value != last {
                shown = value; bridge.setShown(calendar, value)
            }
            synced[id] = shown
            desired["calendars/" + id] = payload(calendar, shown: shown)
        }
        UserDefaults.standard.set(synced, forKey: "calendarShownSynced")
        // Events in the shared window, from the calendars that are shown.
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Calendar.current.startOfDay(for: .now))!
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start)!
        for event in bridge.events(from: start, to: end) { desired["events/" + eventID(event)] = payload(event) }
        for (key, value) in desired {
            if let current = server[key], !current.deleted, NSDictionary(dictionary: current.payload).isEqual(to: value) { continue }
            if let current = server[key], !current.deleted, (current.payload["device"] as? String) != device { continue }
            try await put(key, value, false, server[key]?.revision ?? 0)
        }
        for (key, record) in mine where desired[key] == nil { try await put(key, record.payload, true, record.revision) }
    }

    /// Makes a change asked for on another device. A change the calendar refuses is dropped: the event is
    /// shared again as it is.
    static func apply(_ request: [String: Any], to payload: [String: Any], store: EKEventStore) {
        guard let ref = payload["ref"] as? String, let stamp = (payload["occurrence"] as? NSNumber)?.doubleValue else { return }
        let date = Date(timeIntervalSince1970: stamp / 1000)
        let nearby = store.events(matching: store.predicateForEvents(withStart: date.addingTimeInterval(-2 * 86400), end: date.addingTimeInterval(2 * 86400), calendars: nil))
        guard let event = nearby.first(where: { $0.eventIdentifier == ref && abs(occurrence($0).timeIntervalSince(date)) < 1 }), event.calendar.allowsContentModifications else { return }
        switch request["kind"] as? String {
        case "delete":
            try? store.remove(event, span: .thisEvent, commit: true)
        case "edit":
            if let title = (request["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { event.title = title }
            if request["allDay"] as? Bool == true, let first = (request["startDay"] as? String).flatMap(day) {
                let after = (request["endDay"] as? String).flatMap(day) ?? Calendar.current.date(byAdding: .day, value: 1, to: first)!
                event.isAllDay = true; event.startDate = first
                event.endDate = max(first, Calendar.current.date(byAdding: .day, value: -1, to: after) ?? first)
            } else if let start = (request["start"] as? NSNumber)?.doubleValue, let end = (request["end"] as? NSNumber)?.doubleValue {
                event.isAllDay = false
                event.startDate = Date(timeIntervalSince1970: start / 1000)
                event.endDate = Date(timeIntervalSince1970: max(end, start + 5 * 60000) / 1000)
            }
            try? store.save(event, span: .thisEvent, commit: true)
        default: break
        }
    }
}
