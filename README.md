# DeviceFarmScheduler — Demo

**A SwiftUI console that runs the same 30 minutes of device-farm traffic through three scheduling
policies and shows you which team paid for each one.**

This app consumes [**device-farm-scheduler-kit**](https://github.com/rajatslakhina/device-farm-scheduler-kit)
as a remote Swift package. There is no copy of the library in this repository —
`Demo.xcodeproj` resolves it from GitHub, constrained to the `2.x` line.

---

## Why this matters

`vphone-cli` made it possible to boot real iOS 27 firmware in a VM on Apple Silicon. That turned
"iOS device farm" from a procurement problem into a scheduling problem — and scheduling problems
are where reasonable-sounding choices quietly pick a loser.

The console exists to make the losing visible, because the headline number is where the damage
hides. A policy here posts a **91% cache hit rate** while running one team's test suite **twice in
half an hour**. Both facts are true of the same run. Only one of them fits on a dashboard.

## What you see

The app is deliberately harder on the fleet than the library's own fixture. The library's README
quotes an **eight**-host farm; this app runs **six**, which pushes it from comfortable into
contended — the regime where the policy choice stops being academic. Same tenants, same two OS
builds, same bursty agent fan-out, same seed.

Switch the picker at the top and these are the numbers that move:

| Policy | Runs started | Warm hit rate | Restore paid | Worst wait | Worst-served tenant |
|---|---|---|---|---|---|
| **Layered** (DRR + delay scheduling) | 182 | 56% | 38 min | **752 s** | `checkout` |
| Affinity-first | 192 | **91%** | 27 min | 1410 s | **`payments`** |
| Strict fairness | 94 | 32% | 111 min | 1320 s | `checkout` |

The per-tenant rows underneath are the point:

| Under affinity-first | ran | still queued | worst wait |
|---|---|---|---|
| `checkout` (60% of arrivals) | 146 | 10 | 496 s |
| `search` (30%) | 44 | 31 | 1320 s |
| **`payments` (10%)** | **2** | **18** | **1410 s** |

A 91% hit rate, and the smallest tenant got two runs in thirty minutes. Warmth is a proxy for
"ran recently", so ranking by warmth hands the farm to whoever already had it. Under the layered
policy `payments` runs 15 times instead of 2, and the tenant left holding the backlog is
`checkout` — the biggest one, which is the correct place for a backlog to land.

There is also an admission banner, and on this fleet it reports a **miss**: `AdmissionController`
is configured with a 300-second wait budget, and the layered policy's worst-served tenant waited
752. Six hosts is not enough for this workload under any policy, and a console that only showed
the winning policy's best column would not have told you that.

The banner says plainly what it is comparing, because the distinction matters: **this replay does
not apply admission control.** `FarmSimulation` enqueues every arrival unconditionally, so what
you see is the *unclipped* cost measured against the budget the farm would have quoted — not a
report that admission control ran and held. Under strict fairness `checkout`'s backlog reaches
119, well past the same policy's 96-job per-tenant cap, which is the same fact from the other
direction. Admitting everything is the right choice for comparing placement policies (clipping
the queue would hide the differences) and the wrong thing to quietly call a service level.

The third panel sizes the warm pool against the observed arrival histogram, bucketed into
30-second observation windows. The curve `[10040, 7820, 5600, 3700, 2240, 1420, 1080]` falls
monotonically, so it recommends holding the full burst — the answer you would have guessed,
arrived at by evaluating the real cost at every depth rather than assuming it. Make idle hosts
expensive and the recommendation moves, which is why the app draws the whole curve and not just
the winner.

## Design decisions in this app

Most of the interesting decisions live in the library and are documented there. Three are this
app's own:

**Six hosts, not eight — and rebuilt rather than mutated.** Reproducing the library's fixture
exactly would have given the console nothing to show that its README does not already say. The
contended fleet is the demo. `WorkloadSpec` is a value type with `let` properties, so
`DemoWorkload.makeSpec()` constructs a new one field by field instead of tweaking a copy;
*rejected* was adding a `with(hostCount:)` mutator to the library, which would have made a
workload editable halfway through a run and its results unreplayable.

**The view takes its configuration as a parameter.** `FarmConsoleView` could have read
`ReferenceWorkload` directly and needed no wiring at all. *Rejected*, because a UI module that
hardcodes a fixture is one you can only ever use for a demo — the fleet being reasoned about
belongs to whoever runs the console, which is exactly why this app can hand it a different one.

**The observation window is passed explicitly, not defaulted.** *Rejected* was letting
`FarmConsoleConfiguration` default it, because the wrong value fails silently: bucket arrivals
per tick instead of per burst and the sizer answers a question about seconds, recommends a warm
pool of zero, and renders a confident rising chart. An earlier revision of this app did exactly
that. A required parameter is the cheapest possible fix and it is why the panel above is correct.

## Screenshots

**There are none, and this section exists to say so rather than to quietly omit it.**

This project was built by an unattended scheduled task. Access to the Simulator was requested
three times and refused each time with:

> Computer-use access to "Simulator" can't be approved during a scheduled run. To grant it, send
> a message in this conversation (the approval card will appear), or add the app to the scheduled
> task's settings. (Retrying returns this same result.)

So there is no `Demo/Screenshots/` directory, and nothing in this README describes an image that
does not exist.

## What was and was not verified

Kept separate, because "builds for a Simulator" and "ran on a Simulator" are different claims and
conflating them is the easy lie here.

**Checked by CI on this repository** — see the Actions tab for the result on the current commit:

- `xcodebuild -resolvePackageDependencies` — the remote package resolves from GitHub. No
  `Package.resolved` is committed, so resolution reaches the network on every run rather than
  replaying a cached graph, and the job prints the version it resolved.
- `xcodebuild build -scheme Demo -destination 'generic/platform=iOS Simulator'` — the app
  compiles against the resolved library for an iOS Simulator destination.

**Checked in the library's repository:** a clean `swift build -Xswiftc -warnings-as-errors` with
0 warnings, `swift test` with 98 tests and 0 failures, a grep enforcing that no suspension point appears in
the scheduler core, and a macOS job compiling the SwiftUI module for iOS Simulator.

**Not verified: the app has never been launched.** Nobody has seen it render. Every number in the
tables above comes from replaying this app's exact `WorkloadSpec` through `FarmSimulation` under
Swift 6.0.3 — the same deterministic, seeded code path the console calls on appear — and they are
pinned cell by cell — every column of all three rows, the whole per-tenant table, and the
wait-budget miss — by `testDemoAppSixHostNumbersArePinned` in the library's test suite, so they
cannot drift without CI failing there. That is an inference from a shared code path plus a
regression test, not an observation of the running app, and it is worth exactly that much.

## How to run it

```bash
git clone https://github.com/rajatslakhina/device-farm-scheduler-demo-app.git
cd device-farm-scheduler-demo-app
open Demo.xcodeproj
```

Then in Xcode:

1. Wait for **Package Dependencies** to resolve `device-farm-scheduler-kit` from GitHub (the
   first resolve needs a network connection).
2. Select the **Demo** scheme — it is committed as a shared scheme, so it appears on a fresh
   clone.
3. Pick any iOS 17+ Simulator and **Build & Run** (⌘R).

The console computes all three policy runs during `init`, so the first frame already has real
numbers; there is no loading state to sit through.

Requires Xcode 16+ and iOS 17+. Code signing is disabled in the project, so it builds and runs on
a Simulator with no development team configured.

## Structure

```
Demo.xcodeproj/          project.pbxproj + a shared Demo.xcscheme
Demo/DemoApp.swift       @main App, and the six-host workload it owns
.github/workflows/ci.yml resolve the remote package, then build for iOS Simulator
```

`DemoApp.swift` imports both library products for a real reason: the app owns its own
`WorkloadSpec` (from `DeviceFarmScheduler`) and hands it to `FarmConsoleView` (from
`DeviceFarmSchedulerUI`).

## The library

Design decisions, trade-offs, rejected alternatives, and the full measured comparison including
the naive-layering baseline that motivated the whole design:
**[device-farm-scheduler-kit](https://github.com/rajatslakhina/device-farm-scheduler-kit)**

## License

MIT
