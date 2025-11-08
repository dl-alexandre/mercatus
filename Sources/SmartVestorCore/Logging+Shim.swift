import Foundation
import Utils

#if os(macOS) || os(Linux)
import Darwin
#endif

extension StructuredLogger {
    public func warning(component: String, event: String, meta: [String: String]? = nil) {
        self.log(level: .warn, component: component, event: event, data: meta ?? [:])
    }
}
