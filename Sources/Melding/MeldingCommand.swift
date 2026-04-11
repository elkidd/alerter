import ArgumentParser
import AppKit

struct MeldingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "melding",
        abstract: "A command-line tool to send macOS user notifications.",
        version: "1.0.1"
    )

    // MARK: - Required (at least one)

    @Option(help: "The notification message.")
    var message: String?

    @Option(help: "Remove a notification with the specified group ID.")
    var remove: String?

    @Option(help: "List notifications by group ID, or use 'ALL' to see all.")
    var list: String?

    // MARK: - Reply

    @Option(help: "Display as reply-type alert. VALUE is used as placeholder text.")
    var reply: String?

    // MARK: - Actions

    @Option(help: "Comma-separated list of actions.")
    var actions: String?

    // MARK: - Optional

    @Option(help: "The notification title. (default: Terminal)")
    var title: String = "Terminal"

    @Option(help: "The notification subtitle.")
    var subtitle: String?

    @Option(help: "Sound name to play. Use 'default' for the default sound.")
    var sound: String?

    @Option(help: "Group ID for notification replacement.")
    var group: String?

    @Option(help: "Thread ID for grouping related notifications in Notification Center.")
    var thread: String?

    @Option(help: "Interruption level: passive, active (default), time-sensitive, or critical.")
    var level: String?

    @Option(help: "URL or path of an image to use as app icon.")
    var appIcon: String?

    @Option(help: "URL or path of an image attached to the notification.")
    var contentImage: String?

    @Option(help: "Auto-close the notification after N seconds.")
    var timeout: Int = 0

    @Flag(help: "Output result as JSON.")
    var json: Bool = false

    @Option(help: "Deliver the notification after N seconds.")
    var delay: Int = 0

    @Option(help: "Deliver at a specific time. Formats: 'HH:mm' or 'yyyy-MM-dd HH:mm'.")
    var at: String?

    // MARK: - Run

    mutating func validate() throws {
        if message == nil && isatty(STDIN_FILENO) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let stdinMessage = String(data: data, encoding: .utf8)
            if let msg = stdinMessage, !msg.isEmpty {
                message = msg
            }
        }

        if message == nil && remove == nil && list == nil {
            throw ValidationError("At least one of --message, --remove, or --list is required.")
        }

        if actions != nil && reply != nil {
            throw ValidationError("--actions and --reply cannot be combined.")
        }

        if delay < 0 {
            throw ValidationError("--delay must be a non-negative integer.")
        }

        if at != nil && delay > 0 {
            throw ValidationError("--at and --delay cannot be combined.")
        }

        if let atValue = at {
            guard let targetDate = parseAtTime(atValue) else {
                throw ValidationError("--at: invalid format. Use 'HH:mm' or 'yyyy-MM-dd HH:mm'.")
            }
            if targetDate.timeIntervalSinceNow < -60 {
                throw ValidationError("--at: the specified time is in the past.")
            }
        }
    }

    func run() throws {
        if let listID = list {
            NotificationManager.shared.listNotifications(groupID: listID)
            throw ExitCode.success
        }

        if let removeID = remove {
            NotificationManager.shared.removeNotification(groupID: removeID)
            if message == nil {
                throw ExitCode.success
            }
        }

        waitForScheduledTime()

        if let message = message {
            let config = NotificationConfig(
                title: title,
                subtitle: subtitle,
                message: message,
                actions: actions?.components(separatedBy: ","),
                replyPlaceholder: reply,
                sound: sound,
                groupID: group,
                threadID: thread,
                interruptionLevel: level,
                appIcon: appIcon,
                contentImage: contentImage,
                timeout: timeout,
                outputJSON: json,
                uuid: UUID().uuidString
            )

            let manager = NotificationManager.shared
            manager.deliverNotification(config: config)
            NSApplication.shared.run()
        }
    }

    private func waitForScheduledTime() {
        if let atValue = at, let targetDate = parseAtTime(atValue) {
            let waitInterval = targetDate.timeIntervalSinceNow
            if waitInterval > 0 {
                Thread.sleep(forTimeInterval: waitInterval)
            }
        } else if delay > 0 {
            Thread.sleep(forTimeInterval: Double(delay))
        }
    }

    private func parseAtTime(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.dateFormat = "HH:mm"
        if let time = formatter.date(from: value) {
            let calendar = Calendar.current
            let now = Date()
            let components = calendar.dateComponents([.hour, .minute], from: time)
            guard let todayAtTime = calendar.date(
                bySettingHour: components.hour!, minute: components.minute!, second: 0, of: now
            ) else {
                return nil
            }
            let nowMinute = calendar.date(
                from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            )!
            if todayAtTime >= nowMinute {
                return todayAtTime
            }
            return calendar.date(byAdding: .day, value: 1, to: todayAtTime)
        }

        return nil
    }

}
