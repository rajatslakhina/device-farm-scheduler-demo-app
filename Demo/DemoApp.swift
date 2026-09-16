import SwiftUI
import DeviceFarmScheduler
import DeviceFarmSchedulerUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            FarmConsoleView(configuration: DemoWorkload.configuration)
        }
    }
}

/// The workload the console renders.
///
/// It lives in the app, not in the library, and that is the point of the
/// split. `FarmConsoleView` takes a `FarmConsoleConfiguration` as a parameter
/// precisely so the fleet being reasoned about belongs to whoever is running
/// the console — a UI module that hardcodes its own fixture is a UI module you
/// can only ever use for a demo.
///
/// This app's fleet is the library's `ReferenceWorkload` with one deliberate
/// change: **six hosts instead of eight.** Every number quoted in the library's
/// README comes from the eight-host fleet, so if this app reproduced it exactly
/// there would be nothing to see. Taking two hosts away pushes the farm from
/// comfortable into contended, which is the regime where the choice of
/// placement policy stops being academic — switch the picker at the top and the
/// warm hit rate and the worst-case wait move in opposite directions.
enum DemoWorkload {

    /// Two fewer hosts than the library's reference fleet.
    static let hostCount = 6

    static let configuration = FarmConsoleConfiguration(
        title: "Contended fleet · \(hostCount) hosts",
        subtitle: "Two OS builds, three tenants, bursty agent fan-out. One arrival "
            + "trace, replayed through three placement policies.",
        spec: makeSpec(),
        costModel: ReferenceWorkload.makeCostModel(),
        admissionPolicy: ReferenceWorkload.makeAdmissionPolicy(),
        // Must match the burst period. Bucketing per tick asks "how many runs
        // arrived this second", which on a bursty workload answers "zero" almost
        // always — and the sizer then correctly concludes no warm pool is ever
        // worth holding. Right about the model, wrong about the farm.
        observationWindowTicks: ReferenceWorkload.observationWindowTicks
    )

    /// The reference workload, rebuilt with a smaller fleet.
    ///
    /// Rebuilt field by field rather than mutated, because `WorkloadSpec` is a
    /// value type with `let` properties — which is deliberate on the library's
    /// side: a workload you can edit halfway through a run is a workload whose
    /// results cannot be replayed.
    static func makeSpec() -> WorkloadSpec {
        let reference = ReferenceWorkload.makeSpec()
        return WorkloadSpec(
            tenants: reference.tenants,
            catalog: reference.catalog,
            horizonTicks: reference.horizonTicks,
            hostCount: hostCount,
            hostCapacityBytes: reference.hostCapacityBytes,
            baseArrivalsPerTick: reference.baseArrivalsPerTick,
            burstEveryTicks: reference.burstEveryTicks,
            burstSize: reference.burstSize,
            burstJitter: reference.burstJitter,
            seed: reference.seed
        )
    }
}
