import Foundation

extension Notification.Name {
    /// Posted when items are added to the Diver queue, indicating that the pipeline should process them.
    public static let diverQueueDidUpdate = Notification.Name("diverQueueDidUpdate")
}
