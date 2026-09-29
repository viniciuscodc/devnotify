import AppKit
import SwiftUI

private enum AppTab: String, CaseIterable, Identifiable {
    case meetings = "Meetings"
    case pullRequests = "Pull Requests"
    var id: Self { self }
    var symbol: String { self == .meetings ? "calendar" : "arrow.triangle.pull" }
}

struct DevNotifyPopover: View {
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var pullRequests: PRStore
    @ObservedObject var settings: AppSettings
    @AppStorage("selectedAppTab") private var selectedTab = AppTab.meetings.rawValue
    @Environment(\.openSettings) private var openSettings

    private var tab: Binding<AppTab> {
        Binding(get: { AppTab(rawValue: selectedTab) ?? .meetings }, set: { selectedTab = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DEVNOTIFY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(selectedTab == AppTab.meetings.rawValue ? Date.now.formatted(.dateTime.month(.abbreviated).day().year()) : (pullRequests.authenticatedLogin.map { "GitHub · @\($0)" } ?? "Developer notifications"))
                        .font(.headline)
                }
                Spacer()
                Button { settings.notificationsMuted.toggle() } label: {
                    Image(systemName: settings.notificationsMuted ? "bell.slash.fill" : "bell.fill").foregroundStyle(settings.notificationsMuted ? .red : .secondary)
                }.buttonStyle(.plain).help(settings.notificationsMuted ? "Resume all notifications" : "Mute all notifications")
                Button { refresh() } label: {
                    if isLoading { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(.plain).disabled(isLoading).help("Refresh")
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Picker("Section", selection: tab) {
                ForEach(AppTab.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            Group {
                if tab.wrappedValue == .meetings { MeetingListView(store: calendar) }
                else { PullRequestListView(store: pullRequests) }
            }.frame(maxHeight: .infinity)
            Divider()
            HStack {
                Button { showSettings() } label: { Label("Settings", systemImage: "gear") }
                Spacer()
                if tab.wrappedValue == .meetings {
                    Button { NSWorkspace.shared.open(URL(string: "https://calendar.google.com")!) } label: { Label("Calendar", systemImage: "calendar") }
                } else {
                    Button { NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!) } label: { Label("GitHub", systemImage: "safari") }
                }
                Spacer()
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: { Image(systemName: "xmark") }.help("Quit DevNotify")
            }.font(.caption).padding(.horizontal, 16).padding(.vertical, 11)
        }
        .frame(width: tab.wrappedValue == .meetings ? 380 : 440, height: CGFloat(settings.popoverHeight))
        .task { await calendar.refresh(); await pullRequests.refresh() }
    }

    private var isLoading: Bool { tab.wrappedValue == .meetings ? calendar.isLoading : pullRequests.isLoading }
    private func refresh() {
        if tab.wrappedValue == .meetings { Task { await calendar.syncAndRefresh() } }
        else { Task { await pullRequests.refresh() } }
    }
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true); openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeKey && $0.styleMask.contains(.titled) }?.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MeetingListView: View {
    @ObservedObject var store: CalendarStore
    @State private var showsIgnored = false
    var body: some View {
        if let error = store.authorizationError {
            ContentUnavailableView("Calendar unavailable", systemImage: "calendar.badge.exclamationmark", description: Text(error))
        } else if store.isLoading && store.events.isEmpty {
            ProgressView("Loading today’s schedule…")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.currentEvents) { event in
                        MeetingCard(event: event, isCurrent: true, now: store.now) { store.ignore(event) }
                    }
                    if let next = store.next { MeetingCard(event: next, isCurrent: false, now: store.now) { store.ignore(next) } }
                    let later = store.upcoming.filter { $0.id != store.next?.id }
                    if !later.isEmpty {
                        section("UPCOMING", "clock")
                        ForEach(later) { event in MeetingRow(event: event, faded: false) { store.ignore(event) } }
                    }
                    if !store.ignoredEvents.isEmpty {
                        DisclosureGroup(isExpanded: $showsIgnored) {
                            ForEach(store.ignoredEvents) { event in
                                HStack { Text(event.title).lineLimit(1); Spacer(); Button { store.restore(event) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain) }
                                    .font(.caption).foregroundStyle(.tertiary).padding(.leading, 20).padding(.vertical, 4)
                            }
                        } label: { Label("\(store.ignoredEvents.count) ignored", systemImage: "eye.slash").font(.caption).foregroundStyle(.tertiary) }
                            .tint(.secondary).padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    let past = store.events.filter { $0.endDate <= store.now }
                    if !past.isEmpty { section("EARLIER TODAY", "clock.arrow.circlepath"); ForEach(past) { MeetingRow(event: $0, faded: true) } }
                    if store.events.isEmpty { ContentUnavailableView("Nothing on your calendar", systemImage: "cup.and.saucer").frame(maxWidth: .infinity).padding(.vertical, 60) }
                }
            }
        }
    }
    private func section(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 7)
    }
}

private struct MeetingCard: View {
    let event: CalendarEvent; let isCurrent: Bool; let now: Date; let ignore: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isCurrent ? "NOW" : "NEXT IN \(max(1, Int(event.startDate.timeIntervalSince(now) / 60))) MIN", systemImage: isCurrent ? "record.circle.fill" : "clock")
                .font(.caption.weight(.semibold)).foregroundStyle(isCurrent ? .red : .secondary)
            HStack { Text(event.title).font(.headline).lineLimit(2); Spacer(); ResponseBadge(response: event.response) }
            Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                if let url = event.videoURL { Button { NSWorkspace.shared.open(url) } label: { Label("Join video call", systemImage: "video.fill") }.buttonStyle(.borderedProminent) }
                Button(action: ignore) { Label("Ignore", systemImage: "bell.slash") }.buttonStyle(.bordered)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background((isCurrent ? Color.red : Color.accentColor).opacity(0.055))
    }
}

