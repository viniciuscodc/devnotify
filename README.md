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
- A GitHub personal access token for PR features
- Google Calendar connected to Apple Calendar if your meetings are hosted by Google

## Connect Google Calendar to Apple Calendar

DevNotify uses Apple’s EventKit framework and reads the calendars already available to macOS. It does not connect directly to the Google Calendar API and does not ask for your Google password or an additional Google OAuth token. Connecting the accounts lets macOS handle synchronization while DevNotify reads one system calendar source for Google, iCloud, Exchange, and local events.

If your meetings are stored in Google Calendar:

1. Open the **Calendar** app on your Mac.
2. Choose **Calendar → Add Account**.
3. Select **Google**, click **Continue**, and sign in.
4. Make sure **Calendars** is enabled for the account.
5. In Apple Calendar, show the calendar list and confirm that the required Google calendars are selected and their events appear.
6. Optionally open **Calendar → Settings → Accounts** and choose how often calendars refresh.

You can also add the account from **System Settings → Internet Accounts → Add Account → Google** and enable Calendars. If a shared or secondary Google calendar does not appear, select it on Google’s Calendar sync page and refresh Apple Calendar. See [Apple’s calendar-account instructions](https://support.apple.com/guide/calendar/icl4308d6701/mac) and [Google’s Apple Calendar sync guide](https://support.google.com/calendar/answer/99358?hl=en).

## Create the GitHub token

The token authenticates DevNotify’s GitHub API requests. It is required for the **Pull Requests** tab to load private repository data. DevNotify uses it to:

- Find and read open pull requests and submitted reviews.
- Read commit statuses and check runs to determine CI state.
- Read workflow runs and, when requested, re-run failed GitHub Actions jobs.
- Merge a pull request only when you click **Merge**.

Create a classic personal access token:

1. Open [GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens/new).
2. Enter `DevNotify` in the **Note** field and choose an expiration date.
3. Enable the **`repo`** scope. This gives DevNotify the repository access needed to load private PRs and reviews, inspect CI, re-run failed jobs, and merge when you request those actions.
4. Click **Generate token**, copy the resulting `ghp_…` value, and paste it into **DevNotify → Settings → GitHub**. GitHub only displays the token once.
5. If an organization uses SAML SSO, use **Configure SSO** beside the new token and authorize it for that organization.

The classic `repo` scope is broad: it grants repository access according to the permissions of the GitHub account that created it. Set an expiration, keep the token private, and revoke it when you stop using DevNotify. See [GitHub’s token creation and security guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic).

## Permissions and privacy

DevNotify requests only the access needed for its features:

- **Calendar — Full Access:** reads event times, titles, attendee responses, locations, notes, and URLs so it can build the meeting list and detect Meet, Zoom, or Teams links. DevNotify does not edit calendar events.
- **Notifications:** displays meeting reminders, ready-to-merge alerts, and new-review alerts. Notifications can be muted globally, and review alerts have a separate switch.
- **Open at Login / Login Items:** lets DevNotify start after you sign in so reminders and PR polling work without opening the app manually. This is enabled by default and can be disabled in Settings.
- **Keychain:** stores the GitHub token in the macOS login Keychain instead of UserDefaults or a plain-text file.
- **Network:** contacts `api.github.com` for PR data/actions and GitHub’s image hosts for avatars. Calendar events are read locally through macOS; DevNotify does not send them to GitHub.

macOS prompts for Calendar and Notification access when DevNotify first needs them. You can review or revoke these permissions in **System Settings → Privacy & Security → Calendars** and **System Settings → Notifications → DevNotify**. Disabling a permission disables only the related features.

## Quick install

With [GitHub CLI](https://cli.github.com/) authenticated, install the latest version into `~/Applications` and launch it:

```zsh
gh api -H 'Accept: application/vnd.github.raw+json' repos/viniciuscodc/devnotify/contents/scripts/install.sh | zsh
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
