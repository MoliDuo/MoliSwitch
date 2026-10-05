import MoliSwitchCore
import XCTest

final class RemoteTitleParserTests: XCTestCase {
    func testClaudeCodeIsKnownByItsMark() {
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "✳ Claude Code"), ["claude"])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "⠐ Fix the login bug"), ["claude"])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "✳ Fix the login bug (ssh)"), ["claude"])
    }

    func testCommandWrittenIntoTheTitleByTheShell() {
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "vim notes.md"), ["vim"])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "htop (ssh)"), ["htop"])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "codex — ssh — 80×24"), ["codex"])
    }

    func testVimWindowTitle() {
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "notes.md (~/work) - VIM"), ["vim"])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "init.lua - NVIM"), ["nvim"])
    }

    func testShellPromptTitlesNameNoProgram() {
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "me@devbox: ~"), [])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "me@devbox:~/projects"), [])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: "~/projects/claude-test"), [])
        XCTAssertEqual(RemoteTitleParser.candidates(fromTitle: ""), [])
    }

    func testRemoteLoginPrograms() {
        XCTAssertTrue(RemoteTitleParser.isRemoteLogin(["ssh"]))
        XCTAssertTrue(RemoteTitleParser.isRemoteLogin(["autossh"]))
        XCTAssertFalse(RemoteTitleParser.isRemoteLogin(["zsh"]))
    }
}
