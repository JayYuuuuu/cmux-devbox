import CmuxSwiftRender
import Foundation
import Testing
@testable import CmuxSidebar

@Suite("SidebarAgentActivity")
struct SidebarAgentActivityTests {
    @Test("parses a full report with percent-encoded text")
    func parsesFullReport() throws {
        let activity = try #require(SidebarAgentActivity.parse(
            "v1 ev=agent st=working at=1793770000 agent=claude who=dev d=ai-ecommerce t=%E4%BF%AE%E4%B8%80%E4%B8%8B%20bug"
        ))
        #expect(activity.state == .working)
        #expect(activity.since == Date(timeIntervalSince1970: 1_793_770_000))
        #expect(activity.agent == "claude")
        #expect(activity.who == "dev")
        #expect(activity.directory == "ai-ecommerce")
        #expect(activity.title == "修一下 bug")
    }

    @Test("encoded form round-trips, including spaces and CJK")
    func roundTrips() throws {
        for state in SidebarAgentActivity.State.allCases {
            let activity = SidebarAgentActivity(
                state: state,
                since: Date(timeIntervalSince1970: 1_793_770_123),
                agent: "codex",
                who: "air13home",
                directory: "cmux devbox",
                title: "把 = 和 % 都处理好"
            )
            #expect(SidebarAgentActivity.parse(activity.encoded) == activity)
        }
    }

    @Test("rejects bodies that are not agent reports")
    func rejectsOtherBodies() {
        #expect(SidebarAgentActivity.parse("v1 who=dev h5=3 d7=7") == nil)
        #expect(SidebarAgentActivity.parse("v1 ev=agent st=sleeping at=1") == nil)
        #expect(SidebarAgentActivity.parse("v1 ev=agent st=done") == nil)
        #expect(SidebarAgentActivity.parse("v2 ev=agent st=done at=1") == nil)
        #expect(SidebarAgentActivity.parse("hello") == nil)
    }

    @Test("older builds drop agent reports: they are not usage reports")
    func usageParserIgnoresAgentReports() {
        let body = SidebarAgentActivity(
            state: .waiting, since: Date(timeIntervalSince1970: 1_793_770_000),
            agent: "claude", who: "yujie", directory: "x", title: "y"
        ).encoded
        #expect(SidebarClaudeUsage.parse(body) == nil)
    }

    @Test("titles are single-line, control-free, and capped")
    func sanitizesTitle() {
        let long = String(repeating: "长", count: 300)
        let activity = SidebarAgentActivity(
            state: .working, since: Date(timeIntervalSince1970: 5),
            agent: "c\u{1B}laude", who: "a b", directory: "", title: "  first\n\tsecond\u{07} \(long)"
        )
        #expect(activity.agent == "claude")
        #expect(activity.who == "ab")
        #expect(activity.title.hasPrefix("first second "))
        #expect(activity.title.count == 120)
        #expect(!activity.encoded.contains(" t= "))
    }

    @Test("custom-sidebar value carries usage and activity")
    func customSidebarValue() throws {
        let now = Date(timeIntervalSince1970: 1_793_770_000)
        let usage = SidebarClaudeUsage(
            who: "dev",
            fiveHour: .init(usedPercent: 42, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: .init(usedPercent: 16, resetsAt: now.addingTimeInterval(-1))
        )
        let activity = SidebarAgentActivity(
            state: .done, since: now, agent: "claude", who: "dev", directory: "ai-ecommerce", title: "hi"
        )
        let value = try #require(SidebarDevBoxCustomSidebarValue.value(
            usage: usage, usageReportedAt: now, activity: activity, now: now
        ))
        guard case let .object(fields) = value,
              case let .object(usageFields)? = fields["usage"],
              case let .object(activityFields)? = fields["activity"] else {
            Issue.record("unexpected shape \(value)")
            return
        }
        #expect(usageFields["who"] == .string("dev"))
        #expect(usageFields["h5"] == .int(42))
        #expect(usageFields["h5Reset"] == .int(1_793_773_600))
        #expect(usageFields["d7"] == .int(0))
        #expect(usageFields["d7Reset"] == nil)
        #expect(usageFields["at"] == .int(1_793_770_000))
        #expect(activityFields["state"] == .string("done"))
        #expect(activityFields["dir"] == .string("ai-ecommerce"))
        #expect(activityFields["title"] == .string("hi"))
        #expect(SidebarDevBoxCustomSidebarValue.value(usage: nil, usageReportedAt: nil, activity: nil, now: now) == nil)
    }

    @Test("extra workspace fields merge without replacing built-in keys")
    func extraFieldsMerge() {
        let snapshot = CustomSidebarWorkspaceSnapshot(
            id: UUID(), title: "主号 1", isSelected: false, isPinned: false, index: 0,
            directory: "/", listeningPorts: [], unreadCount: 0, surfaces: [], surfaceCount: 1,
            customDescription: nil, customColor: nil, gitBranch: nil, gitIsDirty: false,
            pullRequestValues: [], progress: nil, latestConversationMessage: nil,
            latestSubmittedMessage: nil, latestSubmittedAt: nil, remote: nil,
            extraFields: ["devbox": .object(["k": .int(1)]), "title": .string("spoof")]
        )
        guard case let .object(fields) = CustomSidebarDataContextBuilder().workspaceValue(snapshot) else {
            Issue.record("not an object")
            return
        }
        #expect(fields["devbox"] == .object(["k": .int(1)]))
        #expect(fields["title"] == .string("主号 1"))
    }
}
