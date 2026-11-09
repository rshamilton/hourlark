# Hourlark

**Time, signed & sealed.** A free, open-source iPhone app for tracking volunteer, community service, work, or any other hours, and getting them signed off on paper.

**Free, no account, works offline, no ads. Unlimited causes, entries and exports (CSV, Excel, PDF).**

Website and privacy policy: https://rshamilton.github.io/hourlark/

## Feature checklist

| Question | Answer |
|---|---|
| Free? | Yes. No in-app purchases, subscriptions or trials. Nothing is capped or locked. |
| Account required? | No. |
| Works offline? | Yes. The app has no networking code. |
| Ads or analytics? | None. No third-party code. |
| Start/stop timer? | Yes, plus manual entry. |
| Limit on projects (causes), clients or entries? | No limit. |
| CSV export? | Yes, free. Also Excel (.xlsx) and PDF. |
| Signed verification sheets? | Optional: print, sign, scan back in. |
| Widgets, lock screen, Siri/Shortcuts? | Yes. |
| Open source? | Yes, GPL-3.0. |
| Platforms | iPhone, iOS 18+. |

## FAQ

**Does it need an account?** No.

**Is CSV export free?** Yes. CSV, Excel and PDF exports are free and unlimited.

**Is there a limit on projects?** No limit on causes, entries or exports.

**Does it work offline?** Yes, always. It never goes online.

**Where is my data?** On your iPhone, plus backup files in the Files app. If you choose an iCloud Drive folder, iOS syncs those files; Hourlark itself sends nothing.

**Can it invoice clients?** No. See below.

## What it doesn't do

- No invoicing, billing rates or payments.
- No iPad, Mac or Android version.
- No live multi-device database sync (backups can be mirrored through iCloud Drive).
- No team or shared accounts.

## Open source

Hourlark is released under the GPL-3.0. Read the code, build it yourself, or send a pull request. Issues: https://github.com/rshamilton/hourlark/issues

## Highlights

- **Private by design.** Your data is stored on the iPhone, or in your own private iCloud Drive if you turn that on. No account, no servers, no analytics, no ads, and Hourlark never sends your data to anyone.
- **Free forever.** No in-app purchases or subscriptions.
- **Track anything.** Organize time by cause (a charity, a job, a class, a project) with optional hour goals.
- **Signed-off hours.** Create a verification sheet PDF, print it, get it signed, then scan or photograph it back into the app. Entries on a signed sheet are locked.
- **Reports.** Export a PDF report (with signed/unsigned status per entry and the signed proof attached at the back), an Excel workbook (.xlsx), or a CSV.
- **Your logs live in Files.** Every change is mirrored to ordinary files (full JSON backup including proof photos, a CSV of your hours, 14 daily snapshots) under *On My iPhone → Hourlark → Backups*. Optionally pick a folder in iCloud Drive (or anywhere in Files) and Hourlark mirrors the same files there. The app never goes online; iOS does the syncing.
- **Restore.** Merge a backup into your data or replace everything, from Settings or from the welcome screen on a fresh install.
- **Widgets and lock screen.** A home-screen widget (small and medium) and lock-screen widgets show today's hours and let you start or stop the timer. A Live Activity with a Stop button shows the running timer on the lock screen and Dynamic Island. Siri and Shortcuts can start and stop it too.
- **iCloud Drive.** Optionally mirror backups into Hourlark's own iCloud Drive folder.
- **Reminders.** Optional daily "log your hours" nudges and a "timer running long" alert, all scheduled locally.
- **Per-cause sign-off.** Each cause is either verified by a supervisor or just tracked for yourself.

## Building

Requires Xcode 16+ and iOS 18+. No third-party dependencies.

```bash
brew install xcodegen   # only needed if you change project.yml
xcodegen generate
open Hourlark.xcodeproj
```

Run the tests:

```bash
xcodebuild test -project Hourlark.xcodeproj -scheme Hourlark \
  -destination 'platform=iOS Simulator,name=iPhone 13'
```

To run on a real device, set your own Development Team under Signing & Capabilities and change the bundle identifier prefix (`com.ryanhamilton`) in `project.yml` to your own, along with the App Group and iCloud container names. The widget, Stop button and iCloud features need a paid Apple Developer membership because they use App Groups and iCloud entitlements.

## Layout

| Path | What's there |
|---|---|
| `Hourlark/Models` | SwiftData models: `Cause`, `TimeEntry`, `SignOffSheet`, `ProofImage` |
| `Hourlark/Services` | Timer, PDF layout and reports, CSV export |
| `Hourlark/Views` | SwiftUI screens |

## Roadmap

Live multi-device sync of the database itself (CloudKit), localization, and a tip jar.

## License

GPL-3.0. See [LICENSE](LICENSE).
