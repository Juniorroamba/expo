import CoreLocation

@testable import ExpoLocation

final class FakeUpdatesSource: @unchecked Sendable {
  private(set) var openCount = 0
  private(set) var terminationCount = 0
  private(set) var continuations: [AsyncThrowingStream<CLLocation?, Error>.Continuation] = []
  private let profiles: AsyncStream<Profile>
  private let profilesContinuation: AsyncStream<Profile>.Continuation
  private let terminations: AsyncStream<Void>
  private let terminationsContinuation: AsyncStream<Void>.Continuation
  private lazy var profilesIterator = profiles.makeAsyncIterator()
  private lazy var terminationsIterator = terminations.makeAsyncIterator()

  init() {
    (profiles, profilesContinuation) = AsyncStream.makeStream(of: Profile.self)
    (terminations, terminationsContinuation) = AsyncStream.makeStream(of: Void.self)
  }

  func updates(for profile: Profile) -> PositionUpdates.Stream {
    openCount += 1
    let (stream, continuation) = PositionUpdates.Stream.makeStream()
    continuations.append(continuation)
    continuation.onTermination = { [self] _ in
      terminationCount += 1
      terminationsContinuation.yield()
    }
    profilesContinuation.yield(profile)
    return stream
  }

  func nextProfile() async -> Profile? {
    return await profilesIterator.next()
  }

  func nextTermination() async {
    _ = await terminationsIterator.next()
  }
}
