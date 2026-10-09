import Foundation
import Testing

@testable import TimeBudgetCore

@Suite("Decision")
struct DecisionTests {
  @Test func normalizesEntailmentOverTheOptions() throws {
    // Equal logits give each label 1/3, so equal entailment for each option.
    let even = try #require(Decision.optionProbabilities(logits: [[0, 0, 0], [0, 0, 0]]))
    #expect(even == [0.5, 0.5])

    // Option 0: entailment is e^2 / (1 + e^2 + 1). Option 1: 1/3.
    let e2 = exp(2.0)
    let first = e2 / (e2 + 2)
    let second = 1.0 / 3
    let p = try #require(Decision.optionProbabilities(logits: [[0, 2, 0], [0, 0, 0]]))
    #expect(abs(p[0] - first / (first + second)) < 1e-12)
    #expect(abs(p[1] - second / (first + second)) < 1e-12)
    #expect(abs(p.reduce(0, +) - 1) < 1e-12)
  }

  @Test func largeLogitsDoNotOverflow() throws {
    let p = try #require(Decision.optionProbabilities(logits: [[0, 1000, 0], [1000, 0, 0]]))
    #expect(abs(p[0] - 1) < 1e-12)
    #expect(p[1] < 1e-12)
  }

  @Test func rejectsBadInput() {
    #expect(Decision.optionProbabilities(logits: []) == nil)
    #expect(Decision.optionProbabilities(logits: [[0, 0]]) == nil)
    #expect(Decision.optionProbabilities(logits: [[0, .nan, 0]]) == nil)
    #expect(Decision.optionProbabilities(logits: [[0, .infinity, 0]]) == nil)
  }

  @Test func noEntailmentAnywhereIsUnknown() {
    // Entailment underflows to zero for every option: there is no distribution.
    #expect(Decision.optionProbabilities(logits: [[0, -2000, 0], [0, -2000, 0]]) == nil)
  }
}

@Suite("TokenPrefix")
struct TokenPrefixTests {
  @Test func findsTheSharedPrefix() {
    #expect(TokenPrefix.sharedLength([[1, 2, 3, 4], [1, 2, 5], [1, 2, 3, 9]]) == 2)
    #expect(TokenPrefix.sharedLength([[7, 1], [8, 1]]) == 0)
  }

  @Test func leavesAtLeastOneTokenForEachSequence() {
    // The score reads the last token, so each sequence needs its own last step.
    #expect(TokenPrefix.sharedLength([[1, 2, 3], [1, 2, 3]]) == 2)
    #expect(TokenPrefix.sharedLength([[1, 2], [1, 2, 3]]) == 1)
    #expect(TokenPrefix.sharedLength([[1, 2, 3]]) == 2)
  }

  @Test func emptyInputHasNoPrefix() {
    #expect(TokenPrefix.sharedLength([]) == 0)
    #expect(TokenPrefix.sharedLength([[], [1]]) == 0)
  }
}

@Suite("ClassifierPrompt")
struct ClassifierPromptTests {
  let focus = Allocation(
    name: "Focus work", descriptionText: "Planned work on my own projects", budgetMinutes: 60,
    period: .week)
  let blank = Allocation(name: "Admin", descriptionText: "  ", budgetMinutes: 60, period: .week)

  @Test func premiseListsTheEvidence() {
    let evidence = SliceEvidence(
      appName: "Slack", windowTitle: "#payments-partners", host: "app.slack.com",
      visibleText: "Can you look at the refund bug?", textSource: .accessibility)
    #expect(
      ClassifierPrompt.premise(for: evidence)
        == """
        App: Slack
        Window title: #payments-partners
        Website: app.slack.com
        Text on the screen:
        Can you look at the refund bug?
        """)
  }

  @Test func premiseUsesRecognizedTextWhenAccessibilityGaveNone() {
    let evidence = SliceEvidence(
      appName: "Preview", visibleText: "", textSource: .none, recognizedText: "Invoice 42")
    #expect(
      ClassifierPrompt.premise(for: evidence)
        == """
        App: Preview
        Text on the screen:
        Invoice 42
        """)
  }

  @Test func premiseSaysWhenNoTextWasRead() {
    #expect(
      ClassifierPrompt.premise(for: SliceEvidence(appName: "Finder"))
        == "App: Finder\nText on the screen: none")
  }

  @Test func hypothesisFollowsTheModelCardTemplate() {
    #expect(
      ClassifierPrompt.hypothesis(for: focus)
        == "The answer to \"\(ClassifierPrompt.question)\" is Focus work: Planned work on my own projects"
    )
    // With no description, the name is the rubric, as in openjev_decide.py.
    #expect(
      ClassifierPrompt.hypothesis(for: blank)
        == "The answer to \"\(ClassifierPrompt.question)\" is Admin: Admin")
  }

  @Test func inputJoinsPremiseAndHypothesis() {
    #expect(
      ClassifierPrompt.input(premise: " P \n", hypothesis: " H ") == "Premise: P\nHypothesis: H")
  }

  @Test func optionsAreTheAllocationsAndNoneOfThese() {
    let options = ClassifierPrompt.options(for: [focus, blank])
    #expect(options.map(\.label) == [.allocation(focus.id), .allocation(blank.id), .unassigned])
    #expect(options.map(\.name) == ["Focus work", "Admin", ClassifierPrompt.noneName])
  }
}

