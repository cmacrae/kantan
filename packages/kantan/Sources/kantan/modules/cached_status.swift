import Foundation

/// Thread-safe holder for a cached snapshot used by event-driven modules.
///
/// Event-driven modules (power, volume, wifi, bluetooth) write the snapshot
/// from system-callback threads (CoreAudio, IOKit, NotificationCenter) and
/// read it from the main thread render path. `CachedStatus` centralises the
/// `NSLock` + optional-with-fallback boilerplate that each module had
/// hand-rolled.
final class CachedStatus<S: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: S?
  private let fallback: S

  init(fallback: S) {
    self.fallback = fallback
  }

  /// Return the current snapshot, or the fallback if none has been set.
  func get() -> S {
    lock.lock()
    defer { lock.unlock() }
    return value ?? fallback
  }

  /// Replace the snapshot atomically.
  func set(_ newValue: S) {
    lock.lock()
    value = newValue
    lock.unlock()
  }

  /// Atomic read-modify-write. The closure runs under the lock and may
  /// replace the inner storage. Callers can use this to coordinate
  /// companion state that needs to change in the same critical section.
  func mutate<R>(_ body: (inout S?) -> R) -> R {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}
