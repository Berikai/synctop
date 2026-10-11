import Foundation
import SyncTopCore

@main
struct SyncTopTestRunner {
    static func main() async {
        print("🚀 Running SyncTopCore Test Suite...")
        var passed = 0
        var failed = 0

        func test(_ name: String, block: () async throws -> Void) async {
            do {
                try await block()
                print("  ✅ [PASS] \(name)")
                passed += 1
            } catch {
                print("  ❌ [FAIL] \(name): \(error)")
                failed += 1
            }
        }

        await test("ExcludePreset correctly resolves developer and system rules") {
            let rules = ExcludePreset.resolveExcludePatterns(
                includeDeveloper: true,
                includeSystem: true,
                customRules: ["*.tmp", "node_modules/**"]
            )
            assert(rules.contains("node_modules/**"))
            assert(rules.contains(".git/**"))
            assert(rules.contains(".DS_Store"))
            assert(rules.contains("*.tmp"))
            let count = rules.filter { $0 == "node_modules/**" }.count
            assert(count == 1, "Duplicate rule found")
        }

        await test("SyncProfile formats remote path cleanly") {
            let profile = SyncProfile(
                name: "Work Notes",
                localPath: "/Users/test/Notes",
                remoteName: "google:",
                remotePath: "/Backups/Notes/"
            )
            assert(profile.fullRemotePath == "google:Backups/Notes")
        }

        await test("RcloneEngine builds correct arguments for bidirectional bisync") {
            let profile = SyncProfile(
                name: "Vault",
                localPath: "/Users/test/Vault",
                remoteName: "google",
                remotePath: "Backups/Vault",
                direction: .bidirectional,
                isDeveloperPresetEnabled: true,
                isSystemPresetEnabled: false,
                customExcludes: ["*.log"],
                isBisyncInitialized: false
            )
            let engine = RcloneEngine()
            let args = engine.buildArguments(for: profile, isDryRun: true)

            assert(args.contains("bisync"))
            assert(args.contains("/Users/test/Vault"))
            assert(args.contains("google:Backups/Vault"))
            assert(args.contains("--conflict-resolve"))
            assert(args.contains("newer"))
            assert(args.contains("--conflict-loser"))
            assert(args.contains("pathname"))
            assert(args.contains("--conflict-suffix"))
            assert(args.contains("sync-conflict"))
            assert(args.contains("--resync"))
            assert(args.contains("--dry-run"))
            assert(args.contains("node_modules/**"))
            assert(args.contains("*.log"))
            assert(!args.contains(".DS_Store"))
        }

        await test("RcloneEngine builds correct arguments for push backup") {
            let profile = SyncProfile(
                name: "Projects",
                localPath: "/Users/test/Projects",
                remoteName: "google",
                remotePath: "Cloud/Projects",
                direction: .push,
                isDeveloperPresetEnabled: false,
                isSystemPresetEnabled: true
            )
            let engine = RcloneEngine()
            let args = engine.buildArguments(for: profile, isDryRun: false)

            assert(args.contains("sync"))
            assert(args[1] == "/Users/test/Projects")
            assert(args[2] == "google:Cloud/Projects")
            assert(!args.contains("bisync"))
            assert(args.contains(".DS_Store"))
        }

        await test("SyncScheduler accurately identifies due profiles") {
            let now = Date()
            let scheduler = SyncScheduler()

            let p1 = SyncProfile(
                name: "Profile 1",
                localPath: "/tmp/p1",
                remotePath: "p1",
                isAutoSyncEnabled: true,
                scheduleIntervalMinutes: 60,
                lastSyncDate: now.addingTimeInterval(-3700),
                lastSyncStatus: .success
            )

            let p2 = SyncProfile(
                name: "Profile 2",
                localPath: "/tmp/p2",
                remotePath: "p2",
                isAutoSyncEnabled: true,
                scheduleIntervalMinutes: 60,
                lastSyncDate: now.addingTimeInterval(-1800),
                lastSyncStatus: .success
            )

            let p3 = SyncProfile(
                name: "Profile 3 (Manual)",
                localPath: "/tmp/p3",
                remotePath: "p3",
                isAutoSyncEnabled: false
            )

            let due = scheduler.profilesDueForSync(profiles: [p1, p2, p3], now: now)
            assert(due.count == 1)
            assert(due.first?.name == "Profile 1")
        }

        await test("RcloneDiscovery locates binary and discovers local remotes") {
            let discovery = RcloneDiscovery()
            let binary = discovery.locateBinary()
            assert(binary != nil, "Should locate rclone binary")
            print("     📍 Found binary at: \(binary?.path ?? "")")

            let info = try await discovery.discover()
            print("     ℹ️ Version: \(info.version)")
            print("     ☁️ Remotes detected: \(info.remotes)")
            assert(info.remotes.contains("google"), "Should detect configured 'google' remote")
        }

        print("\n🏁 Summary: \(passed) passed, \(failed) failed.")
        if failed > 0 {
            exit(1)
        }
    }
}
