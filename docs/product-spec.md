# Time Allocation Tracker for macOS: Product Spec

Oct 8, 2026 · @Nick

> **Status: tentative design.** The decisions here are proposals until milestones 1
> and 2 confirm them. See [Milestones](#milestones).

## Summary

The app measures real work on a Mac against a time budget for each type of work. It alerts the user when a budget is spent. One open-weight model does the sorting, and that model ships inside the app. No data leaves the Mac.

This spec lists two ways to build the app. Option A forks Dayflow, a native Mac app with an MIT license. Option B puts a new Swift app on the screenpipe capture engine. **The recommendation is Option A.** The screenpipe license requires a paid commercial license for use at work. A bundled engine needs that agreement before the first release.

The model is OpenJev 4B v5, with an MIT license. We convert it to MLX and place it in the app bundle. The install is one disk image of about 3 GB.

Two tests come before the main build. The first test proves that the model gives correct labels in Swift. The second test measures how well screen text separates the allocations.

## Problem and goals

The user accepts too much work because no signal says when one type of work has used its share of the week. The app measures real work against a budget for each type. It tells the user when a budget is spent.

**Goals**

- The user divides a day or a week into named allocations. Each allocation has a time budget.
- The app assigns each minute of real work to one allocation. The user starts no timers.
- The app tells the user when an allocation reaches its budget. The user can then decline new requests of that type.
- All data and all model work stay on the Mac.

**Non-goals**

- Billing, invoices, and client timesheets.
- Reports for a manager, or any monitoring of other people.
- Calendar scheduling. The app measures time. It does not plan time.
- App or website blocking.
- Windows, Linux, iOS, and Intel Macs.

## User experience

The app lives in the menu bar. It shows the current allocation and the time that remains in its budget.

**Setup**

1. The user creates allocations. Each allocation has a name, a description in plain words, a budget, and a period of one day or one week.
2. The app suggests the four starting allocations below. The budgets are example values for a 40-hour week. The user changes them.
3. The user grants the macOS permissions. The app shows what each permission lets it read.

| Allocation | Description the model reads | Example budget per week |
| --- | --- | --- |
| Focus work | Planned work on my own projects, with no request from another person | 20 h |
| Partner team help | Work that answers a request from a person outside my team | 8 h |
| Interrupts | Unplanned requests that I answer in less than 15 minutes | 6 h |
| Developing talent | Coaching, reviews, and feedback for people on my team | 6 h |

**During the day**

- The menu bar item shows the active allocation and its remaining time, for example `Partner help 1h 10m left`.
- A click opens a panel with one bar for each allocation. Each bar shows used time against the budget.
- At 80% of a budget, the app sends one quiet notification.
- At 100%, the app sends an alert: `Partner team help is spent for this week.` The alert includes a short decline message that the user can copy.
- After 100%, the menu bar item changes color while the user works in that allocation. The app does not block any work.

**Corrections**

- A timeline shows the day as blocks. Each block has an allocation and a one-line reason.
- The user moves a block to a different allocation with one click. The app saves the correction as an example for later decisions.
- Blocks with low confidence go to an `Unassigned` list. The app asks about them once, at the end of the day.

**Time away from the Mac**

- When the user returns after more than 5 minutes, the app asks which allocation the time belongs to. One click answers it.
- If a calendar event covers the gap, the app suggests the allocation from the event title and attendees.

**Privacy controls**

- A pause button stops all capture for 15 minutes, 1 hour, or until the user starts it again.
- An exclude list names apps, websites, and window titles that the app never reads. Password managers and private browser windows are on the list by default.

## Requirements

Four constraints are fixed. Both build options must meet all four.

| ID | Hard constraint |
| --- | --- |
| C1 | The classifier is an open-weight model. Its license permits redistribution inside the app. |
| C2 | The model runs on the Mac, inside the app. The app sends no screen content, text, or labels to any network address. |
| C3 | The app brings the model with it. Installation needs no Ollama, LM Studio, Python, Homebrew, or terminal command. The user does not select or download a model. |
| C4 | The app is native macOS: Swift and SwiftUI, Apple silicon, macOS 14 or later. |

**Functional requirements**

| ID | Requirement |
| --- | --- |
| F1 | Allocations: create, edit, and archive. Each has a name, a description, a budget, a period (day or week), and a color. |
| F2 | Capture: record the active app, the window title, and the visible text at each app switch and at least once per minute. |
| F3 | Classify: assign each 1-minute slice to one allocation, to `Unassigned`, or to `Idle`. Store the confidence and the evidence. |
| F4 | Ledger: add the minutes for each allocation in each period. Keep the totals through a restart. Reset at the start of each period. |
| F5 | Alerts: notify at 80% and at 100% of each budget, one time for each threshold in each period. |
| F6 | Corrections: let the user move a block to a different allocation. Update the ledger and the alerts immediately. |
| F7 | Away time: ask for an allocation after an idle gap. Read calendar events through EventKit when the user permits it. |
| F8 | Privacy: pause capture, and exclude named apps, websites, and window titles. |
| F9 | Review: show budget against actual time for each week. Export the ledger as CSV. |
| F10 | Decline messages: store one short reply for each allocation. The user edits the text. |

**Quality targets**

These values are proposed. The prototype in milestone 1 confirms or changes them.

| Measure | Target |
| --- | --- |
| Alert delay after a budget is crossed | 2 minutes or less |
| Minutes that match the user's own label, after 1 week of corrections | 85% or more |
| Average CPU use during a work day | 5% or less of one core |
| Memory while the model is loaded | 4 GB or less |
| Disk use, model included | 5 GB or less |
| Network needed after install | None |

## Shared architecture

Both options use the same four-step pipeline. The options differ only in the Capture step.

[Embedded content in the original: "shared pipeline · 6 parts, 1 feedback loop". The figure was not carried over.]

A slice passes through the rules before it reaches the model. Most slices match the previous slice, and those slices need no model run. The ledger feeds the alerts. Corrections from the timeline change the ledger immediately and can add new rules.

| Part | Option A | Option B |
| --- | --- | --- |
| Capture | Dayflow capture code, plus our Accessibility reader | screenpipe engine as a helper process |
| Rules, model, ledger, alerts | New Swift code | New Swift code |
| Timeline | Dayflow timeline, changed to show allocations | New Swift code |
| Storage | Dayflow SQLite database, with new tables | Our SQLite database, plus the screenpipe database |

## Option A: build on Dayflow

Option A forks [Dayflow](https://github.com/JerryZLiu/Dayflow), a native SwiftUI Mac app with an MIT license. We keep its capture and timeline. We replace its AI layer and add the budget layer.

**What Dayflow gives us today**

- A native Swift app for macOS 14 or later. The source opens in Xcode.
- Screen capture that needs one permission: Screen & System Audio Recording.
- A timeline of activity cards, a weekly review with categories, and automatic cleanup of old recordings.
- Local storage in `~/Library/Application Support/Dayflow/`.

**What does not fit**

- Local AI needs Ollama or LM Studio. The user installs and runs that server. This breaks constraint C3.
- An [earlier README](https://github.com/seasidedog24/Dayflow) states that analysis runs every 15 minutes. A budget alert could then arrive 15 minutes late.
- The same README states that the local path makes 33 or more model calls for each batch. The model describes video frames one by one.
- Dayflow has no budgets and no alerts.
- Dayflow does not read the accessibility tree. It reads pixels only.

**Changes we make**

1. Remove every AI provider: Gemini, the ChatGPT and Claude command-line tools, Ollama, and LM Studio.
2. Add one model runtime inside the app, with the model files in the app bundle.
3. Replace the 15-minute video batch with 1-minute slices. Each slice holds the app name, the window title, and the visible text.
4. Add a text reader that uses the macOS Accessibility API. Use on-device text recognition on a screenshot when an app exposes no text.
5. Add allocations, the ledger, alerts, the menu bar item, and the corrections store.
6. Audit the fork for analytics and crash-report calls. Remove each one.

**Result**

One app, one process, one drag to the Applications folder. All code is Swift, and all of it is ours to change.

## Option B: build on the screenpipe capture engine

Option B writes a new Swift app for the budget layer and uses [screenpipe](https://github.com/screenpipe/screenpipe) as the capture engine. The engine runs as a second process. Our app reads from it on `localhost:3030`.

**What screenpipe gives us today**

- Capture that starts on events: an app switch, a click, a pause in typing, a scroll. It does not record every second.
- Each capture pairs a screenshot with the accessibility tree. The accessibility tree is the structured text that macOS already holds for each window. Text recognition is the fallback.
- Local transcription of meeting audio with Whisper.
- A local SQLite database with full-text search, and a REST API.
- Capture of all monitors.

**What does not fit**

- The license. The [Screenpipe Commercial License](https://github.com/screenpipe/screenpipe/blob/main/LICENSE.md) defines any use in a business environment as commercial use. Commercial use needs a paid license. Free use of a source build covers personal, non-commercial use and a 7-day evaluation.
- The license does not permit us to embed the engine in a product for other people without a commercial license. The licensor also keeps all rights in any changes we make.
- The engine is Rust, and its desktop app uses Tauri. Our Swift app stays native, but the full product is two processes in two languages.
- The desktop app sends product analytics by default. The setting can be turned off. Constraint C2 requires it off.
- The README estimates 5 to 20% CPU and 0.5 to 3 GB of memory for capture alone. The model adds to that.
- The README says the main branch moves fast and breaks things.

**Two ways to ship Option B**

| Variant | Install steps for the user | License need |
| --- | --- | --- |
| B1: bundle the engine inside our app as a helper process | One drag to Applications | Commercial license from Negentropy Labs |
| B2: require the official screenpipe app next to ours | Two installs and one account | One screenpipe subscription for each person |

Only B1 gives the one-step install that this spec asks for.

**Result**

The best text signal of the two options, and meeting audio. The cost is a license agreement, a second process, and more CPU and memory.

## Option comparison and recommendation

Option A is the recommendation. It meets all four hard constraints with no license agreement, and it installs in one step.

| Criterion | Option A: Dayflow fork | Option B: screenpipe engine |
| --- | --- | --- |
| License of the base | MIT | Screenpipe Commercial License; paid for work use |
| C3, one-step install with the model | Yes | Yes for B1, with a commercial license. No for B2 |
| C4, native Swift | Yes, one process | Swift app plus a Rust engine process |
| Text signal today | Pixels only | Accessibility tree, with text recognition as fallback |
| Text signal after our work | Accessibility text, with text recognition as fallback | Same as today |
| Meeting audio | No | Yes, local Whisper |
| Capture trigger | Timed samples | Events, with a timed fallback |
| Capture CPU and memory | Not published; measure in milestone 2 | 5 to 20% CPU, 0.5 to 3 GB memory |
| Code we must write | Model runtime, text reader, budget layer | Budget layer, model runtime, engine packaging |
| Code we must remove | Cloud and server AI providers | Analytics, cloud features, unused pipes |
| Main risk | Our text reader is weaker than screenpipe's | License terms and cost; engine changes break our app |

**Why Option A**

- The app is for use at work. Under the screenpipe license, that is commercial use from the first day after evaluation.
- A bundled engine needs an agreement with a third party before the first release. Option A needs none.
- Dayflow's weak point is its text signal. We can close that gap with our own Accessibility reader. We copy the method, and we copy no screenpipe code.

**When to choose Option B instead**

- Milestone 2 shows that our own text reader cannot separate partner work from team work.
- Meeting audio becomes a requirement.
- A commercial license is acceptable in cost and terms.

## Model

The app uses [OpenJev](https://huggingface.co/AlexWortega/openjev), an open-weight model with an MIT license. The model files ship inside the app bundle. This section applies to both options.

**Why this model**

- Jev itself, from TypeSafe AI, is a closed and hosted model. Constraints C1 and C2 exclude it.
- OpenJev is Qwen3.5 trained as a classifier. It reads a state and a statement about that state. It answers entailment, contradiction, or neutral. It writes no text.
- Its `decide` mode takes a state and a closed set of options. It returns one probability for each option. Our state is the screen evidence. Our options are the allocations.
- The model card reports identical output for the same request, and no label change when the option order changes.

**Checkpoints**

| Checkpoint | Input | Note from the model card | Size of the 4-bit MLX base model | Role in the app |
| --- | --- | --- | --- | --- |
| `qwen3.5-4b-nli-v5` | Text | Recommended for typed decisions. 0.814 on the public JevBench items; Jev 1.13 scores 0.866 | About 2.9 GB | Default |
| `qwen3.5-4b-nli-v2` | Text and images | 0.84 on image claims | About 2.9 GB | Fallback for a screen with no readable text |
| `qwen3.5-0.8b-nli-v5` | Text | Smallest v5 checkpoint | About 622 MB | Default on a Mac with 8 GB of memory |

The sizes come from the MLX conversions of the base models, [Qwen3.5-4B](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) and [Qwen3.5-0.8B](https://huggingface.co/mlx-community/Qwen3.5-0.8B-MLX-4bit). The OpenJev conversions will be close to these values. Milestone 1 measures them.

**Runtime**

- The app runs the model with MLX, Apple's array framework for Apple silicon. The Swift package is [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm).
- The model runs inside the app process. The app starts no server and opens no port.
- OpenJev publishes its weights for the Python Transformers library. We found no MLX build of OpenJev.
- Work item: convert the weights to 4-bit MLX. Add the classification head in Swift. The head reads the last token and returns three label scores.
- Work item: port the shared-prefix method from the model card. The app encodes the long screen text one time, then scores each allocation against it.
- Acceptance test: the Swift port and the Python reference give the same label on 99% or more of a fixed test set. This target is proposed.

**How the app brings the model**

1. The build script places the converted model in `Contents/Resources/Models/` inside the app bundle.
2. The release is one signed and notarized disk image of about 3 GB. The user drags the app to Applications.
3. The first launch needs no network. The app does not download a model.
4. At launch, the app compares a SHA-256 hash of each model file with a list that is signed with the app.
5. Updates use [Sparkle delta updates](https://www.sparkle-project.org/documentation/delta-updates/). A delta update sends only the files that changed. An app update does not send the model again.
6. The bundle includes the license text for OpenJev and for the Qwen3.5 base model.

## Classification design

Each 1-minute slice gets one label. Fixed rules run first. The model decides only what the rules leave open.

**Evidence for one slice**

| Field | Source | Example |
| --- | --- | --- |
| App | `NSWorkspace` | Slack |
| Window title | Accessibility API | `#payments-partners` |
| Website host | Accessibility API, from the browser address field | `github.com` |
| Visible text | Accessibility API; text recognition as fallback | The last messages in the channel |
| Calendar event | EventKit, when permitted | `Mentoring 1:1` |
| Seconds since last input | System idle time | 12 |

The app trims the visible text to about 1,500 tokens. The 0.8B checkpoint has a 4,000-token context.

**Steps**

1. Exclude: if the app, site, or title is on the exclude list, drop the slice. Store nothing.
2. Idle: if the last input is more than 5 minutes old and no meeting is active, label the slice `Idle`.
3. Unchanged: if the evidence matches the previous slice, copy the previous label. Run no model.
4. Pinned rules: apply rules that the user wrote, for example `Slack channel starts with #partner- → Partner team help`.
5. Model: send the evidence as the state. Send each allocation description as an option, plus `None of these`. Take the option with the highest probability.
6. Threshold: if the highest probability is below 0.6, label the slice `Unassigned`. This value is proposed.
7. Smooth: join neighbor slices with the same label into one block. A single slice between two blocks of one label takes that label.

**The Interrupts allocation**

An interrupt is a pattern in time. The content does not define it. Proposed rule: a block shorter than 15 minutes that breaks a Focus work block counts as Interrupts. The user sets the length.

**Learning from corrections**

- Version 1 uses the allocation descriptions and the pinned rules only. Each correction offers to create a pinned rule.
- Version 2 adds a small classifier that trains on the Mac from the stored corrections. It reads the internal vector that OpenJev produces for a slice. The model card describes this method for its largest checkpoint. For the 4B checkpoint, this is an experiment.

**What the user sees as the reason**

The model writes no text. The reason line shows the evidence: the app, the window title, the rule or description that won, and the probability.

**Known weakness**

The model card states that the model is not hardened against prompt injection. One hostile line in the state cut accuracy from 0.833 to 0.467 in the author's test. Screen text is not trusted input. The damage here is a wrong label. Rules and alerts run outside the model, and the model starts no action.

## Data, privacy, permissions, and distribution

The app keeps the smallest record that supports the ledger and the corrections. Nothing leaves the Mac.

**What the app stores**

| Data | Kept for | Note |
| --- | --- | --- |
| Ledger: minutes for each allocation in each period | Until the user deletes it | The only long-term record |
| Slice evidence: app, title, trimmed text, label | 14 days | Needed for the timeline and for corrections |
| Screenshots | Deleted after text recognition | The user can turn on a 3-day window for review |
| Corrections and pinned rules | Until the user deletes them | Used to improve labels |

The retention values are proposed. All data sits in one SQLite database in `~/Library/Application Support/`. One menu command deletes everything.

**What the app never does**

- It does not log keystrokes. It reads text that is visible on the screen. It does not request the Input Monitoring permission.
- It sends no analytics and no crash reports.
- Its only network request is the update check. The request carries no user data. The user can turn it off.

**macOS permissions**

| Permission | Purpose | Option A | Option B |
| --- | --- | --- | --- |
| Accessibility | Read window titles and visible text | Required | Required |
| Screen & System Audio Recording | Take a screenshot for text recognition | Required for the fallback | Required |
| Notifications | Budget alerts | Required | Required |
| Calendar | Label meetings and time away | Optional | Optional |
| Microphone | Meeting transcription | Not used | Optional |

macOS 15 asks the user to confirm screen recording access [each month](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/). The app must detect a lost permission and say so in the menu bar.

**Distribution**

- Direct download: a disk image signed with a Developer ID and notarized by Apple.
- No Mac App Store release. The store requires App Sandbox. Apple's developer forums report that the Accessibility permission prompt [does not appear](https://developer.apple.com/forums/thread/810677) for a sandboxed app.

**Use on a work Mac**

The screen shows messages from other people and company data. An employer can also block these permissions with device management. Get approval from the employer before the first install.

## Milestones

Six milestones lead to a first release. Milestones 1 and 2 are tests that can change the plan. Each milestone has one exit check.

1. **Model test.** Convert OpenJev 4B v5 and 0.8B v5 to 4-bit MLX. Run both in a Swift command-line tool on the target Mac. Exit check: the labels match the Python reference, and the time and memory for one slice are known.
2. **Capture test.** Record two work days of slices in two ways: text recognition only, and Accessibility text. The user labels the slices by hand. Exit check: the accuracy of each way is known, and the choice between Option A and Option B is final.
3. **Core app.** Build allocations, the ledger, the menu bar item, and the alerts at 80% and 100%. Exit check: a budget that is crossed during a real work day produces an alert in 2 minutes or less.
4. **Corrections.** Build the timeline, block reassignment, pinned rules, the away-time prompt, and calendar labels. Exit check: a correction updates the ledger and the alerts immediately.
5. **Packaging.** Put the model in the bundle. Sign and notarize the disk image. Add Sparkle updates. Exit check: the app installs and classifies on a clean Mac with the network off.
6. **Two-week trial.** The user works with the app for two weeks. Adjust the threshold, the Interrupts rule, and the descriptions. Exit check: 85% or more of the minutes match the user's own label on reviewed days.

## Risks and open questions

The largest risk is the text signal: the same app can hold work for two different allocations.

| Risk | Effect | Response |
| --- | --- | --- |
| The screen text does not show who made the request | Partner work and team work get the same label | Put team names and partner names in the allocation descriptions. Add pinned rules. Test in milestone 2 |
| The Swift port of the model differs from the reference | Wrong labels with no visible error | Exit check of milestone 1. Fall back to the 0.8B checkpoint or to a different runtime |
| Work away from the Mac is not seen | Budgets look less used than they are | Away-time prompt and calendar labels |
| Model runs heat the Mac or drain the battery | The user turns the app off | Skip unchanged slices. Use the 0.8B checkpoint on battery power |
| The employer does not permit screen capture | The app cannot be used | Approval before install. Exclude list. No stored screenshots |
| Too many alerts | The user ignores them | One alert for each threshold in each period |
| Hostile text on the screen changes a label | A wrong label | Rules run outside the model. The user corrects the block |
| Option B only: license terms or price change | Release blocked | Option A is the default |

**Open questions**

- [ ] Does this spec read "both options" correctly? It treats them as the Dayflow base and the screenpipe base.
- [ ] Which Mac is the target: which chip and how much memory? The answer selects the 4B or the 0.8B checkpoint as default.
- [ ] Is a download of about 3 GB acceptable? The alternative is a small installer that fetches the model at first launch.
- [ ] Is Apple's on-device text recognition acceptable? It is a system framework, and it is not an open-weight model. The alternatives are Accessibility text only, or the OpenJev 4B v2 checkpoint on images.
- [ ] Does the license of the Qwen3.5 base model permit redistribution inside an app? We did not check this license.
- [ ] Is the app for one person, or will colleagues use it? The answer changes distribution and support.
- [ ] Does the first release need day budgets, or week budgets only?
- [ ] Does the current macOS release still ask for screen recording access each month? We checked macOS 15 only.
- [ ] Does the file host accept one 3 GB file?
- [ ] What is the name of the app?
- [ ] How does the app detect a private browser window? Firefox puts "Private Browsing" in the window title. Safari and Chrome may not. The hello-world build matches title text only, so some private windows are not excluded.
- [ ] Should the idle rule skip a meeting? Step 2 says yes, but the app does not read the calendar yet. Until it does, a meeting with no input counts as `Idle`.
- [ ] Should the app show a Dock icon? The spec describes a menu bar app, which usually has none. The test build shows one, because a hidden menu bar item left no way to reach the app.
- [ ] How is the development build signed? An ad-hoc signature changes at each build, and macOS then drops the Accessibility grant. A Developer ID certificate fixes this.

## Sources

All pages were read on 2026-10-08.

- [Dayflow repository and README](https://github.com/JerryZLiu/Dayflow): license, requirements, AI providers, storage path.
- [Dayflow earlier README, in a fork](https://github.com/seasidedog24/Dayflow): 1 frame per second, 15-minute analysis, 33 or more local model calls.
- [screenpipe repository and README](https://github.com/screenpipe/screenpipe): capture method, API, resource estimates, analytics.
- [Screenpipe Commercial License](https://github.com/screenpipe/screenpipe/blob/main/LICENSE.md): definition of commercial use, free use, embedding, ownership of changes.
- [OpenJev model card](https://huggingface.co/AlexWortega/openjev): checkpoints, license, `decide` mode, benchmark values, prompt-injection test.
- [AI/TLDR note on OpenJev and Jev](https://ai-tldr.dev/releases/sam-witteveen-open-jev-sep20/): Jev is a paid hosted API from TypeSafe AI.
- [Qwen3.5-4B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) and [Qwen3.5-0.8B MLX 4-bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-MLX-4bit): disk sizes.
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm): Swift package for MLX models.
- [Sparkle delta updates](https://www.sparkle-project.org/documentation/delta-updates/): updates that send only changed files.
- [9to5Mac on the macOS 15 screen recording prompt](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/): the monthly confirmation.
- [Apple developer forum thread 810677](https://developer.apple.com/forums/thread/810677): Accessibility permission and App Sandbox.
