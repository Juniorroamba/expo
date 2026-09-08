import CoreLocation
import Foundation

final class PositionUpdatesSubscription {
  private let sink: Sink
  private let task: Task<Void, Never>

  init(
    stream: PositionUpdates.Stream,
    interval: TimeInterval = 0,
    onLocation: @escaping (CLLocation) -> Void,
    onError: @escaping (Error) -> Void
  ) {
    let sink = Sink(interval: interval, onLocation: onLocation, onError: onError)
    self.sink = sink
    self.task = Task { @MainActor [weak sink] in
      do {
        for try await location in stream {
          guard let sink, sink.isActive else {
            break
          }
          sink.deliver(location)
        }
      } catch {
        sink?.fail(error)
      }
      sink?.deactivate()
    }
  }

  var isActive: Bool {
    sink.isActive
  }

  func stop() {
    sink.deactivate()
    task.cancel()
  }

  deinit {
    stop()
  }
}

private extension PositionUpdatesSubscription {
  final class Sink {
    private let lock = NSRecursiveLock()
    private let interval: TimeInterval
    private let onLocation: (CLLocation) -> Void
    private let onError: (Error) -> Void
    private var lastEmittedAt: Date?
    private var active = true

    init(interval: TimeInterval, onLocation: @escaping (CLLocation) -> Void, onError: @escaping (Error) -> Void) {
      self.interval = interval
      self.onLocation = onLocation
      self.onError = onError
    }

    var isActive: Bool {
      lock.withLock {
        active
      }
    }

    func deactivate() {
      lock.withLock {
        active = false
      }
    }

    func deliver(_ location: CLLocation?) {
      lock.withLock {
        guard active, let location, isOutsideInterval(location) else {
          return
        }
        lastEmittedAt = location.timestamp
        onLocation(location)
      }
    }

    func fail(_ error: Error) {
      lock.withLock {
        guard active else {
          return
        }
        onError(error)
      }
    }

    private func isOutsideInterval(_ location: CLLocation) -> Bool {
      guard let lastEmittedAt else {
        return true
      }
      return location.timestamp.timeIntervalSince(lastEmittedAt) >= interval
    }
  }
}
