import Foundation
import Testing

@testable import TimeBudgetCore

/// A fixed calendar, so the tests do not depend on the machine's locale.
/// UTC, and weeks start on Monday.
let testCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  calendar.firstWeekday = 2
  return calendar
}()

/// 2026-10-08 is a Thursday.
func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
  testCalendar.date(
    from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite("BudgetPeriod")
struct PeriodTests {
  @Test func aDayStartsAtMidnight() {
    #expect(
      BudgetPeriod.day.start(containing: date(8, 15, 30), calendar: testCalendar) == date(8, 0))
  }

  @Test func aWeekStartsOnTheCalendarsFirstWeekday() {
    // Monday 2026-10-05.
    #expect(BudgetPeriod.week.start(containing: date(8), calendar: testCalendar) == date(5, 0))
    #expect(
      BudgetPeriod.week.start(containing: date(11, 23, 59), calendar: testCalendar) == date(5, 0))
    #expect(BudgetPeriod.week.start(containing: date(12, 0), calendar: testCalendar) == date(12, 0))
  }
}

@Suite("Ledger")
struct LedgerTests {
  let hour = Allocation(name: "Partner", descriptionText: "", budgetMinutes: 10, period: .week)

  @Test func addsMinutesToTheCurrentPeriod() {
    var ledger = Ledger()
    ledger.add(minutes: 3, to: hour, at: date(8), calendar: testCalendar)
    ledger.add(to: hour, at: date(9), calendar: testCalendar)
    #expect(ledger.usedMinutes(for: hour, at: date(10), calendar: testCalendar) == 4)
  }

  @Test func aNewPeriodStartsAtZeroAndKeepsTheOldOne() {
    var ledger = Ledger()
    ledger.add(minutes: 5, to: hour, at: date(8), calendar: testCalendar)
    #expect(ledger.usedMinutes(for: hour, at: date(12), calendar: testCalendar) == 0)
    #expect(ledger.usedMinutes(for: hour, at: date(6), calendar: testCalendar) == 5)
  }

  @Test func eachThresholdIsAnnouncedOncePerPeriod() {
    var ledger = Ledger()
    #expect(ledger.add(minutes: 7, to: hour, at: date(8), calendar: testCalendar).isEmpty)
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar) == [.warning])
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar).isEmpty)
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar) == [.spent])
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar).isEmpty)
    // Next week, the same budget announces again.
    #expect(
      ledger.add(minutes: 10, to: hour, at: date(12), calendar: testCalendar) == [.warning, .spent])
  }

  @Test func aWithdrawnAlertIsAnnouncedOnTheNextMinute() {
    var ledger = Ledger()
    #expect(ledger.add(minutes: 8, to: hour, at: date(8), calendar: testCalendar) == [.warning])
    ledger.withdraw(.warning, for: ledger.key(for: hour, at: date(8), calendar: testCalendar))
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar) == [.warning])
    #expect(ledger.add(to: hour, at: date(8), calendar: testCalendar) == [.spent])
  }

  @Test func aLoweredBudgetAnnouncesOnTheNextMinute() {
    var ledger = Ledger()
    ledger.add(minutes: 5, to: hour, at: date(8), calendar: testCalendar)
    var lowered = hour
    lowered.budgetMinutes = 4
    #expect(ledger.add(to: lowered, at: date(8), calendar: testCalendar) == [.warning, .spent])
  }

  @Test func allocationsAreCountedApart() {
    var ledger = Ledger()
    let other = Allocation(name: "Focus", descriptionText: "", budgetMinutes: 60, period: .day)
    ledger.add(minutes: 2, to: hour, at: date(8), calendar: testCalendar)
    ledger.add(minutes: 3, to: other, at: date(8), calendar: testCalendar)
    #expect(ledger.usedMinutes(for: hour, at: date(8), calendar: testCalendar) == 2)
    #expect(ledger.usedMinutes(for: other, at: date(8), calendar: testCalendar) == 3)
  }

  @Test func changingThePeriodDoesNotReuseTheOldTotal() {
    var ledger = Ledger()
    // Monday 2026-10-05 00:00 starts both a day and a week.
    ledger.add(minutes: 9, to: hour, at: date(5, 0), calendar: testCalendar)
    var daily = hour
    daily.period = .day
    #expect(ledger.usedMinutes(for: daily, at: date(5, 9), calendar: testCalendar) == 0)
    #expect(ledger.add(to: daily, at: date(5, 9), calendar: testCalendar).isEmpty)
    #expect(ledger.usedMinutes(for: hour, at: date(5, 9), calendar: testCalendar) == 9)
  }

  @Test func roundTripsThroughJSON() throws {
    var ledger = Ledger()
    ledger.add(minutes: 9, to: hour, at: date(8), calendar: testCalendar)
    let data = try JSONEncoder().encode(ledger)
    #expect(try JSONDecoder().decode(Ledger.self, from: data) == ledger)
  }
}

@Suite("SliceRules")
struct SliceRulesTests {
  let focus = SliceLabel.allocation(UUID())

  @Test func anExcludedAppIsDropped() {
    let evidence = SliceEvidence(appName: "1Password", bundleID: "com.1password.1password")
    #expect(SliceRules().label(for: evidence, selected: focus) == nil)
  }

  @Test func appNamesAndBundleIDsIgnoreCase() {
    let list = ExcludeList(apps: ["Signal", "COM.APPLE.KEYCHAINACCESS"])
    #expect(list.excludesApp(name: "signal", bundleID: nil))
    #expect(list.excludesApp(name: "Keychain Access", bundleID: "com.apple.keychainaccess"))
    #expect(!list.excludesApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap"))
  }

