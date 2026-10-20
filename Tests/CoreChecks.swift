import Foundation

@main
struct CoreChecks {
    @MainActor static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); count += 1
        }
        check(DisplaySelection.ids(available: [1, 2, 3], automatic: 2, selected: 0, all: true) == [1, 2, 3], "all displays")
        check(DisplaySelection.ids(available: [1, 2], automatic: 1, selected: 2, all: false) == [2], "specific screen")
        check(DisplaySelection.ids(available: [1], automatic: 1, selected: 2, all: false) == [1], "disconnected screen fallback")
        check(DisplaySelection.ids(available: [], automatic: nil, selected: 2, all: true).isEmpty, "no displays")
        check(DisplaySelection.ids(available: [3, 3, 1], automatic: nil, selected: 0, all: true) == [1, 3], "deduplicate displays")
        // Exercise full sprite extents against growing/shrinking activity labels and asymmetric wings.
        for width in [CGFloat(180), 300, 410, 780] {
            for left in [CGFloat(12), 40, 72] {
                for right in [CGFloat(12), 80, 140] {
                    for radius in [CGFloat(8), 20, 48, 100] {
                        let bounds = PokemonBounds.range(halfWidth: width / 2, leading: left, trailing: right, radius: radius)
                        let x = PokemonBounds.clamp(999, to: bounds)
                        if width - left - right >= 2 * radius {
                            check(x + radius <= width / 2 - right + 0.001, "right sprite boundary")
                            check(PokemonBounds.clamp(-999, to: bounds) - radius >= -width / 2 + left - 0.001, "left sprite boundary")
                        } else { check(bounds.lowerBound == bounds.upperBound, "oversized sprite has no roaming space") }
                    }
                }
            }
        }
        let now = Date()
        let time = now.timeIntervalSince1970
        func job(_ id: String = "test-1", _ state: LightroomExportJob.State = .running, total: Int = 10, done: Int = 4, failed: Int = 0, age: Double = 0) -> LightroomExportJob {
            LightroomExportJob(version: 1, id: id, state: state, total: total, completed: done, failed: failed,
                startedAt: time - 100, updatedAt: time - age, currentFile: "A & B.jpg", outputFolder: "/tmp/exports", message: nil)
        }
        check(job().validated(now: now)?.progress == 0.4, "progress")
        check(job(age: 46).validated(now: now)?.state == .interrupted, "stale heartbeat")
        check(job(done: 11).validated(now: now) == nil, "reject invalid counts")
        check(job("../../bad").validated(now: now) == nil, "reject invalid job ID")
        check(job("future", age: -120).validated(now: now) == nil, "reject future timestamps")
        check(job("incomplete", .completed).validated(now: now) == nil, "reject false success")
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .xml
        try encoder.encode(job()).write(to: folder.appendingPathComponent("valid.plist"))
        try Data("partial garbage".utf8).write(to: folder.appendingPathComponent("broken.plist"))
        try Data(repeating: 65, count: 70000).write(to: folder.appendingPathComponent("huge.plist"))
        try encoder.encode(job("stale", age: 80)).write(to: folder.appendingPathComponent("stale.plist"))
        let found = LightroomExportService.readJobs(in: folder, now: now)
        check(found.count == 2, "ignore corrupt/oversized files")
        check(found.first { $0.id == "stale" }?.state == .interrupted, "stale reader state")
        let service = LightroomExportService(folder: folder)
        var alerts = 0; service.onFinish = { _ in alerts += 1 }
        service.accept([job("old", .completed, done: 10)])
        check(alerts == 0, "do not replay historical completion alerts")
        let recent = LightroomExportJob(version: 1, id: "recent", state: .completed, total: 1, completed: 1, failed: 0,
            startedAt: time, updatedAt: time, currentFile: nil, outputFolder: nil, message: nil)
        service.accept([recent]); service.accept([recent])
        check(alerts == 1, "completion alert only once")
        service.accept([job("a",total:10,done:5), job("b",total:30,done:10)])
        check(service.countLabel == "15/40", "concurrent export counts")
        check(service.progress == 0.375, "weighted concurrent progress")
        service.accept([recent,job()]); service.clearFinished()
        check(service.jobs.count == 1 && service.jobs[0].state == .running, "clear only finished")
        // Parse real Lua-emitted fixture files when provided by the plug-in checks.
        if CommandLine.arguments.count > 2 {
            let luaJobs = LightroomExportService.readJobs(in: URL(fileURLWithPath: CommandLine.arguments[2]), now: Date())
            check(luaJobs.contains { $0.state == .completed && $0.completed == 3 }, "Lua -> Swift success")
            check(luaJobs.contains { $0.state == .failed && $0.failed == 1 }, "Lua -> Swift failure")
            check(luaJobs.contains { $0.state == .cancelled }, "Lua -> Swift cancellation")
            check(luaJobs.contains { $0.currentFile == "A & B <photo>.jpg" }, "Lua XML escaping")
        }
        print("Passed \(count) core checks: display selection, sprite boundaries, snapshot validation, concurrent exports and notifications.")
    }
}
