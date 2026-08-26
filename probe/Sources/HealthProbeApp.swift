import SwiftUI
import HealthKit
import os

struct StageResult: Identifiable {
    let id = UUID()
    let name: String
    let ok: Bool?
    let detail: String
}

@main
struct HealthProbeApp: App {
    @StateObject private var runner = ProbeRunner()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List(runner.results) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.name).font(.headline)
                            Spacer()
                            Text(r.ok == nil ? "…" : (r.ok! ? "PASS" : "FAIL"))
                                .font(.caption.bold())
                                .foregroundColor(r.ok == nil ? .gray : (r.ok! ? .green : .red))
                        }
                        Text(r.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("HealthKit Probe")
                .task { await runner.runAll() }
            }
        }
    }
}

@MainActor
final class ProbeRunner: ObservableObject {
    @Published var results: [StageResult] = []
    private let log = Logger(subsystem: "work.danieltuma.healthprobe", category: "probe")
    private let store = HKHealthStore()

    func stage(_ name: String, _ detail: String, _ ok: Bool?) {
        results.append(StageResult(name: name, ok: ok, detail: detail))
        print("PROBE|\(name)|\(ok.map { $0 ? "PASS" : "FAIL" } ?? "RUN")|\(detail)")
        log.info("stage=\(name, privacy: .public) ok=\(ok ?? false) \(detail, privacy: .public)")
    }

    func runAll() async {
        stage("INIT", "HKHealthStore instance created", true)

        let available = HKHealthStore.isHealthDataAvailable()
        stage("IS_AVAILABLE", "isHealthDataAvailable() == \(available)", nil)

        guard available else {
            stage("REQUEST_AUTH", "skipped: health data unavailable without entitlement", false)
            stage("QUERY", "skipped: health data unavailable without entitlement", false)
            finish()
            return
        }

        let steps = HKQuantityType(.stepCount)!
        let sleep = HKCategoryType(.sleepAnalysis)

        do {
            try await store.requestAuthorization(toShare: [sleep], read: [steps])
            stage("REQUEST_AUTH", "requestAuthorization completed without error", true)
        } catch {
            stage("REQUEST_AUTH", "error: \(error.localizedDescription)", false)
            finish()
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: steps, limit: 5, sortDescriptors: [sort]) { _, samples, err in
            Task { @MainActor in
                if let err {
                    self.stage("QUERY", "steps query error: \(err.localizedDescription)", false)
                } else {
                    self.stage("QUERY", "steps query returned \((samples as? [HKQuantitySample])?.count ?? 0) samples", true)
                }
                self.finish()
            }
        }
        store.execute(q)
    }

    private func finish() {
        print("PROBE|DONE")
        if ProcessInfo.processInfo.environment["PROBE_AUTOEXIT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
        }
    }
}
