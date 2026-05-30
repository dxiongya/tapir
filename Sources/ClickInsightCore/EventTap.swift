import Foundation
import CoreGraphics
import AppKit

public final class EventTap: @unchecked Sendable {
    public typealias Handler = (CGEventType, CGPoint, CGEvent) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, ctx in
            guard let ctx else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(ctx).takeUnretainedValue()
            let p = event.location
            tap.handler(type, p, event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
    }
}
