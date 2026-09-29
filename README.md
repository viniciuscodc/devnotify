# DevNotify

DevNotify is a native macOS menu bar app that keeps meetings and GitHub pull requests in one compact place. Its menu bar item uses the meeting status display, including a colored state dot, countdown, and truncated meeting title. The popover has **Meetings** and **Pull Requests** tabs so both workflows remain one click away.

## Features

### Meetings

- Shows the current meeting, the next meeting, and the rest of today’s calendar.
- Displays a live countdown and meeting title in the menu bar (or a compact calendar icon).
- Finds Google Meet, Zoom, and Microsoft Teams links and opens them with one click.
- Sends configurable pre-meeting notifications with a **Join** action.
- Supports ignored events, attendee response indicators, and a global join shortcut.

### Pull requests

- Loads open PRs from selected repositories or organizations, or from your authored, assigned, and review-requested PRs.
- Groups PRs into **Ready to Merge**, **Review List**, and **Needs Review**.
- Shows CI status and provides merge, failed-CI rerun, ignore, and open-in-GitHub actions.
- Notifies when one of your PRs becomes ready to merge.
- Notifies when someone submits a new review on one of your PRs. This is enabled by default and can be disabled independently.
- Supports optional author filters and global shortcuts for the first ready/review PR.

### Shared app behavior

- One settings window without duplicate notification or appearance controls.
- A global mute switch for all notifications.
- Launch at login is enabled by default and can be changed under **Settings → General**.
- GitHub tokens are stored in the macOS Keychain.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools (`xcode-select --install`)
- A GitHub personal access token for PR features. Grant access to the repositories you want to monitor, pull requests, commit statuses/checks, Actions (for reruns), and contents/pull requests write access if you want to merge.

Calendar access and notification access are requested by macOS when DevNotify first needs them.

## Quick install

With [GitHub CLI](https://cli.github.com/) authenticated, install the latest version into `~/Applications` and launch it:

```zsh
gh api -H 'Accept: application/vnd.github.raw+json' repos/ebanx/devnotify/contents/scripts/install.sh | zsh
```

If the repository has a different owner/name, the installer can be reused without editing it:

```zsh
DEVNOTIFY_REPOSITORY=owner/repository gh api -H 'Accept: application/vnd.github.raw+json' repos/owner/repository/contents/scripts/install.sh | zsh
```

Set `DEVNOTIFY_INSTALL_DIR=/Applications` to install system-wide when your account can write there.

## Development

Build and test from the repository root:

```zsh
swift test
```

Build an ad-hoc signed app bundle and open it:

```zsh
./scripts/run-app.sh
```

Settings are stored in `UserDefaults`; the GitHub token is kept separately in Keychain. DevNotify also reads the legacy PR Pilot Keychain entry during migration, so an existing token is retained after upgrading.
