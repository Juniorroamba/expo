import ExpoModulesCore
import CoreLocation

final class LocationUpdatesTaskConsumer: NSObject, EXTaskConsumerInterface {
  var task: (any EXTaskInterface)?
  var makeStream: (_ profile: Profile) -> PositionUpdates.Stream = { PositionUpdates.stream(for: $0, allowsBackgroundUpdates: true) }
  private(set) var subscription: PositionUpdatesSubscription?
  private let relaunchMonitor = SignificantLocationChangeMonitor()

  func didRegisterTask(_ task: any EXTaskInterface) {
    let options = LocationUpdatesTaskOptions(task.options)
    subscription?.stop()
    subscription = PositionUpdatesSubscription(
      stream: makeStream(options.profile),
      onLocation: { location in
        task.execute(withData: location.toPosition().toEventPayload(), withError: nil)
      },
      onError: { error in
        task.execute(withData: nil, withError: error)
      }
    )

    // liveUpdates relaunches a terminated app on its own; the CLLocationManager path needs
    // significant-change monitoring to be relaunched. It can be removed once we drop support for iOS 17
    if #available(iOS 17.0, *), options.profile != .lowPower {
      return
    }
    relaunchMonitor.start()
  }

  func taskType() -> String {
    return "locationNext"
  }

  func didUnregister() {
    relaunchMonitor.stop()
    subscription?.stop()
    subscription = nil
  }
}
