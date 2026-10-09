# Manual test: hello-world build

This build runs the whole loop with you as the classifier. You choose the
allocation that you work on. Each minute, the app records a slice of evidence
with your label. It adds the minute to that allocation and alerts you at 80%
and at 100% of the budget.

No model runs yet. The capture log is the hand-labeled data that milestone 2
needs.

## Build and launch

```
make run
```

This builds `.build/TimeBudget.app`, signs it ad hoc, and opens it. Two things
appear:

- A **Time Budget** window with the full panel. You can close it.
- A timer icon in the menu bar with `–` next to it. It shows the time left
  once you select an allocation.
- An icon in the Dock. Click it to bring the window back after you close it.

If you do not see the menu bar icon, the menu bar may be full: on a Mac with a
camera notch, extra items hide behind it. Quit some menu bar apps, or check
**System Settings → Menu Bar**. The window works without the icon.

To open the app without a terminal, run `make install` once. It copies the app
to `~/Applications`. Then open **Time Budget** from Spotlight or Finder. Run
`make install` again after each change. The installed copy and
`.build/TimeBudget.app` count as two apps for permissions, so pick one.

Opening the app again while it runs brings the window back.

Use `make run`, not `swift run`. Notifications and the macOS permissions need a
real app bundle. With `make run`, macOS asks for permissions for "Time Budget",
not for your terminal.

## Permissions after a rebuild

Each build gets a new ad-hoc signature. macOS can keep an old Accessibility
grant in System Settings that no longer works for the new build. The panel then
shows a red mark next to Accessibility, but the switch in System Settings is on.

To fix it:

```
make reset-permissions
make run
```

Then grant the permissions again.

**Stable fix: a free development certificate.** With it, the grants stay
through rebuilds. `make app` uses it when it exists.

1. In Xcode, open **Settings → Accounts** and add your Apple ID.
2. Select the team. Click **Manage Certificates…**, then **+ → Apple Development**.
3. Run `make reset-permissions`, then `make run`, and grant the permissions one
   last time.

`make app` prints `Signed ad hoc` when it found no certificate.

Screen Recording takes effect only after the app restarts. After you grant it,
quit and reopen the app.

## Checklist

Work through these in order. Each step says what you should see.

### 1. First launch and permissions

1. Click the menu bar item. A panel opens with four allocations, each at
   `0m of 20h` (or the budget you set). `Unassigned (not counted)` is selected.
2. In **Permissions**, click **Grant…** next to Accessibility. macOS asks about
   "Time Budget". Turn it on in System Settings.
3. Click **Grant…** next to Screen Recording. Turn it on. macOS can ask you to
   quit and reopen the app. Run `make run` again.
4. Notifications: macOS asks at the first launch. Allow it.
5. Open the panel again. All three permissions show a green check.

### 2. Capture

1. Select **Focus work** in the panel. The menu bar shows `Focus work 20h`.
2. Switch to another app, for example Safari on a web page. Open the panel.
   **Last capture** shows the app, the host (for example `github.com`), and a
   character count with `(Accessibility)`.
3. Click **Capture log**. Finder opens the data folder. Open
   `Slices/slices-<today>.jsonl`. Each line is one slice. Check these fields:
   `trigger` (`appSwitch` or `minute`), `label`, `userLabel`, and
   `evidence.windowTitle`, `evidence.host`, `evidence.visibleText`,
   `evidence.recognizedText`.
4. Try Slack or VS Code. They are Electron apps. The text should still appear,
   because the app asks them to turn on their accessibility tree.

### 3. Exclusions

1. Open a password manager, for example the Passwords app. Open the panel.
   **Last capture** says `Excluded window. Nothing stored.`
2. Check the log file. No line names the password manager.
3. Open a private window in Firefox. It should also be excluded. A private
   window in Safari or Chrome is not always caught. See the spec's open
   questions.
4. In **Settings… → Privacy**, add a host such as `example.com`. Visit it. The
   slice is dropped.

### 4. Ledger and alerts

Budgets of 20 hours take too long to test. Use a small budget.

1. Open **Settings… → Allocations**. Set **Partner team help** to `0 h` and
   `5 min` per day.
2. Select **Partner team help** in the panel and keep working.
3. After 4 minutes, a quiet notification says `Partner team help is at 80%`.
4. After 5 minutes, an alert with a sound says
   `Partner team help is spent for today.` The menu bar shows
   `Partner te… spent` with a warning triangle. The bar turns red.
5. Keep working for 2 more minutes. No second alert appears.
6. Quit and reopen. The used time is still there.

### 5. Idle and pause

1. Leave the Mac alone for more than 5 minutes. The next slices have
   `"label":{"idle":{}}` in the log. The ledger does not grow.
2. Click **Pause → 15 min**. The menu bar shows `Paused`. No new lines appear
   in the log.
3. Click **Resume**. Capture starts again.

### 6. Delete all data

**Settings… → Privacy → Delete all data…** deletes the ledger, the log, and
your allocations. The panel returns to the starter set at zero.

## What this build does not do yet

- No model. Your selection is the label.
- No timeline, no corrections, no pinned rules, no away-time prompt (milestone 4).
- No calendar. A meeting with no keyboard or mouse input counts as `Idle`.
- No decline message in the alert (spec F10).
- No color change on the menu bar item. A warning triangle shows instead,
  because macOS draws menu bar labels in one color.
- No CSV export or weekly review (spec F9).

## Report what you find

For the capture test, note for each app you use:

- Whether the Accessibility text shows who made the request.
- Whether the recognized text is better or worse than the Accessibility text.
- Any app that shows no text at all.
