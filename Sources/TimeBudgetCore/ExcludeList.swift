import Foundation

/// Apps, websites and window titles that the app never reads (spec F8).
/// All matches ignore case.
public struct ExcludeList: Codable, Equatable, Sendable {
  /// Bundle identifiers or app names, matched in full.
  public var apps: [String]
  /// Hosts. A host also matches its subdomains: `bank.com` matches `www.bank.com`.
  public var hosts: [String]
  /// Text that, anywhere in a window title, excludes the window.
  public var titleFragments: [String]

  public init(apps: [String] = [], hosts: [String] = [], titleFragments: [String] = []) {
    self.apps = apps
    self.hosts = hosts
    self.titleFragments = titleFragments
  }

  /// Password managers and private browser windows (spec "Privacy controls").
  ///
  /// Not every browser puts "Private" or "Incognito" in the window title, so
  /// the title fragments do not catch every private window. See the spec's
  /// open questions.
  public static let defaults = ExcludeList(
    apps: [
      // Names catch every edition of an app. Bundle identifiers catch an app
      // whose shown name differs, for example in another language.
      "1Password", "Bitwarden", "Dashlane", "LastPass", "Enpass", "KeePassXC", "KeePassium",
      "Proton Pass", "NordPass", "Keeper Password Manager", "RoboForm", "Passwords",
      "Keychain Access", "com.1password.1password", "com.agilebits.onepassword7",
      "com.bitwarden.desktop", "com.apple.keychainaccess", "com.apple.Passwords",
      "org.keepassxc.keepassxc",
    ],
    hosts: [],
    titleFragments: ["Private Browsing", "Incognito", "InPrivate"])

  /// Checked before the app reads anything from the window.
  public func excludesApp(name: String, bundleID: String?) -> Bool {
    apps.contains { entry in
      entry.caseInsensitiveCompare(name) == .orderedSame
        || bundleID.map { entry.caseInsensitiveCompare($0) == .orderedSame } == true
    }
  }

  /// Checked after the app reads the title and the host, before it reads text.
  public func excludesWindow(title: String?, host: String?) -> Bool {
    if let title,
      titleFragments.contains(where: { !$0.isEmpty && title.localizedCaseInsensitiveContains($0) })
    {
      return true
    }
    if let host = host.map(Self.canonicalHost) {
      return hosts.contains { entry in
        let entry = Self.canonicalHost(entry)
        return !entry.isEmpty && (host == entry || host.hasSuffix("." + entry))
      }
    }
    return false
  }

  /// Trims spaces and trailing dots and lowercases, so `Bank.com.` matches
  /// `bank.com`. Internationalized names must be written the way the browser
  /// reports them, usually as punycode (`xn--...`).
  static func canonicalHost(_ host: String) -> String {
    var host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    while host.hasSuffix(".") { host.removeLast() }
    return host
  }

  public func excludes(_ evidence: SliceEvidence) -> Bool {
    excludesApp(name: evidence.appName, bundleID: evidence.bundleID)
      || excludesWindow(title: evidence.windowTitle, host: evidence.host)
  }
}
