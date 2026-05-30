import Foundation
import AppKit
import ApplicationServices

public struct ResolvedContext: Sendable {
    public var appName: String?
    public var bundleId: String?
    public var windowTitle: String?
    public var axRole: String?
    public var axSubrole: String?
    public var axTitle: String?
    public var axLabel: String?
    public var axParentChain: String?
}

public enum ContextResolver {
    public static func resolve(at point: CGPoint) -> ResolvedContext {
        var ctx = ResolvedContext()

        if let app = NSWorkspace.shared.frontmostApplication {
            ctx.appName = app.localizedName
            ctx.bundleId = app.bundleIdentifier
            ctx.windowTitle = focusedWindowTitle(for: app.processIdentifier)
        }

        let sys = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = withUnsafeMutablePointer(to: &element) { ptr -> AXError in
            ptr.withMemoryRebound(to: AXUIElement?.self, capacity: 1) { rebound in
                AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), rebound)
            }
        }
        guard result == .success, let el = element else { return ctx }

        ctx.axRole = copyStringAttr(el, kAXRoleAttribute as CFString)
        ctx.axSubrole = copyStringAttr(el, kAXSubroleAttribute as CFString)
        ctx.axTitle = copyStringAttr(el, kAXTitleAttribute as CFString)
        ctx.axLabel = copyStringAttr(el, kAXDescriptionAttribute as CFString)
            ?? copyStringAttr(el, kAXValueAttribute as CFString)
            ?? copyStringAttr(el, kAXHelpAttribute as CFString)

        ctx.axParentChain = parentChain(of: el, depth: 4)
        return ctx
    }

    private static func focusedWindowTitle(for pid: pid_t) -> String? {
        let appEl = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard r == .success, let w = windowRef else { return nil }
        return copyStringAttr(w as! AXUIElement, kAXTitleAttribute as CFString)
    }

    private static func copyStringAttr(_ el: AXUIElement, _ key: CFString) -> String? {
        var ref: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(el, key, &ref)
        guard r == .success else { return nil }
        if let s = ref as? String { return s.isEmpty ? nil : s }
        if let n = ref as? NSNumber { return n.stringValue }
        return nil
    }

    private static func parentChain(of el: AXUIElement, depth: Int) -> String? {
        var parts: [String] = []
        var current: AXUIElement? = el
        var hops = 0
        while let node = current, hops < depth {
            let role = copyStringAttr(node, kAXRoleAttribute as CFString) ?? "?"
            let title = copyStringAttr(node, kAXTitleAttribute as CFString)
            if let t = title, !t.isEmpty {
                parts.append("\(role)[\(t)]")
            } else {
                parts.append(role)
            }
            var pRef: CFTypeRef?
            let r = AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &pRef)
            if r == .success, let pVal = pRef {
                current = (pVal as! AXUIElement)
            } else {
                current = nil
            }
            hops += 1
        }
        return parts.isEmpty ? nil : parts.reversed().joined(separator: " > ")
    }
}
