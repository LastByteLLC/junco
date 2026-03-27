// FileWatcher.swift — FSEvents-based file watching for auto-reindex
//
// Monitors the project directory for file changes and triggers callbacks.
// Uses DispatchSource for efficient kernel-level file monitoring.

import Foundation

/// Watches a directory for file changes using FSEvents.
public actor FileWatcher {
  private let directory: String
  private var stream: FSEventStreamRef?
  private var onChange: (@Sendable () -> Void)?
  private var isWatching = false

  public init(directory: String) {
    self.directory = directory
  }

  /// Start watching for file changes. Calls `handler` on any change.
  public func start(handler: @escaping @Sendable () -> Void) {
    guard !isWatching else { return }
    onChange = handler
    isWatching = true

    let paths = [directory] as CFArray
    var context = FSEventStreamContext()

    // Store handler pointer for C callback
    let handlerBox = Unmanaged.passRetained(CallbackBox(handler)).toOpaque()
    context.info = handlerBox

    let flags: FSEventStreamCreateFlags =
      UInt32(kFSEventStreamCreateFlagUseCFTypes)
      | UInt32(kFSEventStreamCreateFlagFileEvents)
      | UInt32(kFSEventStreamCreateFlagNoDefer)

    stream = FSEventStreamCreate(
      nil,
      { _, info, _, _, _, _ in
        guard let info else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
        box.handler()
      },
      &context,
      paths,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      1.0,  // Latency: 1 second debounce
      flags
    )

    if let stream {
      FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
      FSEventStreamStart(stream)
    }
  }

  /// Stop watching.
  public func stop() {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
    }
    isWatching = false
  }

  // Cleanup handled by stop() — caller must call stop() before releasing.
}

/// Box to pass Swift closure through C callback.
private final class CallbackBox: @unchecked Sendable {
  let handler: @Sendable () -> Void
  init(_ handler: @escaping @Sendable () -> Void) {
    self.handler = handler
  }
}