@Suite("PinnedRule")
struct PinnedRuleTests {
  let target = UUID()
  let slack = SliceEvidence(
    appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", windowTitle: "#Partner-payments",
    host: nil)

  @Test func matchesTheChosenField() {
    #expect(
      PinnedRule(field: .windowTitle, match: .startsWith, text: "#partner-", allocationID: target)
        .matches(slack))
    #expect(
      !PinnedRule(field: .windowTitle, match: .equals, text: "#partner-", allocationID: target)
        .matches(slack))
    #expect(
      PinnedRule(field: .windowTitle, match: .contains, text: "PAYMENTS", allocationID: target)
        .matches(slack))
    #expect(
      PinnedRule(field: .app, match: .equals, text: "slack", allocationID: target).matches(slack))
    #expect(
      PinnedRule(
        field: .app, match: .equals, text: "com.tinyspeck.slackmacgap", allocationID: target
      )
      .matches(slack))
    #expect(
      !PinnedRule(field: .host, match: .contains, text: "slack", allocationID: target).matches(
        slack))
  }

  @Test func describesItsCondition() {
    #expect(
      PinnedRule(field: .windowTitle, match: .startsWith, text: " #partner- ", allocationID: target)
        .conditionText == "window title starts with \"#partner-\"")
    #expect(
      PinnedRule(field: .host, match: .equals, text: "github.com", allocationID: target)
        .conditionText == "website is \"github.com\"")
    #expect(
      PinnedRule(field: .app, match: .contains, text: "Slack", allocationID: target)
        .conditionText == "app contains \"Slack\"")
  }

  @Test func blankTextNeverMatches() {
    #expect(
      !PinnedRule(field: .app, match: .contains, text: " ", allocationID: target).matches(slack))
  }

  @Test func hostRulesIgnoreCaseAndSpaces() {
    let github = SliceEvidence(appName: "Safari", host: "GitHub.com")
    #expect(
      PinnedRule(field: .host, match: .equals, text: " github.com ", allocationID: target).matches(
        github))
  }
}

@Suite("SliceClassifier")
struct SliceClassifierTests {
  let focus = Allocation(
    name: "Focus work", descriptionText: "Mine", budgetMinutes: 60, period: .week)
  let partner = Allocation(
    name: "Partner", descriptionText: "Theirs", budgetMinutes: 60, period: .week)
  let editor = SliceEvidence(
    appName: "Xcode", windowTitle: "Ledger.swift", visibleText: "struct Ledger",
    textSource: .accessibility,
    secondsSinceInput: 3)

  let classifier: SliceClassifier

  init() {
    classifier = SliceClassifier(
      rules: SliceRules(), allocations: [focus, partner],
      pinnedRules: [
        PinnedRule(field: .host, match: .equals, text: "partner.example", allocationID: partner.id)
      ])
  }

  @Test func excludedSlicesAreDropped() {
    let vault = SliceEvidence(appName: "1Password")
    #expect(classifier.start(vault, previous: nil) == .drop)
  }

