# Test results: hello-world build

This file records what was tested on a real Mac, and what the test showed.
The checklist itself is in [`manual-test.md`](manual-test.md). Add a new
section for each test session. Put the newest at the top.

## 2026-10-08: first manual test session

**Summary.** The core loop works on a real Mac. The app captures evidence
every minute and labels it with the allocation that the user selected. It
adds the minute to the ledger. The ledger total matched the capture log
exactly. Alerts, exclusions, idle, pause and "Delete all data" are not
tested yet.

**Setup**

| Item | Value |
| --- | --- |
| Mac | Apple silicon laptop, macOS 26.6.2 |
| Xcode | 27.0 |
| Branch | `hello-world`, up to commit `1746652` |
| Signing | Apple Development certificate (stable identity) |
| Test time | About 80 minutes: 01:35 to 02:55 UTC on 2026-10-09 |
| Slices recorded | 202: 37 minute slices, 165 app-switch slices |

### Validated

Each row was seen working in the running app or shown by its data files.

| Area | Result | Evidence |
| --- | --- | --- |
| Build | `make check` passes (43 tests). `make app` builds and signs the bundle. CI passes on Linux and macOS. | Local runs and GitHub Actions |
| Launch | `make run` opens the main window and a Dock icon with the brand logo. | User saw both |
| Launch from a terminal | The app runs as its own process, not as a child of the terminal. Permission prompts name Time Budget, not the terminal. | Parent process is `launchd` (PID 1) |
| Permissions | Accessibility and Screen Recording grants work. With the certificate, they stay through rebuilds. | Text captured right after a rebuild, with no new grant |
| Accessibility text | Window titles and visible text are captured. | Ghostty (38 slices), Firefox (25), Time Budget (23), Chrome (13), Xcode (4) |
| Browser host | The website host is captured in Chrome and Firefox. | `host` set in browser slices |
| Chrome text | Chrome exposes its text after the app asks for it. Electron apps (Slack, VS Code) are not tested yet. | Chrome slices have Accessibility text |
| Text recognition | Runs once a minute next to Accessibility text. | Recognized text in Firefox (12), Ghostty (5), Chrome (1) and Finder (1) slices |
| Window-change guard | A screenshot is thrown away when the focused window changes during it. | Two slices note `focused window changed before/during the screenshot` |
| Labels | Slices before a selection are `unassigned`. Slices after are labeled with the selected allocation. | 130 allocation slices, 72 unassigned |
| Ledger | Each labeled minute slice adds one minute to its allocation. | Partner team help: 27 minute slices, 27 ledger minutes. Developing talent: 2 and 2 |
| Persistence | The ledger and the selection survive restarts. | Totals kept across several restarts |
| File permissions | The data folder and its files are readable only by the user. | Folder `drwx------`, files `-rw-------` |
| Allocations editable | **Edit…**, **Settings…** and ⌘, open the settings window, where allocations can be added, renamed, removed and budgeted. | User confirmed |

### Problems found and fixed during the session

| Problem | Fix | Commit |
| --- | --- | --- |
| The menu bar item was hidden, so the app seemed not to run | A main window opens at launch, with the same panel | `81258e7` |
| No Dock icon, so the app was hard to reach | The app now has a Dock icon and an app menu | `81258e7` |
| Grants stopped working after each rebuild | Sign with the Apple Development certificate. The keychain was missing Apple's G3 intermediate certificate, which was then installed | `81258e7` (Makefile) |
| The panel showed old permission status | Status is checked again each time the app becomes active | `81258e7` |
| Text recognition never ran for Chrome | Find the window by its frame, not its title | `a5c7c27` |
| App-switch slices often had no window | Wait 500 ms after an app switch | `16e918b` |
| **Edit…** and **Settings…** did nothing | Settings is now an AppKit window | `1746652` |

### Not yet validated

These checklist steps in [`manual-test.md`](manual-test.md) were not run:

- Alerts at 80% and 100% (step 4). No budget was crossed.
- Exclusions: password manager, private window, excluded site (step 3).
- Idle labels after 5 minutes with no input, and pause (step 5).
- Delete all data (step 6).
- Text recognition as the only text source, for an app with no Accessibility text.
- The `make install` copy.
- Sleep and wake, and a change of week.

### Observations for the capture test (milestone 2)

- **Terminals give the whole buffer.** Ghostty slices reach the 6,000-character
  limit, because Accessibility returns the terminal's full scrollback. Terminals
  stay included: their time matters. A later change could keep only the visible
  part.
- **Some apps report no focused window.** Finder, System Settings and Photos
  often have none, so their slices hold no title or text.
- **Personal browsing is captured.** The log holds every site visited while
  capture runs. Pause or the exclude list is the only control. Keep this in mind
  for the two-day capture test on a work Mac.
