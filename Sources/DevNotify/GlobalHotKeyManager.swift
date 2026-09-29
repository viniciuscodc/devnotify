import Carbon
import Foundation

private func devNotifyHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let data else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(data).takeUnretainedValue()
    var identifier = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    Task { @MainActor in manager.perform(id: identifier.id) }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let joinMeeting: () -> Void
    private let openReady: () -> Void
    private let openReview: () -> Void

    init(joinMeeting: @escaping () -> Void, openReady: @escaping () -> Void, openReview: @escaping () -> Void) {
        self.joinMeeting = joinMeeting; self.openReady = openReady; self.openReview = openReview
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), devNotifyHotKeyHandler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }

    func configure(using settings: AppSettings) {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll()
        if settings.meetingShortcutEnabled { register(key: settings.meetingShortcutKey, id: 1) }
        if settings.readyHotKeyEnabled { register(key: settings.readyHotKey, id: 2) }
        if settings.reviewHotKeyEnabled { register(key: settings.reviewHotKey, id: 3) }
    }

    func perform(id: UInt32) {
        if id == 1 { joinMeeting() }; if id == 2 { openReady() }; if id == 3 { openReview() }
    }

    private func register(key: String, id: UInt32) {
        guard let keyCode = Self.keyCodes[key.uppercased()] else { return }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4456_4E54, id: id),
                            GetApplicationEventTarget(), 0, &ref)
        if let ref { refs.append(ref) }
    }

    private static let keyCodes: [String: UInt32] = [
        "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
        "K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17,
        "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6
    ]
}
