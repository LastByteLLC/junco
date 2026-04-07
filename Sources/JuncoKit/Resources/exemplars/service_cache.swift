// Simple in-memory cache actor with dictionary and expiry
import Foundation

actor Cache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let expiresAt: Date
    }

    private var storage: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    func get(_ key: String) -> Value? {
        guard let entry = storage[key],
              entry.expiresAt > Date.now else {
            storage[key] = nil
            return nil
        }
        return entry.value
    }

    func set(_ key: String, value: Value) {
        storage[key] = Entry(value: value, expiresAt: Date.now.addingTimeInterval(ttl))
    }

    func clear() {
        storage.removeAll()
    }
}
