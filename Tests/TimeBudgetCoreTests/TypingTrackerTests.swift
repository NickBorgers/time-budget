import Foundation
import Testing

@testable import TimeBudgetCore

@Suite("TypingTracker")
struct TypingTrackerTests {
  func at(_ seconds: Double) -> Date { date(8).addingTimeInterval(seconds) }

  func field(_ value: String, id: String = "slack-box", typed: Bool = true) -> FieldSnapshot {
    FieldSnapshot(fieldID: id, value: value, keyPressed: typed)
  }

  @Test func findsTheInsertedText() {
    #expect(TypingTracker.insertion(old: "Hi", new: "Hi Priya") == " Priya")
    #expect(TypingTracker.insertion(old: "ac", new: "abc") == "b")
    #expect(TypingTracker.insertion(old: "", new: "new") == "new")
    // Deleting or no change is not typing.
    #expect(TypingTracker.insertion(old: "abc", new: "ab") == nil)
    #expect(TypingTracker.insertion(old: "abc", new: "abc") == nil)
    // A replaced word keeps only the new part.
    #expect(TypingTracker.insertion(old: "the cat sat", new: "the dog sat") == "dog")
  }

  @Test func keepsTextTypedIntoOneField() {
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(field("Hi Pri"), at: at(5))
    tracker.observe(field("Hi Priya, can you"), at: at(10))
    #expect(tracker.typed(at: at(12)) == TypedText(text: "Hi Priya, can you", characters: 17))
  }

  @Test func theFirstLookAtAFieldIsNotTyping() {
    // Text already in a field, such as an open document, was not typed now.
    var tracker = TypingTracker()
    tracker.observe(field("A long document"), at: at(0))
    tracker.observe(field("Other text", id: "other"), at: at(5))
    #expect(tracker.typed(at: at(6)).characters == 0)
  }

  @Test func changesWithNoKeyPressAreNotTyping() {
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(field("someone else's text", typed: false), at: at(5))
    tracker.observe(field("someone else's text!"), at: at(10))
    #expect(tracker.typed(at: at(11)).text == "!")
  }

  @Test func largeInsertionsArePastesOrOutput() {
    var tracker = TypingTracker()
    tracker.observe(field("$ "), at: at(0))
    let output = String(repeating: "x", count: TypingTracker.maxInsertion + 1)
    tracker.observe(field("$ " + output), at: at(5))
    #expect(tracker.typed(at: at(6)).characters == 0)
    // The baseline moved on, so later typing still counts.
    tracker.observe(field("$ " + output + "ls"), at: at(10))
    #expect(tracker.typed(at: at(11)).text == "ls")
  }

  @Test func aSentMessageStartsANewLine() {
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(field("first"), at: at(5))
    tracker.observe(field(""), at: at(10))  // Sent: the box is empty again.
    tracker.observe(field("second"), at: at(15))
    tracker.observe(field("x", id: "other"), at: at(20))
    tracker.observe(field("xy", id: "other"), at: at(25))
    #expect(tracker.typed(at: at(26)).text == "first\nsecond\ny")
  }

  @Test func forgetsTextOlderThanTheWindow() {
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(field("old"), at: at(5))
    tracker.observe(field("old new"), at: at(70))
    #expect(tracker.typed(at: at(70)).text == " new")
  }

  @Test func keepsOnlyTheLastCharactersOfALongMinute() {
    var tracker = TypingTracker()
    var value = ""
    tracker.observe(field(value), at: at(0))
    for i in 1...10 {
      value += String(repeating: "a", count: 199) + "\(i % 10)"
      tracker.observe(field(value), at: at(Double(i) * 5))
    }
    let typed = tracker.typed(at: at(51))
    #expect(typed.characters == 2_000)
    #expect(typed.text.count == TypingTracker.textLimit)
    #expect(typed.text.hasSuffix("a0"))
  }

  @Test func noFieldResetsTheBaseline() {
    // An excluded app, a password field, or no focused field.
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(nil, at: at(5))
    tracker.observe(field("secret"), at: at(10))
    #expect(tracker.typed(at: at(11)).characters == 0)
  }

  @Test func clearForgetsEverything() {
    var tracker = TypingTracker()
    tracker.observe(field(""), at: at(0))
    tracker.observe(field("abc"), at: at(5))
    tracker.clear()
    tracker.observe(field("abcd"), at: at(10))
    #expect(tracker.typed(at: at(11)) == TypedText(text: "", characters: 0))
  }
}

@Suite("Typed text in the evidence")
struct TypedEvidenceTests {
  @Test func premiseIncludesTypedText() {
    var evidence = SliceEvidence(
      appName: "Slack", visibleText: "#payments", textSource: .accessibility)
    evidence.typedText = "sure, I can look at the webhook"
    #expect(
      ClassifierPrompt.premise(for: evidence)
        == """
        App: Slack
        Text on the screen:
        #payments
        Typed in the last minute:
        sure, I can look at the webhook
        """)
  }

  @Test func typedTextChangesTheContent() {
    let a = SliceEvidence(appName: "Slack")
    var b = a
    b.typedText = "hello"
    #expect(!a.sameContent(as: b))
  }

  @Test func typedTextIsNeverWrittenToTheLog() throws {
    var evidence = SliceEvidence(appName: "Slack")
    evidence.typedText = "my private draft"
    evidence.typedCharacters = 16
    let record = SliceRecord(
      time: date(8), trigger: .minute, label: .unassigned, userLabel: .unassigned,
      evidence: evidence)
    let line = String(decoding: try SliceLog.line(for: record), as: UTF8.self)
    #expect(!line.contains("private draft"))
    #expect(line.contains("\"typedCharacters\":16"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let back = try decoder.decode(SliceRecord.self, from: Data(line.utf8))
    #expect(back.evidence.typedText == "")
    #expect(back.evidence.typedCharacters == 16)
  }
}
