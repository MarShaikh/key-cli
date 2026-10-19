import Foundation
import LocalAuthentication

struct AuthenticationError: Error, CustomStringConvertible {
    let description: String
}

enum Authentication {
    /// Blocks until the user passes Touch ID, or the login password when Touch ID is
    /// unavailable (lid closed, no enrolled finger). Throws if they cancel or fail.
    ///
    /// The dialog reads "key is trying to <reason>."
    static func require(_ reason: String) throws {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        var canError: NSError?
        guard context.canEvaluatePolicy(policy, error: &canError) else {
            throw AuthenticationError(description: "Authentication unavailable: \(canError?.localizedDescription ?? "unknown")")
        }

        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        context.evaluatePolicy(policy, localizedReason: reason) { ok, error in
            if !ok { failure = error ?? AuthenticationError(description: "Authentication failed") }
            done.signal()
        }
        done.wait()

        if let failure {
            throw AuthenticationError(description: "Authentication failed: \(failure.localizedDescription)")
        }
    }
}
