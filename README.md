# melding

**melding** is a command-line tool for sending macOS notifications (alerts), built with Swift. It is a fork of [vjeantet/alerter](https://github.com/vjeantet/alerter), rewritten to use `UNUserNotificationCenter` for full compatibility with macOS 26+.

The program exits when the user interacts with the notification or when it times out, printing the result to stdout as plain text or JSON.

Requires **macOS 13.0** or later.

Two kinds of alerts can be triggered: **Reply Alert** and **Actions Alert**.

---

## Installation

### Homebrew (recommended)

```bash
brew install elkidd/tap/melding
```

### Build from source

```bash
git clone https://github.com/elkidd/melding.git
cd melding
make bundle        # builds + assembles + signs melding.app in dist/
make install       # installs to /Library/Application\ Support/melding.app + /usr/local/bin/melding
```

---

## Usage

```
melding --message|--remove|--list VALUE [options]
```

### Display a simple notification
```bash
melding --message "Hello!"
```

### Multiple action buttons
```bash
melding --message "Deploy to UAT?" --actions "Now,Later,Cancel"
```

### Yes or No
```bash
melding --title "ProjectX" --subtitle "New tag detected" \
        --message "Deploy now?" --actions "Yes,No"
```

### Reply alert
```bash
melding --reply "Type release name" --message "What is the name of this release?" \
        --title "Deploy in progress..."
```

### Piped input
```bash
echo "Build complete!" | melding --sound default
```

### With timeout and group (replaces previous notification)
```bash
melding --message "Check complete" --group "my-tool" --timeout 30
```

---

## Shell script example

```bash
ANSWER="$(melding --message 'Start now?' --actions 'YES,MAYBE,NO' --timeout 10)"
case $ANSWER in
    "@TIMEOUT")       echo "Timed out" ;;
    "@CLOSED")        echo "Dismissed" ;;
    "@CONTENTCLICKED") echo "Clicked notification body" ;;
    "@ACTIONCLICKED") echo "Clicked default action" ;;
    "YES")            echo "Action: YES" ;;
    "MAYBE")          echo "Action: MAYBE" ;;
    "NO")             echo "Action: NO" ;;
    *)                echo "Unknown: $ANSWER" ;;
esac
```

---

## Options

At a minimum, you must specify `--message`, `--remove`, or `--list`.

| Option | Description |
|--------|-------------|
| `--message VALUE` | The notification message body. Can also be piped via stdin. |
| `--title VALUE` | Notification title. Defaults to `Terminal`. |
| `--subtitle VALUE` | Notification subtitle. |
| `--reply TEXT` | Display as a reply-type alert. TEXT is the input placeholder. Cannot be combined with `--actions`. |
| `--actions A,B,C` | Comma-separated action buttons. Cannot be combined with `--reply`. |
| `--sound NAME` | Sound to play on delivery. Use `default` for the system default sound. |
| `--group ID` | Group ID — only one notification per group is shown at a time; new ones replace old ones. Use `ALL` with `--remove` to clear everything. |
| `--thread ID` | Thread ID — groups related notifications visually in Notification Center (they collapse into a stack). |
| `--level passive\|active\|time-sensitive\|critical` | Interruption level. `passive` = silent, no banner. `active` = default. `time-sensitive` = breaks through Focus mode. `critical` = always shown, ignores silent/DND. |
| `--remove ID` | Remove the notification with the given group ID. Use `ALL` to remove all. |
| `--list ID` | List notifications by group ID. Use `ALL` to list everything. Outputs JSON. |
| `--timeout NUMBER` | Auto-close after NUMBER seconds. Defaults to 0 (no timeout). |
| `--delay NUMBER` | Deliver after NUMBER seconds. Defaults to 0. Cannot be combined with `--at`. |
| `--at TIME` | Deliver at a specific time: `HH:mm` or `yyyy-MM-dd HH:mm`. Cannot be combined with `--delay`. |
| `--app-icon PATH` | URL or path to an image to use as the app icon. |
| `--content-image PATH` | URL or path to a local image to attach to the notification. |
| `--json` | Output result as JSON. |
| `--version` | Print version and exit. |

---

## Output values

| Value | Meaning |
|-------|---------|
| `@CLOSED` | User dismissed the notification |
| `@TIMEOUT` | Notification timed out |
| `@CONTENTCLICKED` | User clicked the notification body |
| `@ACTIONCLICKED` | User clicked the default action button |
| `@REPLIED` | User submitted a reply (reply-type alerts) |
| `<ACTION>` | User clicked a named action button (e.g. `Yes`, `No`) |

---

## Release workflow

```bash
./scripts/release.sh        # bump version, build, sign, zip, tag, GitHub Release
```

The formula in [elkidd/homebrew-tap](https://github.com/elkidd/homebrew-tap) must be updated manually after a new release.

---

## Background

melding is a fork of [vjeantet/alerter](https://github.com/vjeantet/alerter). The original used `NSUserNotification` private APIs which crash on macOS 26+. This fork migrates to `UNUserNotificationCenter` and packages the binary as a proper `.app` bundle (required by Apple's notification framework).

---

## License

MIT — Copyright (C) 2012-2026 Valère Jeantet, Eloy Durán, Julien Blanchard, Miguel Cabeza