  @Test func idleComesBeforeEverythingElse() {
    var idle = editor
    idle.secondsSinceInput = 6 * 60
    #expect(
      classifier.start(idle, previous: nil) == .decided(SliceDecision(label: .idle, method: .idle)))
  }

  @Test func aPinnedRuleWinsOverTheModel() {
    let page = SliceEvidence(appName: "Safari", host: "partner.example", secondsSinceInput: 1)
    let rule = classifier.pinnedRules[0]
    #expect(
      classifier.start(page, previous: nil)
        == .decided(
          SliceDecision(label: .allocation(partner.id), method: .rule(rule.id), confidence: 1)))
  }

  @Test func aRuleForARemovedAllocationIsSkipped() {
    let page = SliceEvidence(appName: "Safari", host: "gone.example", secondsSinceInput: 1)
    var c = classifier
    c.pinnedRules = [
      PinnedRule(field: .host, match: .equals, text: "gone.example", allocationID: UUID())
    ]
    guard case .askModel = c.start(page, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
  }

  @Test func unchangedEvidenceCopiesThePreviousDecision() {
    let before = SliceDecision(
      label: .allocation(focus.id), method: .model, confidence: 0.9,
      options: [OptionScore(name: "Focus work", label: .allocation(focus.id), probability: 0.9)])
    var later = editor
    later.secondsSinceInput = 40  // Idle time is not part of the comparison.
    #expect(
      classifier.start(later, previous: PreviousSlice(evidence: editor, decision: before))
        == .decided(
          SliceDecision(label: .allocation(focus.id), method: .unchanged, confidence: 0.9)))
  }

  @Test func unchangedDoesNotCopyALabelThatNoLongerExists() {
    let before = SliceDecision(label: .allocation(UUID()), method: .model, confidence: 0.9)
    guard
      case .askModel = classifier.start(
        editor, previous: PreviousSlice(evidence: editor, decision: before))
    else {
      Issue.record("expected a model request")
      return
    }
  }

  @Test func changedEvidenceAsksTheModel() throws {
    guard case .askModel(let request) = classifier.start(editor, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
    #expect(request.premise == ClassifierPrompt.premise(for: editor))
    #expect(
      request.options.map(\.label) == [.allocation(focus.id), .allocation(partner.id), .unassigned])
    #expect(request.inputs.count == 3)
    #expect(
      request.inputs[0]
        == ClassifierPrompt.input(
          premise: request.premise, hypothesis: request.options[0].hypothesis))
  }

  @Test func theModelsBestOptionWinsAboveTheThreshold() throws {
    guard case .askModel(let request) = classifier.start(editor, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
    let decision = classifier.finish(request, probabilities: [0.7, 0.2, 0.1])
    #expect(decision.label == .allocation(focus.id))
    #expect(decision.method == .model)
    #expect(decision.confidence == 0.7)
    #expect(decision.options?.map(\.probability) == [0.7, 0.2, 0.1])
  }

  @Test func belowTheThresholdIsUnassigned() throws {
    guard case .askModel(let request) = classifier.start(editor, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
    let decision = classifier.finish(request, probabilities: [0.59, 0.3, 0.11])
    #expect(decision.label == .unassigned)
    #expect(decision.confidence == 0.59)
    // Exactly the threshold is enough.
    #expect(
      classifier.finish(request, probabilities: [0.6, 0.3, 0.1]).label == .allocation(focus.id))
  }

  @Test func noneOfTheseIsUnassigned() throws {
    guard case .askModel(let request) = classifier.start(editor, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
    let decision = classifier.finish(request, probabilities: [0.05, 0.05, 0.9])
    #expect(decision.label == .unassigned)
    #expect(decision.confidence == 0.9)
  }

  @Test func noScoresMeansNoModelDecision() throws {
    guard case .askModel(let request) = classifier.start(editor, previous: nil) else {
      Issue.record("expected a model request")
      return
    }
    #expect(
      classifier.finish(request, probabilities: nil)
        == SliceDecision(label: .unassigned, method: .noModel))
    // A wrong count is a broken model run, not a decision.
    #expect(
      classifier.finish(request, probabilities: [1])
        == SliceDecision(label: .unassigned, method: .noModel))
    #expect(
      classifier.finish(request, probabilities: [0.5, .nan, 0.5])
        == SliceDecision(label: .unassigned, method: .noModel))
  }

  @Test func noAllocationsNeedNoModel() {
    let empty = SliceClassifier(rules: SliceRules(), allocations: [], pinnedRules: [])
    #expect(
      empty.start(editor, previous: nil)
        == .decided(SliceDecision(label: .unassigned, method: .noModel)))
  }
}

@Suite("SliceRecord decision")
struct SliceRecordDecisionTests {
  @Test func roundTripsWithADecision() throws {
    let id = UUID()
    let record = SliceRecord(
      time: date(8), trigger: .minute, label: .allocation(id), userLabel: .unassigned,
      confidence: 0.8,
      decision: SliceDecision(
        label: .allocation(id), method: .model, confidence: 0.8,
        options: [OptionScore(name: "A", label: .allocation(id), probability: 0.8)]),
      evidence: SliceEvidence(appName: "Xcode"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(SliceRecord.self, from: SliceLog.line(for: record)) == record)
  }

  @Test func readsALineFromBeforeTheModel() throws {
    let line = """
      {"evidence":{"appName":"Xcode","secondsSinceInput":0,"textSource":"none","visibleText":""},\
      "label":{"unassigned":{}},"time":"2026-10-08T12:00:00Z","trigger":"minute","userLabel":{"unassigned":{}}}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(SliceRecord.self, from: Data(line.utf8))
    #expect(record.decision == nil)
    #expect(record.label == .unassigned)
  }
}