  @Test func aPrivateWindowTitleIsDropped() {
    let evidence = SliceEvidence(appName: "Firefox", windowTitle: "News — Private Browsing")
    #expect(SliceRules().label(for: evidence, selected: focus) == nil)
  }

  @Test func aHostMatchesItselfAndItsSubdomainsOnly() {
    let list = ExcludeList(hosts: ["bank.com"])
    #expect(list.excludesWindow(title: nil, host: "bank.com"))
    #expect(list.excludesWindow(title: nil, host: "WWW.Bank.com"))
    #expect(!list.excludesWindow(title: nil, host: "notbank.com"))
    #expect(!list.excludesWindow(title: nil, host: nil))
  }

  @Test func hostsAreCanonicalBeforeMatching() {
    let list = ExcludeList(hosts: [" Bank.com. "])
    #expect(list.excludesWindow(title: nil, host: "bank.com."))
    #expect(list.excludesWindow(title: nil, host: "www.bank.com"))
  }

  @Test func aNegativeIdleTimeIsIdle() {
    let evidence = SliceEvidence(appName: "Xcode", secondsSinceInput: -1)
    #expect(SliceRules().label(for: evidence, selected: focus) == .idle)
  }

  @Test func emptyEntriesMatchNothing() {
    let list = ExcludeList(hosts: [""], titleFragments: [""])
    #expect(!list.excludesWindow(title: "Anything", host: "example.com"))
  }

  @Test func noInputForMoreThanFiveMinutesIsIdle() {
    let rules = SliceRules()
    #expect(
      rules.label(for: SliceEvidence(appName: "Xcode", secondsSinceInput: 301), selected: focus)
        == .idle)
    #expect(
      rules.label(for: SliceEvidence(appName: "Xcode", secondsSinceInput: 300), selected: focus)
        == focus)
  }

  @Test func anUnknownIdleTimeIsIdle() {
    let evidence = SliceEvidence(appName: "Xcode", secondsSinceInput: .nan)
    #expect(SliceRules().label(for: evidence, selected: focus) == .idle)
  }

  @Test func passwordManagersAreExcludedByName() {
    for name in ["Dashlane", "LastPass", "Enpass", "Proton Pass", "Passwords"] {
      #expect(ExcludeList.defaults.excludesApp(name: name, bundleID: nil))
    }
  }

  @Test func sameContentIgnoresIdleTime() {
    let a = SliceEvidence(appName: "Xcode", windowTitle: "A", secondsSinceInput: 1)
    var b = a
    b.secondsSinceInput = 50
    #expect(a.sameContent(as: b))
    b.windowTitle = "B"
    #expect(!a.sameContent(as: b))
  }
}

@Suite("TextTools")
struct TextToolsTests {
  @Test func joinsTrimsAndDropsRepeats() {
    let text = TextTools.joinVisibleText(["  Hello\n  world ", "", "Hello world", "Next"])
    #expect(text == "Hello world\nNext")
  }

  @Test func cutsAtTheLimit() {
    let text = TextTools.joinVisibleText(["abcd", "efgh"], limit: 7)
    #expect(text == "abcd\nef")
    #expect(text.count == 7)
  }

  @Test func formatsDurations() {
    #expect(TextTools.duration(minutes: 0) == "0m")
    #expect(TextTools.duration(minutes: 45) == "45m")
    #expect(TextTools.duration(minutes: 60) == "1h")
    #expect(TextTools.duration(minutes: 70) == "1h 10m")
  }
}

@Suite("SliceLog")
struct SliceLogTests {
  @Test func namesOneFilePerDay() {
    #expect(
      SliceLog.fileName(for: date(8, 23, 59), calendar: testCalendar) == "slices-2026-10-08.jsonl")
  }

  @Test func expiresFilesFourteenDaysOldOrOlder() {
    let names = [
      "slices-2026-09-23.jsonl", "slices-2026-09-24.jsonl", "slices-2026-10-08.jsonl",
      "notes.txt", "slices-old.jsonl",
    ]
    #expect(
      SliceLog.expired(names, now: date(8), calendar: testCalendar) == [
        "slices-2026-09-23.jsonl", "slices-2026-09-24.jsonl",
      ])
  }

  @Test func rejectsAStoredConfidenceOutsideZeroToOne() throws {
    let record = SliceRecord(
      time: date(8), trigger: .minute, label: .idle, userLabel: .idle, confidence: 0.5,
      evidence: SliceEvidence(appName: "Xcode"))
    let good = String(decoding: try SliceLog.line(for: record), as: UTF8.self)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for bad in ["1.5", "-0.1"] {
      let text = good.replacingOccurrences(of: "\"confidence\":0.5", with: "\"confidence\":\(bad)")
      #expect(text != good)
      #expect(throws: DecodingError.self) {
        try decoder.decode(SliceRecord.self, from: Data(text.utf8))
      }
    }
  }

  @Test func writesOneLineOfJSON() throws {
    let record = SliceRecord(
      time: date(8), trigger: .minute, label: .idle, userLabel: .unassigned, confidence: 0.75,
      evidence: SliceEvidence(appName: "Xcode", host: "a/b"))
    let line = try SliceLog.line(for: record)
    #expect(line.last == 0x0A)
    #expect(line.dropLast().contains(0x0A) == false)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(SliceRecord.self, from: line) == record)
  }
}

@Suite("AlertText")
struct AlertTextTests {
  @Test func matchesTheSpecWording() {
    let partner = Allocation.starterSet[1]
    #expect(
      AlertText.title(for: partner, threshold: .spent)
        == "Partner team help is spent for this week.")
    let status = BudgetStatus(usedMinutes: 400, budgetMinutes: 480)
    #expect(
      AlertText.body(for: partner, status: status, threshold: .warning)
        == "1h 20m left of 8h this week.")
  }
}