private struct MeetingRow: View {
    let event: CalendarEvent; let faded: Bool; var ignore: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 9) {
            Text(event.startDate.formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            Text(event.title).lineLimit(1); Spacer(); if event.videoURL != nil { Image(systemName: "video") }; ResponseBadge(response: event.response)
            if let ignore { Button(action: ignore) { Image(systemName: "bell.slash") }.buttonStyle(.plain) }
        }.font(.subheadline).padding(.horizontal, 16).padding(.vertical, 7).opacity(faded ? 0.42 : 1)
    }
}

private struct ResponseBadge: View {
    let response: CalendarEvent.Response
    var body: some View { if !response.symbol.isEmpty { Image(systemName: response.symbol).font(.caption.weight(.bold)).foregroundStyle(response == .accepted ? .green : response == .declined ? .red : .orange) } }
}

private struct PullRequestListView: View {
    @ObservedObject var store: PRStore
    @State private var showsIgnored = false
    var body: some View {
        if store.settings.token.isEmpty {
            ContentUnavailableView("Connect GitHub", systemImage: "key.fill", description: Text("Open Settings and add a personal access token."))
        } else if store.isLoading && store.pullRequests.isEmpty { ProgressView("Loading pull requests…") }
        else if store.pullRequests.isEmpty, let error = store.errorMessage { ContentUnavailableView("GitHub unavailable", systemImage: "exclamationmark.triangle", description: Text(error)) }
        else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = store.errorMessage { banner(error, .red, "exclamationmark.triangle.fill") }
                    else if let message = store.actionMessage { banner(message, .green, "checkmark.circle.fill") }
                    prSection("READY TO MERGE", "checkmark.seal.fill", store.ready.count, .green)
                    if store.ready.isEmpty { empty("No approved PRs with passing CI") }
                    ForEach(store.ready) { PRCard(pullRequest: $0, kind: .ready, store: store) }
                    prSection("REVIEW LIST", "person.2.fill", store.review.count, .blue)
                    if store.review.isEmpty { empty("No reviewable PRs with passing CI") }
                    ForEach(store.review) { PRCard(pullRequest: $0, kind: .review, store: store) }
                    prSection("NEEDS REVIEW", "person.badge.clock.fill", store.needsReview.count, .orange)
                    if store.needsReview.isEmpty { empty("None of your PRs are waiting for review") }
                    ForEach(store.needsReview) { PRCard(pullRequest: $0, kind: .needsReview, store: store) }
                    if !store.ignored.isEmpty {
                        DisclosureGroup(isExpanded: $showsIgnored) {
                            ForEach(store.ignored) { pr in HStack { Text("\(pr.repository) #\(pr.number)"); Text(pr.title).lineLimit(1); Spacer(); Button { store.restore(pr) } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(.plain) }.font(.caption).padding(.leading, 20).padding(.vertical, 4) }
                        } label: { Label("\(store.ignored.count) ignored", systemImage: "eye.slash").font(.caption).foregroundStyle(.tertiary) }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
            }
        }
    }
    private func prSection(_ title: String, _ symbol: String, _ count: Int, _ color: Color) -> some View {
        HStack { Image(systemName: symbol).foregroundStyle(color); Text(title); Spacer(); Text("\(count)").padding(.horizontal, 6).background(.quaternary, in: Capsule()) }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 7)
    }
    private func empty(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 16).padding(.bottom, 8) }
    private func banner(_ text: String, _ color: Color, _ symbol: String) -> some View { Label(text, systemImage: symbol).font(.caption).foregroundStyle(color).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.07)) }
}

private enum PRCardKind { case ready, review, needsReview }
private struct PRCard: View {
    let pullRequest: PullRequest; let kind: PRCardKind; @ObservedObject var store: PRStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                AsyncImage(url: pullRequest.authorAvatarURL) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.tertiary) }
                    .frame(width: 30, height: 30).clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) { Text(pullRequest.title).font(.headline).lineLimit(2); Text("\(pullRequest.repository) #\(pullRequest.number) · @\(pullRequest.authorLogin)").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Label(pullRequest.ciState.title, systemImage: pullRequest.ciState.symbol).font(.caption2.weight(.semibold)).foregroundStyle(pullRequest.ciState == .passed ? .green : pullRequest.ciState == .failed ? .red : .orange)
            }
            HStack {
                if kind == .ready { Button { Task { await store.merge(pullRequest) } } label: { Label("Merge", systemImage: "arrow.triangle.merge") }.buttonStyle(.borderedProminent) }
                if pullRequest.ciState == .failed { Button { Task { await store.rerunFailedCI(pullRequest) } } label: { Label("Re-run CI", systemImage: "arrow.clockwise") } }
                Button { store.ignore(pullRequest) } label: { Image(systemName: "eye.slash") }; Spacer()
                Button { store.open(pullRequest) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
            }.buttonStyle(.bordered).controlSize(.small)
        }.padding(12).background((kind == .ready ? Color.green : kind == .review ? Color.blue : Color.orange).opacity(0.055), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 10).padding(.bottom, 7)
    }
}
