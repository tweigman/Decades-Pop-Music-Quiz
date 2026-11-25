import Foundation
import os

/// A small log file for troubleshooting on the phone (debug builds only: a
/// release build keeps nothing it hears). Pull it to the Mac with:
///   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
///     --domain-identifier com.tweigman.popquiz --source Documents/diagnostics.log --destination .
nonisolated enum Diagnostics {
    private static let logger = Logger(subsystem: "com.tweigman.popquiz", category: "diagnostics")
    private static let url = URL.documentsDirectory.appending(path: "diagnostics.log")
    private static let queue = DispatchQueue(label: "diagnostics")

    static func log(_ message: String) {
        #if DEBUG
        logger.notice("\(message, privacy: .public)")
        let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }

    /// Start a fresh log for each launch.
    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
