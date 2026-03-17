import Foundation

enum CallDirection: String, Codable {
    case inbound
    case outbound
}

struct CallDetailRecord: Identifiable, Codable {
    let id: UUID
    let phoneNumber: String       // raw number or label (e.g. "+15551234567" or "Incoming Call")
    let direction: CallDirection
    let timestamp: Date
    var duration: TimeInterval

    /// Human-friendly number for UI rows, derived from phoneNumber.
    var displayNumber: String {
        return Self.formatPhoneNumber(phoneNumber)
    }

    /// A missed call is an inbound call with zero duration.
    var isMissed: Bool { direction == .inbound && duration == 0 }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Subtitle shown below the phone number in the recents list.
    var callSubtitle: String {
        if isMissed {
            return "Missed Call"
        }
        let type = direction == .outbound ? "Outgoing" : "Incoming"
        if duration > 0 {
            return "\(type) · \(formattedDuration)"
        }
        return type
    }

    /// Short date string for the right side of the recents row (iOS Phone style).
    var formattedDate: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(timestamp) {
            return Self.timeFormatter.string(from: timestamp)
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: Date()),
                  timestamp > weekAgo {
            return Self.weekdayFormatter.string(from: timestamp)
        } else {
            return Self.dateFormatter.string(from: timestamp)
        }
    }

    // MARK: - Static Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static func formatPhoneNumber(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }

        if digits.count == 11, digits.first == "1" {
            let area = digits.dropFirst(1).prefix(3)
            let mid = digits.dropFirst(4).prefix(3)
            let last = digits.dropFirst(7)
            return "+1 (\(area)) \(mid)-\(last)"
        }

        if digits.count == 10 {
            let area = digits.prefix(3)
            let mid = digits.dropFirst(3).prefix(3)
            let last = digits.dropFirst(6)
            return "(\(area)) \(mid)-\(last)"
        }

        return value
    }
}
