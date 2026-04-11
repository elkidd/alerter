import AppKit
import UserNotifications

struct NotificationConfig {
    let title: String
    let subtitle: String?
    let message: String
    let actions: [String]?
    let replyPlaceholder: String?
    let sound: String?
    let groupID: String?
    let threadID: String?
    let interruptionLevel: String?
    let appIcon: String?
    let contentImage: String?
    let timeout: Int
    let outputJSON: Bool
    let uuid: String
}

private let kReplyActionID = "com.melding.action.reply"

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var currentConfig: NotificationConfig?
    private var hasExited = false
    private var timeoutTimer: DispatchWorkItem?
    private var deliveredAt: Date?

    // MARK: - Deliver

    func deliverNotification(config: NotificationConfig) {
        currentConfig = config

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Remove earlier notification with the same group ID (fire-and-forget — run loop not yet started)
        if let groupID = config.groupID {
            center.getDeliveredNotifications { notifications in
                let ids = notifications.compactMap { n -> String? in
                    let gid = n.request.content.userInfo["groupID"] as? String
                    return (groupID == "ALL" || gid == groupID) ? n.request.identifier : nil
                }
                if !ids.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ids)
                }
            }
        }

        // Request authorization and proceed regardless of result.
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.scheduleNotification(config: config)
            }
        }
    }

    private func scheduleNotification(config: NotificationConfig) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = config.title
        if let subtitle = config.subtitle { content.subtitle = subtitle }
        content.body = config.message

        var userInfo: [String: String] = ["uuid": config.uuid]
        if let groupID = config.groupID { userInfo["groupID"] = groupID }
        content.userInfo = userInfo

        // Sound
        if let sound = config.sound {
            content.sound = (sound == "default")
                ? .default
                : UNNotificationSound(named: UNNotificationSoundName(sound))
        }

        // Thread identifier — groups related notifications in Notification Center
        if let threadID = config.threadID {
            content.threadIdentifier = threadID
        }

        // Interruption level — controls how the notification breaks through Focus
        if #available(macOS 12.0, *), let level = config.interruptionLevel {
            switch level {
            case "passive":       content.interruptionLevel = .passive
            case "time-sensitive": content.interruptionLevel = .timeSensitive
            case "critical":      content.interruptionLevel = .critical
            default:              content.interruptionLevel = .active
            }
        }

        // Content image via UNNotificationAttachment (local files only)
        if let contentImagePath = config.contentImage,
           let attachment = makeAttachment(from: contentImagePath) {
            content.attachments = [attachment]
        }

        // App icon — private API, best-effort; may not function on all OS versions
        if let appIconPath = config.appIcon, let image = loadImage(from: appIconPath) {
            content.setValue(image, forKey: "_identityImage")
            content.setValue(false, forKey: "_identityImageHasBorder")
        }

        // Build UNNotificationActions and register a per-request category
        let categoryID = "com.melding.cat.\(config.uuid)"
        var unActions: [UNNotificationAction] = []

        if let actionTitles = config.actions, !actionTitles.isEmpty {
            for (index, title) in actionTitles.enumerated() {
                unActions.append(UNNotificationAction(
                    identifier: "action.\(index)",
                    title: title,
                    options: []
                ))
            }
        } else if let placeholder = config.replyPlaceholder {
            unActions.append(UNTextInputNotificationAction(
                identifier: kReplyActionID,
                title: "Reply",
                options: [],
                textInputButtonTitle: "Send",
                textInputPlaceholder: placeholder
            ))
        }

        // .customDismissAction enables the UNNotificationDismissActionIdentifier callback
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: unActions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
        content.categoryIdentifier = categoryID

        let request = UNNotificationRequest(identifier: config.uuid, content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if let error = error {
                fputs("melding: failed to deliver notification: \(error)\n", stderr)
                exit(1)
            }
            DispatchQueue.main.async {
                self?.deliveredAt = Date()
                self?.startTimeoutIfNeeded(config: config)
            }
        }
    }

    // MARK: - Timeout

    private func startTimeoutIfNeeded(config: NotificationConfig) {
        guard config.timeout > 0 else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.hasExited else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [config.uuid])
            let event = ActivationEvent(
                type: .timeout,
                value: nil,
                valueIndex: nil,
                deliveredAt: self.deliveredAt,
                activatedAt: Date()
            )
            self.outputAndExit(event: event)
        }
        timeoutTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(config.timeout), execute: item)
    }

    // MARK: - Remove

    func removeNotification(groupID: String) {
        let center = UNUserNotificationCenter.current()
        var done = false
        center.getDeliveredNotifications { notifications in
            let ids = notifications.compactMap { n -> String? in
                let gid = n.request.content.userInfo["groupID"] as? String
                return (groupID == "ALL" || gid == groupID) ? n.request.identifier : nil
            }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
            done = true
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    // MARK: - List

    func listNotifications(groupID: String) {
        let center = UNUserNotificationCenter.current()
        var results: [[String: String]] = []
        var done = false

        center.getDeliveredNotifications { notifications in
            for n in notifications {
                let info = n.request.content.userInfo
                let deliveredGroupID = info["groupID"] as? String
                if groupID == "ALL" || deliveredGroupID == groupID {
                    var entry: [String: String] = [:]
                    entry["groupID"] = deliveredGroupID
                    entry["title"] = n.request.content.title.isEmpty ? nil : n.request.content.title
                    entry["subtitle"] = n.request.content.subtitle.isEmpty ? nil : n.request.content.subtitle
                    entry["message"] = n.request.content.body.isEmpty ? nil : n.request.content.body
                    entry["deliveredAt"] = n.date.description
                    results.append(entry)
                }
            }
            done = true
        }
        let deadline = Date(timeIntervalSinceNow: 5)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if !results.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString, terminator: "")
        }
    }

    // MARK: - Cleanup

    func bye() {
        guard let config = currentConfig else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [config.uuid])
        center.removePendingNotificationRequests(withIdentifiers: [config.uuid])
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when the app is in the foreground
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.notification.request.content.userInfo["uuid"] as? String == currentConfig?.uuid else { return }

        timeoutTimer?.cancel()
        timeoutTimer = nil

        let event = activationEvent(for: response)
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        outputAndExit(event: event)
    }

    private func activationEvent(for response: UNNotificationResponse) -> ActivationEvent {
        let activatedAt = Date()

        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            return ActivationEvent(type: .closed, value: nil, valueIndex: nil,
                                   deliveredAt: deliveredAt, activatedAt: activatedAt)

        case UNNotificationDefaultActionIdentifier:
            return ActivationEvent(type: .contentsClicked, value: nil, valueIndex: nil,
                                   deliveredAt: deliveredAt, activatedAt: activatedAt)

        case kReplyActionID:
            let text = (response as? UNTextInputNotificationResponse)?.userText
            return ActivationEvent(type: .replied, value: text, valueIndex: nil,
                                   deliveredAt: deliveredAt, activatedAt: activatedAt)

        default:
            // Action identifiers are "action.0", "action.1", …
            if response.actionIdentifier.hasPrefix("action."),
               let indexStr = response.actionIdentifier.split(separator: ".").last,
               let index = Int(indexStr),
               let titles = currentConfig?.actions,
               index < titles.count {
                return ActivationEvent(type: .actionClicked, value: titles[index], valueIndex: index,
                                       deliveredAt: deliveredAt, activatedAt: activatedAt)
            }
            return ActivationEvent(type: .actionClicked, value: response.actionIdentifier, valueIndex: nil,
                                   deliveredAt: deliveredAt, activatedAt: activatedAt)
        }
    }

    // MARK: - Helpers

    private func outputAndExit(event: ActivationEvent) {
        guard !hasExited else { return }
        hasExited = true
        let output = OutputFormatter.format(event: event, asJSON: currentConfig?.outputJSON ?? false)
        print(output, terminator: "")
        exit(0)
    }

    private func loadImage(from path: String) -> NSImage? {
        let url: URL
        if let parsed = URL(string: path), let scheme = parsed.scheme, !scheme.isEmpty {
            guard scheme == "file" else { return nil } // remote URLs not supported
            url = parsed
        } else {
            url = URL(fileURLWithPath: path)
        }
        return NSImage(contentsOf: url)
    }

    private func makeAttachment(from path: String) -> UNNotificationAttachment? {
        let fileURL: URL
        if let parsed = URL(string: path), let scheme = parsed.scheme, !scheme.isEmpty {
            guard scheme == "file" else { return nil } // remote URLs not supported
            fileURL = parsed
        } else {
            fileURL = URL(fileURLWithPath: path)
        }
        return try? UNNotificationAttachment(identifier: "content-image", url: fileURL, options: nil)
    }
}
