import Combine
import XCTest

@testable import ComposableArchitecture

@MainActor
final class EffectRunTests: XCTestCase {
  func testRun() async {
    struct State: Equatable {}
    enum Action: Equatable { case tapped, response }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { send in await send(.response) }
      case .response:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    store.send(.tapped)
    await store.receive(.response)
  }

  func testRunCatch() async {
    struct State: Equatable {}
    enum Action: Equatable { case tapped, response }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { _ in
          struct Failure: Error {}
          throw Failure()
        } catch: { @Sendable _, send in  // NB: Explicit '@Sendable' required in 5.5.2
          await send(.response)
        }
      case .response:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    store.send(.tapped)
    await store.receive(.response)
  }

  func testRunUnhandledFailure() async {
    XCTExpectFailure(nil, enabled: nil, strict: nil) {
      $0.compactDescription == """
        An 'Effect.run' returned from "ComposableArchitectureTests/EffectRunTests.swift:62" threw \
        an unhandled error:

          EffectRunTests.Failure()

        All non-cancellation errors must be explicitly handled via the 'catch' parameter on \
        'Effect.run', or via a 'do' block.
        """
    }
    struct State: Equatable {}
    enum Action: Equatable { case tapped, response }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { send in
          struct Failure: Error {}
          throw Failure()
        }
      case .response:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    // NB: We wait a long time here because XCTest failures take a long time to generate
    await store.send(.tapped).finish(timeout: 5*NSEC_PER_SEC)
  }

  func testRunCancellation() async {
    struct State: Equatable {}
    enum Action: Equatable { case tapped, response }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { send in
          withUnsafeCurrentTask { $0?.cancel() }
          await send(.response)
        }
      case .response:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    await store.send(.tapped).finish()
  }

  func testRunCancellation2() async {
    struct State: Equatable {}
    enum Action: Equatable { case tapped, responseA, responseB }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { send in
          try await withThrowingTaskGroup(of: Void.self) { group in
            _ = group.addTaskUnlessCancelled {
              withUnsafeCurrentTask { $0?.cancel() }
              await send(.responseA)
            }
            _ = group.addTaskUnlessCancelled {
              await send(.responseB)
            }
            try await group.waitForAll()
          }
        }
      case .responseA, .responseB:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    store.send(.tapped)
    await store.receive(.responseB)
    await store.finish()
  }

  func testRunCancellationCatch() async {
    struct State: Equatable {}
    enum Action: Equatable { case tapped, responseA, responseB }
    let reducer = Reducer<State, Action, Void> { state, action, _ in
      switch action {
      case .tapped:
        return .run { send in
          withUnsafeCurrentTask { $0?.cancel() }
          try Task.checkCancellation()
          await send(.responseA)
        } catch: { @Sendable _, send in  // NB: Explicit '@Sendable' required in 5.5.2
          await send(.responseB)
        }
      case .responseA, .responseB:
        return .none
      }
    }
    let store = TestStore(initialState: State(), reducer: reducer, environment: ())
    await store.send(.tapped).finish()
  }
}