import CmuxSwiftRender
import Foundation
import Testing
@testable import CmuxSidebar

@Suite("SidebarCodexUsage")
struct SidebarCodexUsageTests {
    @Test("parses a weekly-only Pro report")
    func parsesWeeklyOnly() throws {
        let usage = try #require(SidebarCodexUsage.parse("cx1 plan=pro d7=5 d7r=1794378986 ob=1793800000"))
        #expect(usage.plan == "pro")
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == .init(usedPercent: 5, resetsAt: Date(timeIntervalSince1970: 1_794_378_986)))
        #expect(usage.observedAt == Date(timeIntervalSince1970: 1_793_800_000))
    }

    @Test("encoded form round-trips with both windows")
    func roundTrips() {
        let usage = SidebarCodexUsage(
            plan: "plus",
            fiveHour: .init(usedPercent: 61, resetsAt: Date(timeIntervalSince1970: 1_793_700_000)),
            sevenDay: .init(usedPercent: 12, resetsAt: nil),
            observedAt: Date(timeIntervalSince1970: 1_793_690_000)
        )
        #expect(SidebarCodexUsage.parse(usage.encoded) == usage)
    }

    @Test("stays apart from Claude and activity reports")
    func versionsDoNotCross() {
        #expect(SidebarCodexUsage.parse("v1 who=dev d7=5") == nil)
        #expect(SidebarClaudeUsage.parse("cx1 plan=pro d7=5") == nil)
        #expect(SidebarAgentActivity.parse("cx1 plan=pro d7=5") == nil)
        #expect(SidebarCodexUsage.parse("cx1 plan=pro") == nil)
    }

    @Test("sanitizes the plan id")
    func sanitizesPlan() throws {
        let usage = try #require(SidebarCodexUsage.parse("cx1 plan=pro\u{1B}lite;x d7=1"))
        #expect(usage.plan == "prolitex")
    }

    @Test("custom-sidebar value carries Codex usage, observed time first")
    func customSidebarValue() throws {
        let now = Date(timeIntervalSince1970: 1_793_770_000)
        let codex = SidebarCodexUsage(
            plan: "pro",
            fiveHour: nil,
            sevenDay: .init(usedPercent: 5, resetsAt: now.addingTimeInterval(86_400)),
            observedAt: now.addingTimeInterval(-60)
        )
        let value = try #require(SidebarDevBoxCustomSidebarValue.value(
            usage: nil, usageReportedAt: nil, activity: nil,
            codexUsage: codex, codexUsageReportedAt: now, now: now
        ))
        guard case let .object(fields) = value, case let .object(codexFields)? = fields["codexUsage"] else {
            Issue.record("unexpected shape \(value)")
            return
        }
        #expect(fields["usage"] == nil)
        #expect(codexFields["plan"] == .string("pro"))
        #expect(codexFields["h5"] == nil)
        #expect(codexFields["d7"] == .int(5))
        #expect(codexFields["d7Reset"] == .int(1_793_856_400))
        #expect(codexFields["at"] == .int(1_793_769_940))
    }
}
