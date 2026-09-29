import EventKit
import Foundation

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let response: Response
    let videoURL: URL?

    enum Response: String {
        case accepted, declined, pending, none
        var symbol: String {
            switch self { case .accepted: "checkmark"; case .declined: "xmark"; case .pending: "questionmark"; case .none: "" }
        }
    }

    init(_ event: EKEvent) {
        id = "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(Int(event.startDate.timeIntervalSince1970))"
        title = event.title?.isEmpty == false ? event.title! : "Untitled event"
        startDate = event.startDate; endDate = event.endDate; isAllDay = event.isAllDay
        videoURL = VideoLink.find(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: "\n"))
        guard event.status != .canceled, let participant = event.attendees?.first(where: { $0.isCurrentUser }) else {
            response = event.status == .canceled ? .declined : .none; return
        }
        switch participant.participantStatus {
        case .accepted, .delegated, .completed: response = .accepted
        case .declined: response = .declined
        case .pending, .tentative, .inProcess: response = .pending
        default: response = .none
        }
    }
}

enum VideoLink {
    static func find(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>\]\[\)]+"#) else { return nil }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }; return URL(string: String(text[range]))
        }.first { url in
            let host = url.host?.lowercased() ?? ""
            return host.contains("meet.google") || host.contains("zoom.us") || host.contains("teams.microsoft") || host.contains("teams.live")
        }
    }
}
