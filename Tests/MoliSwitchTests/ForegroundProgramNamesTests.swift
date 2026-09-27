import Foundation
import XCTest

@testable import MoliSwitchApp

final class ForegroundProgramNamesTests: XCTestCase {
    func testNativeBinaryNamedAfterItsVersionIsKnownByArgv0() {
        let names = ForegroundProgramNames.candidates(
            processName: "2.1.3",
            executablePath: "/Users/me/.local/share/claude/versions/2.1.3",
            arguments: ["claude", "--resume"]
        )

        XCTAssertEqual(names, ["claude", "2.1.3"])
    }

    func testScriptRunByNodeComesFirst() {
        XCTAssertEqual(
            ForegroundProgramNames.candidates(
                processName: "node",
                executablePath: "/opt/homebrew/Cellar/node/24.1.0/bin/node",
                arguments: ["node", "/opt/homebrew/bin/codex"]
            ),
            ["codex", "node"]
        )
        XCTAssertEqual(
            ForegroundProgramNames.candidates(
                processName: "node",
                executablePath: "/usr/local/bin/node",
                arguments: ["node", "--no-warnings", "/usr/local/lib/codex/bin/codex.js", "exec"]
            ),
            ["codex", "codex.js", "node"]
        )
    }

    func testInlineCodeAndLoginShellsHaveNoScript() {
        XCTAssertEqual(
            ForegroundProgramNames.candidates(
                processName: "python3.12",
                executablePath: "/usr/bin/python3",
                arguments: ["python3", "-c", "print(1)"]
            ),
            ["python3", "python3.12"]
        )
        XCTAssertEqual(
            ForegroundProgramNames.candidates(processName: "zsh", executablePath: "/bin/zsh", arguments: ["-zsh"]),
            ["zsh"]
        )
    }

    func testTmuxServerArgumentsAreKept() {
        XCTAssertEqual(
            ForegroundProgramNames.tmuxServerArguments(["tmux", "-L", "work", "-2", "attach", "-t", "0"]),
            ["-L", "work"]
        )
        XCTAssertEqual(
            ForegroundProgramNames.tmuxServerArguments(["tmux", "-S/tmp/socket", "new"]),
            ["-S/tmp/socket"]
        )
    }
}
