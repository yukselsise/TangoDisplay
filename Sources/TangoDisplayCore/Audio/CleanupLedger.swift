import Foundation

/// Attempts every cleanup operation and retains only resources that still
/// belong to the caller because cleanup failed.
public func retainCleanupFailures<Resource>(
    _ resources: [Resource],
    attempt: (Resource) throws -> Void
) -> (remaining: [Resource], firstError: Error?) {
    var remaining: [Resource] = []
    var firstError: Error?
    for resource in resources {
        do { try attempt(resource) }
        catch {
            remaining.append(resource)
            if firstError == nil { firstError = error }
        }
    }
    return (remaining, firstError)
}
