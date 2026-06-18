import Foundation

struct HNComment {
    let id: Int
    let by: String?
    let text: String?
    let time: Int
    let parent: Int
    let kids: [Int]?
    let type: String

    nonisolated var author: String {
        by ?? "[deleted]"
    }

    nonisolated var content: String {
        text ?? "[deleted]"
    }

    nonisolated var postedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(time))
    }

    nonisolated var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: postedDate, relativeTo: Date())
    }

    nonisolated var childCount: Int {
        kids?.count ?? 0
    }
}

nonisolated extension HNComment: Codable, Identifiable {}
