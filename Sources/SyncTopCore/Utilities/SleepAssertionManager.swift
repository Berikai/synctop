import Foundation
import IOKit.pwr_mgt

/// Prevents the Mac from sleeping while background sync tasks are actively uploading/downloading.
public final class SleepAssertionManager: @unchecked Sendable {
    public static let shared = SleepAssertionManager()

    private var assertionID: IOPMAssertionID = 0
    private var activeCount: Int = 0
    private let lock = NSLock()

    private init() {}

    /// Retains a sleep prevention assertion.
    public func retainAssertion(reason: String = "SyncTop synchronization in progress") {
        lock.lock()
        defer { lock.unlock() }

        if activeCount == 0 {
            let success = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID
            )
            if success != kIOReturnSuccess {
                assertionID = 0
            }
        }
        activeCount += 1
    }

    /// Releases a sleep prevention assertion when a sync task finishes.
    public func releaseAssertion() {
        lock.lock()
        defer { lock.unlock() }

        guard activeCount > 0 else { return }
        activeCount -= 1
        if activeCount == 0 && assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}

