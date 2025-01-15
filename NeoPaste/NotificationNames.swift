import Foundation

enum AppNotification {
    static let clipboardContentChanged = Notification.Name("com.Falcon.clipboardContentChanged")
    static let clipboardSaveCompleted = Notification.Name("com.Falcon.clipboardSaveCompleted")
    static let previewClosed = Notification.Name("previewClosed")
    static let previewSaved = Notification.Name("previewSaved")
    static let recentFilesCleared = Notification.Name("com.Falcon.recentFilesCleared")
}
