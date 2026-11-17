import Foundation
import CleanupCore

func expect(_ condition: Bool, _ message: String = "Safety assertion failed") {
    precondition(condition, message)
}

@main
struct SafetyTests {
    static func main() throws {
        let tests = SafetyTests()
        try tests.onlyExitedAndDeadContainersAreCandidates()
        try tests.stoppedContainersStillProtectTheirVolumes()
        tests.resourceDeletionNeverForcesAndPreservesIDsAsArguments()
        try tests.liveReadOnlyScan()
        print("PASS: all safety checks")
    }
    func fixture(_ status: String, id: String = "container") throws -> Container {
        let data = """
        {"Id":"\(id)","Name":"/database","Image":"sha256:used","State":{"Status":"\(status)"},"Mounts":[{"Type":"volume","Name":"database"},{"Type":"bind","Source":"/tmp"}]}
        """
        return try JSONDecoder().decode(Container.self, from: Data(data.utf8))
    }

    func onlyExitedAndDeadContainersAreCandidates() throws {
        for status in ["running", "paused", "created", "restarting", "removing"] {
            expect(try Safety.stopped([fixture(status)]).isEmpty)
        }
        for status in ["exited", "dead"] {
            expect(try Safety.stopped([fixture(status)]).map(\.name) == ["database"])
        }
    }

    func stoppedContainersStillProtectTheirVolumes() throws {
        for status in ["running", "paused", "created", "exited", "dead"] {
            let candidates = Safety.unusedVolumes(["database", "orphan"], containers: [try fixture(status)])
            expect(candidates.map(\.id) == ["orphan"])
        }
    }

    func resourceDeletionNeverForcesAndPreservesIDsAsArguments() {
        for category in [Category.containers, .images, .volumes, .networks] {
            let command = Safety.removalCommand(category, id: "some name; echo unsafe")!
            expect(!command.contains("--force"))
            expect(!command.contains("-f"))
            expect(command.count == 3)
            expect(command.last == "some name; echo unsafe")
        }
        expect(Safety.removalCommand(.cache, id: "cache") == nil)
    }

    func liveReadOnlyScan() throws {
        guard ProcessInfo.processInfo.environment["ORBSWEEP_LIVE_TEST"] == "1" else { return }
        let snapshot = try DockerClient().scan()
        expect(!snapshot.usage.isEmpty)
        expect(!snapshot[.networks].contains { ["bridge", "host", "none"].contains($0.name) })
        print("Read-only scan: \(snapshot.usage.count) usage categories; \(snapshot[.volumes].count) unused volumes")
    }
}
