// Actor with isolated state and async methods
import Foundation

actor DownloadTracker {
    private var activeDownloads: [URL: Double] = [:]
    private var completedCount = 0

    var inProgressCount: Int {
        activeDownloads.count
    }

    func startDownload(url: URL) {
        activeDownloads[url] = 0.0
    }

    func updateProgress(url: URL, fraction: Double) {
        activeDownloads[url] = fraction
    }

    func completeDownload(url: URL) {
        activeDownloads.removeValue(forKey: url)
        completedCount += 1
    }

    func summary() -> String {
        "Active: \(activeDownloads.count), Completed: \(completedCount)"
    }
}
