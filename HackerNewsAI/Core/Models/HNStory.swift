import Foundation

struct HNStory {
    let id: Int
    let title: String
    let by: String
    let score: Int
    let time: Int
    let descendants: Int?
    let url: String?
    let text: String?
    let type: String
    let kids: [Int]?

    nonisolated var storyURL: URL? {
        guard let url else { return nil }
        return URL(string: url)
    }

    nonisolated var domain: String? {
        guard let storyURL else { return nil }
        return storyURL.host?.replacingOccurrences(of: "www.", with: "")
    }

    nonisolated var postedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(time))
    }

    nonisolated var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: postedDate, relativeTo: Date())
    }

    nonisolated var isFromToday: Bool {
        Calendar.current.isDateInToday(postedDate)
    }

    nonisolated var commentCount: Int {
        descendants ?? 0
    }
}

nonisolated extension HNStory: Codable, Identifiable, Equatable {}
