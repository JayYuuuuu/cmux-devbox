import Foundation
import Testing
@testable import CmuxSidebar

@Suite("SidebarClaudeUsage")
struct SidebarClaudeUsageTests {
    @Test("parses a full v1 report")
    func parsesFullReport() throws {
        let usage = try #require(SidebarClaudeUsage.parse("v1 who=dev h5=23.4 h5r=1793700000 d7=41 d7r=1794000000"))
        #expect(usage.who == "dev")
        #expect(usage.fiveHour == SidebarClaudeUsage.Window(usedPercent: 23, resetsAt: Date(timeIntervalSince1970: 1_793_700_000)))
        #expect(usage.sevenDay == SidebarClaudeUsage.Window(usedPercent: 41, resetsAt: Date(timeIntervalSince1970: 1_794_000_000)))
    }

    @Test("encoded form round-trips")
    func roundTrips() throws {
        let usage = SidebarClaudeUsage(
            who: "air13home",
            fiveHour: .init(usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_793_700_000)),
            sevenDay: .init(usedPercent: 99, resetsAt: nil)
        )
        #expect(SidebarClaudeUsage.parse(usage.encoded) == usage)
    }

    @Test("carries a display label with spaces and an email")
    func labelAndEmail() throws {
        let usage = try #require(SidebarClaudeUsage.parse(
            "v1 who=yujie lb=iPhone%2013mini em=someone@example.com h5=2"
        ))
        #expect(usage.label == "iPhone 13mini")
        #expect(usage.email == "someone@example.com")
        #expect(usage.encoded.contains("lb=iPhone%2013mini em=someone@example.com"))
        let chinese = SidebarClaudeUsage(
            who: "air13home", label: " 家里\t笔记本\u{1B} ", email: "a b@example.com",
            fiveHour: nil, sevenDay: .init(usedPercent: 1, resetsAt: nil)
        )
        #expect(chinese.label == "家里 笔记本")
        #expect(chinese.email == "ab@example.com")
        #expect(SidebarClaudeUsage.parse(chinese.encoded) == chinese)
        #expect(SidebarClaudeUsage.parse("v1 who=dev h5=1")?.label == "")
    }

    @Test("accepts a single window, rejects reports without any")
    func windowPresence() {
        #expect(SidebarClaudeUsage.parse("v1 who=dev d7=5")?.fiveHour == nil)
        #expect(SidebarClaudeUsage.parse("v1 who=dev") == nil)
        #expect(SidebarClaudeUsage.parse("v2 h5=1") == nil)
        #expect(SidebarClaudeUsage.parse("hello world") == nil)
        #expect(SidebarClaudeUsage.parse("v1 h5=nan") == nil)
    }

    @Test("clamps percentages and sanitizes names")
    func clampsAndSanitizes() throws {
        let usage = try #require(SidebarClaudeUsage.parse("v1 who=a\u{1B}b h5=180 d7=-3"))
        #expect(usage.who == "ab")
        #expect(usage.fiveHour?.usedPercent == 100)
        #expect(usage.sevenDay?.usedPercent == 0)
    }

    @Test("a window past its reset reads as empty")
    func resetWindowIsEmpty() {
        let reset = Date(timeIntervalSince1970: 1_000)
        let window = SidebarClaudeUsage.Window(usedPercent: 80, resetsAt: reset)
        #expect(window.effectivePercent(now: Date(timeIntervalSince1970: 999)) == 80)
        #expect(window.secondsUntilReset(now: Date(timeIntervalSince1970: 400)) == 600)
        #expect(window.effectivePercent(now: Date(timeIntervalSince1970: 1_000)) == 0)
        #expect(window.secondsUntilReset(now: Date(timeIntervalSince1970: 1_001)) == nil)
    }

    @Test("levels band at 60 and 85 percent")
    func levels() {
        #expect(SidebarClaudeUsageLevel(percent: 59) == .normal)
        #expect(SidebarClaudeUsageLevel(percent: 60) == .elevated)
        #expect(SidebarClaudeUsageLevel(percent: 84) == .elevated)
        #expect(SidebarClaudeUsageLevel(percent: 85) == .critical)
    }
}
