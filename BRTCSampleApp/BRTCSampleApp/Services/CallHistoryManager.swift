import Foundation

@Observable
final class CallHistoryManager {
    private static let storageKey = "callHistory"

    private(set) var records: [CallDetailRecord] = []

    init() {
        records = Self.load()
    }

    // MARK: - Public API

    /// Add a new call record (inserted at the front).
    func addRecord(_ record: CallDetailRecord) {
        records.insert(record, at: 0)
        save()
    }

    /// Update the duration of an existing record (called when a call ends).
    func updateDuration(id: UUID, duration: TimeInterval) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].duration = duration
        save()
    }

    /// Delete a single record.
    func deleteRecord(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    /// Delete records at specific offsets (for List .onDelete).
    func deleteRecords(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    /// Remove all records.
    func clearAll() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [CallDetailRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([CallDetailRecord].self, from: data) else {
            return []
        }
        return records
    }
}
