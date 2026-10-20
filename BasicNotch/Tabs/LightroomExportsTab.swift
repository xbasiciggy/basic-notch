import SwiftUI

struct LightroomExportsTab: View {
    @ObservedObject var exports: LightroomExportService
    let openGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Lightroom Classic exports", systemImage: "photo.badge.arrow.down").font(.headline)
                Spacer()
                Button("Save Plug-in…") { exports.savePlugin() }
                Button("Setup Guide", action: openGuide)
                Button("Clear Finished") { exports.clearFinished() }.disabled(exports.jobs.isEmpty)
            }
            .buttonStyle(PillButtonStyle())
            if let error = exports.setupError { Text(error).font(.caption).foregroundStyle(.red) }
            if exports.jobs.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "camera.aperture").font(.system(size: 28)).foregroundStyle(.cyan)
                    Text("Your exports, at a glance").font(.headline)
                    Text("Save the companion plug-in, add it in Lightroom Classic’s Plug-in Manager, then insert BasicNotch Export Monitor under Export → Post-Process Actions.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 510)
                    Text("Only exports using that action are monitored. Your files and export settings stay unchanged.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(exports.jobs) { job in
                            HStack(spacing: 12) {
                                Image(systemName: job.state == .completed ? "checkmark.circle.fill" : job.state == .running ? "photo.badge.arrow.down" : "exclamationmark.circle")
                                    .foregroundStyle(job.state == .completed ? .green : job.state == .running ? .cyan : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(job.title).font(.caption.bold())
                                        Spacer()
                                        Text("\(job.processed)/\(job.total)").font(.caption.monospacedDigit())
                                    }
                                    ProgressView(value: job.progress).tint(job.failed == 0 ? .cyan : .orange)
                                    Text(detail(job)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if job.outputFolder != nil {
                                    Button("Show Folder") { exports.reveal(job) }.buttonStyle(PillButtonStyle())
                                }
                            }
                            .padding(9).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                        }
                    }
                }
            }
        }
    }

    private func detail(_ job: LightroomExportJob) -> String {
        if job.state == .interrupted { return "No update for 45 seconds. Lightroom may have closed or the plug-in stopped." }
        if job.failed > 0 { return "\(job.completed) rendered · \(job.failed) failed · \(job.message ?? "Check Lightroom for details")" }
        return job.currentFile ?? job.message ?? "Waiting for Lightroom…"
    }
}
