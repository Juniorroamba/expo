import CoreLocation
import Foundation

enum PositionUpdates {
  typealias Stream = AsyncThrowingStream<CLLocation?, Error>

  static func stream(for profile: Profile, allowsBackgroundUpdates: Bool) -> Stream {
    if profile != .lowPower, #available(iOS 17.0, *) {
      return live(for: profile, allowsBackgroundUpdates: allowsBackgroundUpdates)
    }
    return compatibility(for: profile, allowsBackgroundUpdates: allowsBackgroundUpdates)
  }

  @available(iOS 17.0, *)
  static func live(for profile: Profile, allowsBackgroundUpdates: Bool) -> Stream {
    let (stream, continuation) = Stream.makeStream()
    let backgroundSession = allowsBackgroundUpdates ? CLBackgroundActivitySession() : nil
    let invalidateServiceSession = allowsBackgroundUpdates ? holdAlwaysServiceSession() : {}
    let providerTask = Task {
      do {
        for try await update in CLLocationUpdate.liveUpdates(profile.clLocationUpdateProfile()) {
          guard !Task.isCancelled else {
            break
          }
          if #available(iOS 18.0, *), let failure = LocationUpdateDiagnostics(update).unrecoverableFailure() {
            continuation.finish(throwing: failure)
            return
          }
          continuation.yield(update.location)
        }
        if Task.isCancelled {
          continuation.finish()
        } else {
          continuation.finish(throwing: LocationUpdatesEndedUnexpectedly())
        }
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in
      providerTask.cancel()
      backgroundSession?.invalidate()
      invalidateServiceSession()
    }
    return stream
  }

  static func compatibility(for profile: Profile, allowsBackgroundUpdates: Bool) -> Stream {
    let (stream, continuation) = Stream.makeStream()
    let delegate = CompatibilityDelegate(continuation: continuation)
    DispatchQueue.main.async {
      delegate.start(profile: profile, allowsBackgroundUpdates: allowsBackgroundUpdates)
    }
    continuation.onTermination = { _ in
      DispatchQueue.main.async {
        delegate.stop()
      }
    }
    return stream
  }

  private static func holdAlwaysServiceSession() -> () -> Void {
    guard #available(iOS 18.0, *) else {
      return {}
    }
    let session = CLServiceSession(authorization: .always)
    return {
      session.invalidate()
    }
  }
}

private final class CompatibilityDelegate: NSObject, CLLocationManagerDelegate {
  private lazy var manager = CLLocationManager()
  private let continuation: PositionUpdates.Stream.Continuation

  init(continuation: PositionUpdates.Stream.Continuation) {
    self.continuation = continuation
  }

  func start(profile: Profile, allowsBackgroundUpdates: Bool) {
    manager.delegate = self
    manager.activityType = profile.clActivityType()
    manager.distanceFilter = profile.clDistanceFilter()
    manager.desiredAccuracy = profile.clDesiredAccuracy()
    manager.allowsBackgroundLocationUpdates = allowsBackgroundUpdates
    manager.startUpdatingLocation()
  }

  func stop() {
    manager.stopUpdatingLocation()
    manager.delegate = nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for location in locations {
      continuation.yield(location)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    switch error {
    case CLError.locationUnknown:
      return
    default:
      continuation.finish(throwing: error)
    }
  }
}
