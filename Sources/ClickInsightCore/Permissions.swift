import Foundation
import ApplicationServices

public enum Permissions {
    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
