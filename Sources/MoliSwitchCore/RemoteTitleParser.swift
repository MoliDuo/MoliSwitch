import Foundation

/// Finds the program running on the other end of ssh from the title of the
/// terminal tab, which the remote shell or program sets: the local process is
/// only ssh, whatever runs on the remote host.
public enum RemoteTitleParser {
    /// Programs whose foreground program runs on another host.
    public static let remoteLoginPrograms: Set<String> = ["ssh", "autossh"]

    public static func isRemoteLogin(_ candidates: [String]) -> Bool {
        candidates.contains { remoteLoginPrograms.contains(CommandRuleSet.matchKey($0)) }
    }

    /// The characters Claude Code puts in front of its title, idle and while working.
    private static let claudeMarks: Set<Character> = ["✳", "✻", "✶", "✽", "✢", "·"]

    /// Names the remote program may be known by, most likely first, or none
    /// when the title does not name one, like a shell's "me@host: ~".
    public static func candidates(fromTitle title: String) -> [String] {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = text.first else { return [] }

        if claudeMarks.contains(first) || isBraille(first) || text.localizedCaseInsensitiveContains("Claude Code") {
            return ["claude"]
        }

        // vim and Neovim title a window "file (dir) - VIM".
        for (suffix, name) in [(" - NVIM", "nvim"), (" - VIM", "vim")] where text.hasSuffix(suffix) {
            return [name]
        }

        // Terminal and iTerm2 may add parts after a dash, and iTerm2 the job in
        // parentheses.
        if let range = text.range(of: " — ") {
            text = String(text[..<range.lowerBound])
        }
        if text.hasSuffix(")"), let open = text.lastIndex(of: "("),
           text[open...].contains(where: \.isWhitespace) == false
        {
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
        }

        guard let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init),
              looksLikeCommand(word)
        else { return [] }
        let name = CommandRuleSet.normalizedCommand(word)
        return name.isEmpty ? [] : [name]
    }

    private static func isBraille(_ character: Character) -> Bool {
        character.unicodeScalars.first.map { (0x2800...0x28FF).contains($0.value) } ?? false
    }

    /// A program name rather than a user, host or path.
    private static func looksLikeCommand(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first,
              CharacterSet.letters.contains(first),
              !word.contains("@"), !word.contains(":"), !word.contains("/")
        else { return false }
        return word.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.+".unicodeScalars.contains($0)
        }
    }
}
