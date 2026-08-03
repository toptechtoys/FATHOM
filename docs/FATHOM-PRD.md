# FATHOM — Product Requirements Document

**An open-source system instrument and storage forensics tool for Apple Silicon Macs.**

| | |
|---|---|
| **Version** | 3.0 — design locked, reference hardware verified |
| **Date** | 30 July 2026 (v1.0: 28 July 2026) |
| **Owner** | EXHIBINAUT |
| **Status** | Pre-development. Requires seven technical spikes before build (§16). |
| **Review** | `/plan-ceo-review`, SCOPE EXPANSION mode. Six expansions accepted, four critical safety gaps found, one architecture layer added. See §19-§21. |
| **Licence** | MIT |
| **Platform** | macOS 14 (Sonoma) – macOS 26 (Tahoe), Apple Silicon only |
| **Distribution** | Developer ID, notarized, direct + Homebrew cask |

---

## 1. The bet, in one paragraph

Every Mac user eventually asks two questions: *what is my machine doing right now*, and *where did my disk space go*. Today those are two separate purchases from two separate vendors, and neither answers the question properly. System monitors like Stats show you a number but burn 50% of your battery to do it. Disk analysers like DaisyDisk show you a beautiful picture of a moment in time, then forget it — so they can never tell you what *changed*, and the number they show you is arithmetically wrong on exactly the files that matter most. FATHOM merges the two into one always-on instrument that is honest about its numbers, cheap enough to leave running forever, and open enough that you can read the code that decides what gets deleted.

---

## 2. Why this exists

### 2.1 The monitoring problem

Stats is the incumbent: 38.8k stars, MIT licensed, genuinely good. It also has a defect it documents in its own README — turning off the Sensors and Bluetooth modules *"could reduce CPU usage and power efficiency by up to 50% in some cases."* One user measured their Energy Impact dropping from 50–100 down to 6–10 simply by disabling unknown sensors ([Stats #2554](https://github.com/exelban/stats/issues/2554)).

This is not a bug to be patched. It is the direct consequence of an architectural choice, and understanding *why* is the whole reason a rewrite is justified rather than a fork:

Stats reads every sensor, on every bus, on every tick. Each SMC key read is a synchronous round trip to a separate microcontroller — kernel, driver, mailbox transaction — and there is no batch read, so N keys means N round trips. On top of that it queries `IOHIDEventSystemClient` for each of the ~47 thermal services, *and* subscribes to IOReport, *and* for Bluetooth it spawns `system_profiler` as a subprocess on a timer while running an active BLE scan. That is 150+ synchronous hardware transactions per second, every second, forever. On Apple Silicon, energy is dominated by whether the SoC can reach deep idle. A monitoring app that wakes the SoC 150 times a second to tell you the SoC is idle is a contradiction in terms.

The fix is architectural, not incremental: one bus per datum, tiered sampling by volatility, a single coalesced timer for the whole app, and — the largest single lever — sampling the full sensor set only while a window is actually visible. Nobody in the category has done this. That is the opening.

### 2.2 The storage problem

macOS is uniquely bad at telling you where your space went, and the reasons are structural.

Finder reports free space that includes *purgeable* space, so it will tell you there are 100 GB available while a copy fails for lack of room. Howard Oakley demonstrated the sharpest version of this: purgeable space in one volume cannot be purged to satisfy a write on a sibling volume in the same container, yet Finder reports container-wide purgeable as though it were universally available ([Eclectic Light](https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/)). "System Data" is not a category — it is the arithmetic residue of everything the classifier failed to classify, and the classifier is itself inaccurate.

Meanwhile APFS local snapshots are permitted to grow to as much as 80% of disk capacity by design. They pin the old extents of every changed or deleted block, so deleting a 50 GB video frees nothing until every snapshot referencing it is gone. And in macOS 26, Apple *removed* the snapshot subcommands from `diskutil` entirely — DTS's position being that snapshots are "a special purpose feature of APFS that should only be used for very specific use cases" ([Apple Forums 796852](https://developer.apple.com/forums/thread/796852)). The tooling gap just widened.

### 2.3 The evidence from this machine

The screenshots that prompted this project are themselves a good argument for the product. A Mac mini M4 Pro, 24 GB, 494 GB SSD:

| Reading | Value | What a good tool would say |
|---|---|---|
| Disk | 379.6 GB used, 114.8 GB free (77%) | Which of that 379 GB is *reclaimable*, and what grew this week |
| Swap | 8.49 GB, memory pressure "normal" | 8.5 GB of swap on a 24 GB machine at normal pressure is worth explaining |
| SMART: total written | 149.97 TB | — |
| SMART: power-on hours | 1,925 | ≈ 78 GB written per power-on hour, sustained |
| SMART: health | 95% | 5% of endurance consumed in ~80 days of uptime |
| SMART: unsafe shutdowns | 43 | Worth a flag |

Apple Silicon SSDs are soldered. They cannot be replaced without replacing the logic board. A sustained write rate that high — very likely swap-driven — is the kind of thing that should generate a notification, not sit in a diagnostic tab waiting to be noticed. No shipping tool connects "your memory is thrashing" to "your non-replaceable SSD is wearing out." That connection is a feature.

---

## 3. Positioning

### 3.1 Competitive landscape

**System monitors.** Every paid competitor — iStat Menus, TG Pro, Sensei, MacPulse — ships a privileged root helper, and every one of them uses it *only* for fan control. Every one of them also confirms independently that the Mac App Store sandbox makes thermal sensors, fan control, Bluetooth batteries, SMART health and power sensors impossible; iStat Menus's App Store build requires a separately downloaded helper just to show temperatures, and MacPulse's App Store build simply drops those features. That boundary is real and it is settled.

| Product | Price | Distribution | Notable gap |
|---|---|---|---|
| Stats | Free, MIT | Direct | The energy problem; no storage forensics |
| iStat Menus 7 | $12.99/yr | Direct + MAS | Closed source; MAS build crippled |
| TG Pro | ~$20 one-time | Direct | Thermal-focused only |
| Sensei | $29/yr or $59 | Direct | Live storage gauge but no history |
| MacPulse | Sub / Setapp | Direct + MAS | Publishes the clearest sandbox limitation list |
| macmon / mactop / SiliconScope | Free, OSS | CLI / niche | Correct architecture, no consumer product around it |

**Storage tools.**

| Product | Price | What it does | What it does not do |
|---|---|---|---|
| DaisyDisk | $9.99 | Sunburst, ~15s scan, clone+hardlink aware, snapshot deletion | No history, no background. MAS build disables purgeable reclaim and snapshot deletion |
| GrandPerspective | Free, GPL | Treemap, filters, manual before/after view compare | No persistent history, no background, no dev awareness |
| OmniDiskSweeper | Free | Column-view size listing | No visualisation, no history, no categories |
| CleanMyMac | Sub / one-time | Broadest feature set | No history. Opaque, non-auditable rules. Criticised for over-cleaning |
| DevCleaner | $29 lifetime | 23 dev ecosystems including AI model caches. Pro adds background auto-clean | No history, dev paths only, no whole-disk view |
| Sweep | from $9.95/mo | Cleanup, permissions, uninstaller | Advertises the *absence* of a daemon as a feature |
| **StorageRadar** | Free / $9.99 / $19.99 | Treemap + sunburst, **snapshot capture with diff**, dev profiles, dry run | On-demand only, no background, not open source |

### 3.2 Honest read on the differentiator

Research turned up a competitor that was not on the original list and that changes the pitch. **StorageRadar already ships snapshot capture and diffing** — its own site promises you can *"compare what grew, shrank, appeared, or disappeared."* Worse for us, snapshot capture is in its **free** tier; only the comparison export and dev-ecosystem cleanup sit behind the $19.99 Developer tier. "Track disk usage over time" is therefore *not* an unclaimed idea, and the PRD must not be written as though it were.

What *is* unclaimed, verifiably:

**First — continuous passive observation.** Every tool surveyed is on-demand. StorageRadar diffs two scans you asked for. GrandPerspective compares two views you opened. Nobody runs quietly and can already answer "what grew since yesterday" the moment you ask, without having asked you to prepare. One caveat worth taking seriously: two competitors advertise "no background daemon" as a *feature*, which suggests part of the market distrusts exactly this. That assumption needs validating early (§13).

**Second, and stronger — correct free-space accounting.** This is the real moat. When two files share physical extents via APFS cloning, deleting one frees nothing. When a file is sparse — OrbStack's disk image reports as 8 TB while occupying ~40 GB — its logical size is fiction. Every GUI tool in the category shows a number that is wrong precisely on the largest, most tempting items. The correct model, from the `duh` project, is to group files sharing physical blocks into *families*, credit each family's blocks once at the lowest common ancestor of its members, and treat a family with any member outside the scanned tree as contributing **zero** freeable bytes. FATHOM shows two numbers on every node, always together: *size on disk*, and *actually freed if deleted*. Nobody else does. It is provable, demonstrable in a screenshot, and technically hard enough to be defensible.

**Third — attribution, not just deltas.** StorageRadar can tell you *what* changed. Nothing tells you *why*. "Xcode created 14 GB of DerivedData across three branches on Tuesday" requires tying size deltas to FSEvents causality. Genuinely hard, genuinely unclaimed.

**Fourth — auditable reclaim.** The category's central credibility problem is opacity: CleanMyMac decides what "junk" means and you cannot inspect the reasoning. FATHOM's deletion rules ship as versioned, human-readable recipe files in the repository, each stating its regeneration cost. GrandPerspective is the only credible open-source competitor and it has no reclaim engine at all.

### 3.3 One-line positioning

> The instrument panel your Mac should have shipped with — always on, honest about its numbers, and open about what it deletes.

### 3.4 Naming

**FATHOM.** A fathom is a nautical unit of depth, and *to fathom* is to understand something completely. Both meanings are literally the product: measure how deep it goes, and understand what is down there. It reads well in a sentence — *"Fathom says Docker is holding 45 GB of dead space"* — and it is six letters, which fits a menu bar.

Collisions exist but sit in unrelated categories: Fathom Analytics (web analytics) and Fathom AI (meeting notes). Neither is macOS utility software. Before committing, check `fathom.app` availability, the `com.exhibinaut.fathom` bundle-identifier namespace, and run a basic trademark search in your operating jurisdictions.

Rejected alternatives: TIDE (strong for the Timeline feature, silent on the monitoring half), PLUMB (excellent meaning — measuring plus *exactly true* — but reads as plumbing to many people), KEEL (cleanest namespace, but implies stability rather than discovery).

## 4. Users

**The developer** is the primary target and the one whose pain is most acute. They lose 100+ GB to DerivedData, simulator runtimes, `node_modules`, Docker images and — increasingly — local LLM weights, and their machine is under sustained thermal and memory load. They will install from Homebrew, they will read the source before granting Full Disk Access, and they are the reason the reclaim recipes must be auditable.

**The creative professional** runs Final Cut, Logic or the Adobe suite, watches thermals during long renders, and loses tens of gigabytes to media caches they have never heard of. They do not want a terminal.

**The power user** already runs Stats or iStat Menus, cares about the numbers for their own sake, and is the most likely to notice and complain about battery impact.

**The worried owner** has a Mac that says "Your disk is almost full," does not know what "System Data" means, and is one search away from installing something predatory. Serving this person well, for free, with software they can audit, is the strongest argument for the open-source licence.

---

## 5. Product principles

**Honest numbers or no numbers.** If a value cannot be measured accurately it is shown as `—`, never as zero and never as a plausible-looking estimate. Where a number is derived rather than read, the UI says so. Where macOS itself reports something misleading — Finder's free space being the canonical case — FATHOM shows the true figure and explains the discrepancy rather than reproducing it.

**Idle by default.** The app's own energy cost is a first-class, tested, published metric with a hard budget (§10). Any feature that cannot meet the budget ships off by default with its cost stated in the settings UI.

**Reversible before destructive.** Where a choice exists between evicting, compacting and deleting, FATHOM offers them in that order. Eviction of an iCloud file is provably safe — the data is still in iCloud. Nothing is ever unlinked; everything goes to the Trash.

**No auto-delete, ever.** DevCleaner Pro's background auto-clean is the anti-pattern. A safety-first open-source tool declines to ship it, and says why.

**Auditable, not authoritative.** FATHOM never says "junk." It names the recipe that matched, links to that recipe's source, and states the regeneration cost — "this will cost you one full Xcode rebuild, roughly eight minutes."

**Degrade, never crash.** Every private-API dependency is resolved at runtime via `dlsym`. A missing symbol disables one module. It never prevents launch.

---

# PART I — THE MONITOR

## 6. Modules

### 6.1 What is genuinely feasible

Three corrections to the obvious feature list, all load-bearing, all discovered in research:

**Per-core CPU frequency does not exist on Apple Silicon.** DVFS is per-*cluster*. IOReport returns residency in each P-state per cluster; you compute a residency-weighted average MHz. Any tool showing per-core MHz is fabricating it. FATHOM shows per-cluster frequency and labels it as such.

**ANE utilisation does not exist.** There is no counter. asitop derives a percentage by dividing ANE power by a hardcoded guess at maximum ANE power. Bresink's System Monitor — a serious vendor — shows only a binary active/inactive indicator inferred from power gating, noting Apple permits "no further analysis." Stats closed the ANE-usage request as not-planned. FATHOM shows **ANE power in watts** and a binary active indicator. It does not show a fake percentage.

**Memory pressure cannot be polled.** Apple DTS is explicit: `vm.memory_pressure` "is not the droid you're looking for," and there is no API to read the current value — *"assume that memory pressure is normal until you get an event via the Dispatch source."* FATHOM uses `DispatchSource.makeMemoryPressureSource` for the authoritative three-level state, and separately shows a clearly-labelled *derived* pressure index computed from compressed + swap + wired against total. It never presents the derived number as macOS's own.

### 6.2 Module specification

| Module | Metric | Source | Access | Sandbox | Interval |
|---|---|---|---|---|---|
| **CPU** | Overall + per-core usage, user/sys/idle | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | Public | Yes | 1 s |
| | Load averages | `getloadavg(3)` | Public | Yes | 5 s |
| | E/P core counts and mapping | `sysctl hw.perflevel*`, IORegistry device tree | Public | Yes | Launch |
| | Per-cluster frequency | IOReport `CPU Stats` › `CPU Complex Performance States`, channels `ECPU`/`PCPU`/`PCPU1` + DVFS tables `voltage-states1-sram`, `voltage-states5-sram` | **Private** | No | 2 s |
| **GPU** | Utilisation, render, tiler, in-use memory | IORegistry `IOAccelerator` › `PerformanceStatistics` | IOKit | Yes | 1 s |
| | Frequency | IOReport `GPU Stats` + `voltage-states9` | **Private** | No | 2 s |
| | GPU power | IOReport `Energy Model` › `GPU0`, `GPU SRAM0` | **Private** | No | 2 s |
| | ANE power + active flag | IOReport `Energy Model` › `ANE0`, `ANE1` | **Private** | No | 2 s |
| **Memory** | Used/free/wired/compressed/app | `host_statistics64(HOST_VM_INFO64)` | Public | Yes | 1 s |
| | Swap used, in/out | `sysctl vm.swapusage` | Public | Yes | 2 s |
| | Pressure (authoritative) | `DispatchSource` memory pressure | Public | Yes | Event |
| | **Memory bandwidth (GB/s)** | IOReport `AMC Stats` › `Perf Counters`, `* DCS RD/WR` | **Private** | No | 2 s |
| **Disk** | Capacity, free (true) | `statfs` / `NSURLVolumeAvailableCapacityKey` | Public | Yes | 10 s |
| | Purgeable (separately labelled) | `...ForImportantUsage` minus `statfs` | Public | Yes | 10 s |
| | Read/write throughput | IORegistry `IOBlockStorageDriver` › `Statistics` | IOKit | Yes | 1 s |
| | SMART: TBW, health, cycles, hours, unsafe shutdowns | NVMe SMART log page 0x02 — **see spike S2** | TBD | No | 60 s |
| | **NVMe thermal throttle tiers** | IOReport `NVMe` › `BW Limits` | **Private** | No | 10 s |
| **Network** | Per-interface throughput | `sysctl` `IFMIB_IFDATA` (**not** `NET_RT_IFLIST2`) | Public | Yes | 1 s |
| | Local IP, interface type | `getifaddrs` + SystemConfiguration | Public | Yes | Event |
| | Wi-Fi SSID / RSSI | CoreWLAN — needs Location Services | Public | Yes | 10 s |
| | Public IP | HTTPS echo, cached | — | Yes | 6 h |
| | Latency / jitter | Unprivileged ICMP | Public | Yes | 30 s, opt-in |
| **Sensors** | Temperatures | `IOHIDEventSystemClient`, page `0xff00` usage `5`, event type 15 | **Private** | No | 2 s |
| | Fan RPM, min/max, target | SMC `FNum`, `F0Ac`, `F0Mn`, `F0Mx`, `F0Tg` | IOKit user client | No | 2 s |
| | Total system power | SMC `PSTR` | IOKit user client | No | 2 s |
| | Component power | IOReport `Energy Model` | **Private** | No | 2 s |
| **Battery** | Charge, state, time remaining | `IOPSCopyPowerSourcesInfo` | **Public, documented** | Yes | Event |
| | Cycles, design/nominal capacity, temperature | IORegistry `AppleSmartBattery` | IOKit | Probably | 60 s |
| | Health | Computed `NominalChargeCapacity / DesignCapacity` — `kIOPSBatteryHealthKey` is unreliable | — | — | 60 s |
| **Processes** | CPU, memory footprint, disk I/O | `proc_listpids` + `proc_pid_rusage(RUSAGE_INFO_V6)` | Public | Yes | 5 s, visible only |
| | Energy impact | Coefficients from `/usr/share/pmenergy/Mac-<board-id>.plist` — **spike S4** | — | — | 5 s |
| **Bluetooth** | Device list, battery | IORegistry `AppleDeviceManagementHIDEventService` › `BatteryPercent`, Bluetooth prefs domain | IOKit | Partial | 60 s |

### 6.3 Explicitly cut from v1, with reasons

**FPS.** No public system-wide API. `CVDisplayLink` gives display refresh cadence, not render rate. The only working approach requires Screen Recording permission on macOS 15+, which is an unacceptable tax for a menu bar utility. Stats shows FPS; FATHOM will not, and the FAQ will explain why.

**Per-process network.** Activity Monitor uses the private `NetworkStatistics.framework`. Apple DTS, asked directly for an alternative, offered none. The remaining options are linking a private Apple-internal framework, spawning `nettop` on a timer (which DTS themselves flagged as a CPU concern), or shipping a Network Extension system extension — disproportionate for this feature.

**Fan control.** Deferred to v2 at the earliest. It requires a root helper, and on M3/M4+ writing `F0Tg` alone does not work: `thermalmonitord` reverts it. The working sequence is to write `Ftst = 1` to enter diagnostic mode, retry the fan writes across a 3–6 second settling window, then restore `Ftst = 0`. TG Pro publicly concedes that on newer models fan control is hardware-gated and cannot be overridden. Stats has downgraded its own implementation to unmaintained legacy mode. Fan *monitoring* ships in v1; control does not.

**Per-core GPU statistics.** Not exposed.

---

# PART II — DISK INTELLIGENCE

This is the differentiated half of the product and should get the majority of engineering effort.

## 7. The scanning engine

### 7.1 Traversal

Published benchmarks contradict each other, and the contradiction is instructive. Apple DTS advises against `getattrlistbulk` — *"NSFileManager and enumeratorAtURL already use it internally and are highly optimized"* — and their measurements support that for enumeration alone. But `dumac` measured 409k files in 521 ms against `du`'s 3,330 ms, a 6.4× win, with a flamegraph showing ~91% of time in syscalls.

These measure different workloads. Apple measured names only, single-threaded. `dumac` measured names *plus sizes*, concurrently. FATHOM needs sizes, so it is in the second regime. The design follows from that: parallelise across directories with a bounded work-stealing pool, fetch attributes in the same syscall as the directory read rather than `readdir` + `stat`, and if using Foundation pass an explicit property array — never `nil`, which costs roughly 50% — wrapping iteration in `@autoreleasepool` (Apple's own test: 491 MB peak down to 6.3 MB).

**Spike S1 settles this empirically before the engine is written.**

### 7.2 The dataless-file trap

This is the single highest-severity implementation detail in the product.

Since Sonoma, iCloud's "Optimize Mac Storage" replaces evicted files with *dataless files*: full metadata, correct reported size, no data extents, indistinguishable from real files in Finder. **Any scanner that opens or reads file contents triggers a synchronous download of every evicted file** — potentially hundreds of gigabytes, silently, over the user's connection. A storage app that fills your disk while measuring it is a fatal, and richly ironic, one-star review.

Detection is `stat`/`getattrlist` and testing for `SF_DATALESS` in `st_flags`. FATHOM must never open file contents during traversal.

The corollary is a feature: *evicting* iCloud files via `brctl evict` is the safest reclaim action in the entire product, because the data provably still exists in iCloud. It leads the reclaim UI.

### 7.3 Accounting — the moat

Three sizes exist for any file and conflating them is how every competitor gets this wrong.

**Logical size** is `st_size`, what Finder's Get Info shows, and meaningless for sparse files. **Physical size** is `st_blocks × 512` — always 512-byte units on macOS regardless of filesystem block size — and this is what FATHOM sums. **Freeable size** is the one nobody computes, and it requires understanding extent sharing.

Hardlinks are the easy case: deduplicate on `(st_dev, st_ino)` when `st_nlink > 1`. `dumac` uses a 128-shard inode set to keep lock contention low under concurrent traversal, a directly reusable design.

APFS clones are the hard case. Two files with *different* inodes share physical extents through copy-on-write. Naive summation counts those bytes twice, and deleting one file frees nothing. Detection uses `getattrlist` with `ATTR_CMNEXT_CLONEID`.

> **Implementation note that will cost a day if missed:** the `duh` author reports the correct attribute value is `0x100`, not the documented `0x40`, verified by a self-test that creates real clones.

The accounting model groups files sharing physical blocks into **families**. Each family's blocks are credited once, at the lowest common ancestor of its members. A family with any member outside the scanned subtree contributes **zero** freeable bytes. Sibling sets that only free space when removed together are surfaced explicitly as "delete-together clusters."

**Every node in the UI shows two numbers, always together: size on disk, and freed if deleted.** This is the screenshot that sells the product.

### 7.4 The persistent index

A SQLite index holds the file tree with physical sizes, clone family identifiers and modification times, streamed in with bounded memory — `duh` demonstrates this at ~4M files.

Incremental updates come from FSEvents, and Apple's own documentation catalogues the pitfalls. Events are *directory-granular*: they say something in this directory changed, never which file or its new size, so each event triggers a re-enumeration of that directory and a diff against the cached state. `kFSEventStreamEventFlagMustScanSubDirs` is set both on genuine recursive changes and whenever events are dropped, so it is the one flag that must be handled correctly. Device IDs change across reboots, so `FSEventsCopyUUIDForDevice()` must be stored and validated on resume, with a mismatch forcing a full rescan. Monitoring must start *before* the initial scan begins or changes during that scan are lost permanently. And Apple explicitly advises backup software to run periodic full scans regardless.

Two constraints specific to this product: watching `/` requires Full Disk Access and will fire constantly against `/private/var/folders`, so FATHOM watches a curated path set instead. And critically — **snapshots and purgeable space generate no FSEvents at all**, so the two largest space consumers are invisible to the incremental path and require independent polling.

`FSEventsGetLastEventIdForDeviceBeforeTime()` answers "what changed since yesterday" directly. Apple hands us the differentiating query.

### 7.5 Timeline

The index records a daily rollup — per-category totals, per-top-level-directory totals, volume free space, snapshot inventory, purgeable estimate. Retention is 90 days by default, and the whole thing is a few megabytes.

This powers the questions nobody else can answer without preparation: what grew since yesterday, what grew this week, what changed between two arbitrary dates, and — the attribution feature — *why*. Correlating a size delta against FSEvents causality to produce "Xcode created 14 GB of DerivedData across three branches on Tuesday" is the hardest and most valuable thing in the roadmap.

## 8. The consumer catalogue

Detection rules ship as versioned, human-readable recipe files in the repository. Each declares its paths, detection method, safety class, regeneration cost and the command or API used to reclaim.

### 8.1 Safe — regenerates automatically, cost is time only

| Consumer | Path | Typical | Regeneration cost |
|---|---|---|---|
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | 10–100 GB | One full rebuild |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` | 5–40 GB | Reconnect device |
| SwiftUI Previews | `~/Library/Developer/Xcode/UserData/Previews` | 1–20 GB | Regenerates |
| Simulator dyld cache | `~/Library/Developer/CoreSimulator/Caches/dyld` | 1–10 GB | Regenerates |
| npm / yarn / pnpm | `~/.npm/_cacache`, `~/Library/Caches/Yarn`, `~/Library/pnpm/store` | 1–30 GB | Re-download |
| Homebrew | `$(brew --cache)` | 1–20 GB | `brew cleanup -s` |
| Cargo registry | `~/.cargo/registry` | 2–50 GB | Re-download |
| Go modules | `~/go/pkg/mod`, `~/Library/Caches/go-build` | 2–30 GB | `go clean -modcache` — note 0444 perms, plain `rm -rf` fails |
| Gradle / Maven / CocoaPods | `~/.gradle/caches`, `~/.m2/repository`, `~/Library/Caches/CocoaPods` | 1–30 GB | Re-download |
| pip / uv | `~/Library/Caches/pip`, `~/.cache/uv` | 0.5–10 GB | Re-download |
| Browser caches | Safari, Chrome, Firefox, Arc cache dirs **only** | 0.5–10 GB each | Re-download |
| Mail Downloads | `~/Library/Containers/com.apple.mail/.../Mail Downloads` | 0.5–20 GB | Re-download (IMAP) |
| Adobe media cache | `~/Library/Application Support/Adobe/Common/Media Cache Files` | up to 50 GB+ | Re-render previews |
| User logs | `~/Library/Logs` | 0.5–10 GB | None |
| Quick Look thumbnails | `/private/var/folders/*/C/com.apple.QuickLook.thumbnailcache` | 1–10 GB | Regenerates |

### 8.2 Risky — requires explicit per-item confirmation

Xcode Archives (5–50 GB) are needed to re-symbolicate crash reports from shipped builds and must never be auto-selected. Simulator devices (10–80 GB) hold app data and databases developers may have nowhere else; only `xcrun simctl delete unavailable` is offered as the safe subset. Scattered `node_modules` are safe with a lockfile and a network connection and hostile without either — abandoned ones are detected by parent-directory mtime. Trash across all volumes, including the frequently-forgotten per-volume `/Volumes/<X>/.Trashes/<uid>`, is a user decision by definition. Downloads is user data but the highest-yield source of large, old, forgotten files. Creative suite sound libraries under `/Library/Application Support/{GarageBand,Logic,Final Cut Pro}` run 5–70 GB and are commonly overlooked. Stale `~/Library/Mail/V8`/`V9` directories left behind after migration are usually safe but must be confirmed. Staged macOS installers — `Install macOS *.app` at 12–16 GB — are routinely forgotten.

### 8.3 Dangerous — reported and explained, never offered for deletion

APFS local snapshots are handled by a dedicated flow (§9), not the generic delete path. iOS device backups under `MobileSync/Backup` are frequently the only copy of a phone; FATHOM shows device name and date and refuses bulk deletion. Photos library internals must never be touched — with Optimize Storage the originals may be cloud-only and `resources/derivatives` looks deletable but is not. `~/Library/Containers/<app>/Data` **is a sandboxed app's entire home directory**; only `Data/Library/Caches` within it is safe, and any tool classifying the container as cache destroys user documents. Group Containers, likewise. `~/Library/Mail/V10` is live mail. Swap and `/private/var/vm` are SIP-protected and live-mapped — read-only reporting only. Stripping `.lproj` localizations from app bundles breaks their code signature and causes Gatekeeper to refuse launch; **this feature is not built, at all**.

### 8.4 The special cases

**Docker and VM images.** `~/Library/Containers/com.docker.docker/.../Docker.raw` never shrinks. The guest frees blocks but never plumbs discard through to the host sparse file, so the file is a ratchet. `docker system prune -a` frees space inside the VM and reclaims nothing on the host. Docker closed the compaction request as a duplicate of a roadmap item that remains unshipped after years. OrbStack, by contrast, shrinks automatically and documents that its `data.img` *appears* as 8 TB — a naive `st_size` scanner would report an 8 TB file, which is exactly why §7.3 matters.

The opportunity: *"Docker.raw is 180 GB on disk, 40 GB is live data, 140 GB is reclaimable"* with a guided export → reset → reimport flow. Twenty to two hundred gigabytes recoverable, Docker has punted for years, and no cleaner automates it safely. High value, and it should be built carefully behind an explicit confirmation because these files hold the only copy of volumes and unpushed images.

**AI model weights.** `~/.ollama/models`, `~/.cache/huggingface`, LM Studio. The fastest-growing new category — single models run 4–70 GB. DevCleaner already targets it. Safe to delete, expensive to re-download; FATHOM shows model name, size and last-used date.

**Spotlight.** `/System/Volumes/Data/.Spotlight-V100` with documented macOS 26 reports of runaway `mds_stores` consuming hundreds of gigabytes — one user reporting 383.94 GB of System Data against 90 GB of discoverable files. Warrants an explicit detector and a `mdutil` rebuild suggestion.

**Parallels, VMware, UTM.** 30–200 GB each, sparse, and subject to the same accounting problem as Docker.

## 9. Snapshots and purgeable

APFS local snapshots get a dedicated screen because they are the largest invisible consumer and the most misunderstood.

The screen lists every snapshot with its date, its own size, and — importantly — **the space that would actually be freed by deleting it**, which is usually far less than its nominal size because snapshots share blocks with each other. This makes oldest-first the only predictable deletion strategy, and the UI says so. `tmutil thinlocalsnapshots` is offered as the guided path, with `tmutil deletelocalsnapshots` for individual removal.

Two hard constraints. First, macOS 26 removed `diskutil`'s snapshot subcommands, so `tmutil` is the only supported CLI path — and it manages only Time Machine snapshots, meaning snapshots created by Carbon Copy Cloner or SuperDuper may be invisible to it. `fs_snapshot_list()` is the durable programmatic route and API stability across 14→26 is a live risk (spike S6). Second, deleting local snapshots destroys your only local undo if the Time Machine destination is offline, so the flow warns explicitly and checks destination reachability first.

Purgeable space gets an honest treatment. FATHOM reports `statfs` free space as the headline number — the conservative, true figure — and shows purgeable as a separate, explicitly labelled line with a plain-language explanation of why Finder disagrees. It also detects the cross-volume case, where purgeable space in a sibling volume cannot be purged to satisfy a write, because Finder gets this wrong and users get stuck.

On forcing a purge: there is no supported API or command. The only mechanisms are allocating a large file until macOS purges under pressure then deleting it, or rebooting. DaisyDisk's implementation takes two to ten minutes and always leaves 7–10 GB behind. FATHOM offers it, labelled as a workaround, with the caveats stated up front.

## 10. Reclaim safety

**Correcting the record before the pitch is built on it.** Research specifically looked for documented incidents of CleanMyMac destroying user data and found none. The MacRumors "legit or snake oil" thread contains no reports of actual data loss; the criticisms are preventative. The MacKeeper $2M class action was about *deceptive marketing*, not data destruction. The messaging must not imply otherwise — a reviewer who checks will find it false, and credibility is the entire product.

The substantive, defensible criticisms are opacity and over-cleaning: caches deleted so aggressively they must be rebuilt at a net performance loss, and "maintenance" like resetting LaunchServices or the Spotlight index performed without cause. That is what FATHOM competes against.

The safety design:

Everything goes to the Trash via `NSFileManager.trashItem`, never `unlink` — with the UI honestly noting that this defers actual space reclamation until the Trash is emptied. Every operation runs as a dry run by default, producing a reviewable and exportable manifest of exact paths and byte counts before anything moves. A hard deny-list refuses `/System`, `/private/var/vm`, `~/Library/Containers/*/Data` except `/Library/Caches` within it, Group Containers, `*.photoslibrary`, `MobileSync/Backup`, `~/Library/Mail/V*`, app bundle internals, anything SIP-protected and anything flagged `SF_DATALESS`. Before touching any VM image, database or cache belonging to a live application, the engine checks for open file handles and refuses. Every action is journaled to an append-only log recording paths, sizes, timestamps and the recipe version that selected them.

On the legal question: there is no barrier. Notarization is a malware scan, not a behavioural audit, and deleting user-owned files does not fail it. SIP makes it impossible to delete protected system files regardless of root — which is worth framing to users as a safety property rather than a limitation. The one genuine "you broke my Mac" vector is modifying other applications' bundles, and the mitigation is simply not shipping that feature.

---

# PART III — ENGINEERING

## 11. Architecture

```
FATHOM.app
├─ Contents/MacOS/FATHOM              SwiftUI + AppKit. Menu bar + main window.
├─ Contents/Library/LaunchDaemons/     Privileged helper (v2, fan control only)
└─ Contents/Resources/Recipes/         Versioned reclaim rules, human-readable

  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
  │  Presenter   │   │  Scheduler   │   │  Recipes     │
  │ SwiftUI      │◄──│ one coalesced│   │ versioned    │
  │ visibility-  │   │ timer, tiered│   │ auditable    │
  │ aware        │   │ leeway ≥10%  │   └──────┬───────┘
  └──────┬───────┘   └──────┬───────┘          │
         │                  │                  │
  ┌──────▼──────────────────▼──────────────────▼───────┐
  │                    Core                             │
  │  Sampler registry · Channel map · Metric store      │
  └──┬────────┬────────┬────────┬────────┬────────┬─────┘
     │        │        │        │        │        │
  ┌──▼──┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐ ┌──▼─────┐
  │Mach │ │IOKit │ │IORep │ │IOHID │ │ SMC  │ │ Disk   │
  │host_│ │IORegi│ │dlsym │ │temps │ │fans  │ │ engine │
  │stats│ │stry  │ │power │ │only  │ │PSTR  │ │ SQLite │
  └─────┘ └──────┘ └──────┘ └──────┘ └──────┘ │ FSEvent│
                                              └────────┘
```

**One bus per datum.** Temperatures come from IOHID only. Fans and total system power come from SMC only. Component power, frequency and memory bandwidth come from IOReport only. No redundancy — this is precisely where Stats' cost comes from.

**Nothing is hardcoded about the hardware.** IOReport channel names vary between generations; the `zeus-apple-silicon` project reports naming differences between M4 and M5, and the `socpowerbud` author — whose project was archived in January 2026, itself a signal about maintenance burden — warns that breakage concentrates on multi-cluster Max and Ultra parts. So: channels are enumerated at runtime and matched by pattern against a shipped, versioned, remotely-updatable channel-map file keyed on `hw.model`. SMC sensor keys live in the same kind of data file, because Stats' README warns that *"with each new SoC, Apple changes the sensor keys."* A `fathom dump-channels` diagnostic command lets users on unreleased silicon send back a channel dump — this is how the project stays current on hardware the maintainers do not own.

**Everything is Optional.** Every private-API reading is an `Optional`. The UI degrades to `—`. A missing `dlsym` symbol disables one module and never blocks launch.

**Delta timing must use measured intervals.** Stats issue #2777 reports power readings doubling at 2-second intervals — the classic symptom of dividing an energy delta by a hardcoded 1 second instead of elapsed time. Every sample is timestamped with `mach_absolute_time` and divided by the real interval. Unit-tested.

## 12. Performance budget

This is a hard product requirement, tested in CI, and published in the README as a competitive claim.

| State | CPU (M-series) | Energy Impact | Memory |
|---|---|---|---|
| Menu bar only, idle | < 0.3% | < 3 | < 60 MB |
| Popover open | < 1.5% | < 10 | < 90 MB |
| Main window, all modules | < 3% | < 20 | < 150 MB |
| Full disk scan (foreground) | unbounded, user-initiated | — | < 300 MB |
| Background index maintenance | < 0.5% | < 5 | < 100 MB |
| Display asleep / system idle | ~0% | ~0 | — |
| **Window visible, ambient motion running** | **< 0.6%** | **< 4** | — |
| **Window unfocused or on battery** | **~0% from decoration** | **~0** | — |

The mechanisms that make this achievable:

**Visibility gating** is the largest lever by a wide margin. The menu bar widget needs one or two values every 2–5 seconds. The full sensor set is sampled *only* while a popover or window is open. Everything suspends on `NSWorkspace.didSleepNotification` and when the display is off.

**Tiered sampling by volatility.** Temperatures, fans and power at 2 s. Voltages and currents at 10 s. Static values — fan minimum and maximum, sensor presence — read once at launch. Unknown SMC keys are probed once at first launch, the valid set is cached, and invalid keys are *never re-probed*. This alone accounts for most of Stats' measured overhead.

**A single coalesced timer** for the whole application with leeway of at least 10% of the interval, so all modules sample on the same tick and the SoC wakes once rather than N times.

**IOReport subscribed once at launch** to a narrow channel set. Enumeration is the expensive operation; sampling an established subscription is cheap. This is why IOReport-based tools cost less than SMC-based ones.

**Bluetooth never active-scans.** Battery levels are read from cached IORegistry properties and the Bluetooth preferences domain at 60-second intervals, refreshed on connect/disconnect notifications. `system_profiler` is never spawned on a timer.

**Adaptive backoff.** A value that has not changed across N samples gets a longer interval.

**Battery awareness.** All intervals halve on battery, and further under Low Power Mode.

**Decoration is a budget line, not a free gift.** The design system runs film grain, two drifting caustic pools and a per-object breathing loop. A full-window overlay-blended layer plus animating gradients means the window never becomes static, so the compositor never idles. The app publishes its own CPU cost in the sidebar footer as a competitive claim, which makes uncounted decoration a claim the product inflates itself.

Grain ships as a static tiled texture. Caustics and the breathing loop run **only** when the window is key, the machine is on mains power, and the pointer has moved in the last 10 seconds. Frame-callback count per minute joins the CI gates in §17.1.

An XPC helper is explicitly *not* the answer here. Moving cost to another process relocates it in Activity Monitor without reducing it, which is cosmetic at best and arguably dishonest. The wins are sampling strategy, IOReport instead of SMC, and visibility gating.

### 12.1 The Correlator — added in v2.0

The architecture above has samplers feeding a Core that feeds a Presenter. Every value is a point in time. That shape cannot express the two features this product is actually for.

The SSD endurance forecast joins three streams over time: memory pressure and swap from Mach, data-units-written from NVMe SMART, and size deltas from the disk engine. Attribution joins two: FSEvents directory changes and process write activity. Those are the same operation with different inputs — timestamped sample streams in, derived facts out.

The **Correlator** is a layer between Core and the Presenter that owns it. It has one job: consume timestamped series, emit derived facts with a confidence value, and own the downsampling policy so nobody else has to think about retention.

```
                         ┌──────────────────────────────────┐
                         │           Presenter               │
                         │  SwiftUI · visibility-aware       │
                         │  ⌘K palette · digest · menu bar   │
                         └───────────────┬──────────────────┘
                                         │  derived facts
                         ┌───────────────▼──────────────────┐
                         │           CORRELATOR              │
                         │  · swap ↔ writes ↔ endurance      │
                         │  · fsevents ↔ process ↔ deltas    │
                         │  · downsampling + confidence      │
                         └───┬───────────┬──────────────┬───┘
                             │           │              │
  ┌──────────┐  ┌────────────▼──┐  ┌─────▼──────┐  ┌───▼──────────┐
  │Scheduler │─▶│     Core      │  │ Disk engine│  │ Recipe       │
  │1 timer   │  │ registry      │  │ traversal  │  │ runtime      │
  │tiered    │  │ channel map   │  │ families   │  │ + validator  │
  │leeway10% │  │ metric store  │  │ FSEvents   │  │              │
  └──────────┘  └───┬───┬───┬───┘  │ SQLite     │  └───┬──────────┘
                    │   │   │      └─────┬──────┘      │
              ┌─────▼┐ ┌▼──┐ ┌▼────┐     │        ┌────▼─────┐
              │ Mach │ │IO │ │IOHID│     │        │ Recipes  │
              │ host_│ │Rep│ │SMC  │     │        │ signed   │
              │ stats│ │ort│ │NVMe │     │        │ data     │
              └──────┘ └───┘ └─────┘     │        └──────────┘
                                    ┌────▼─────┐
                                    │ SQLite   │
                                    │ index +  │
                                    │ timeseries│
                                    └──────────┘
```

**Series retention.** Full resolution 7 days, hourly 90 days, daily forever. Daily rows for a decade cost a rounding error, and the endurance model needs nothing finer beyond the first week.

**Clock discipline.** `mach_absolute_time` does not advance during sleep; wall clock does. Every series row carries both stamps. Sleep gaps are recorded as gaps and never interpolated, because an interpolated write rate across an overnight sleep looks exactly like a hardware fault.

**Confidence is a first-class output.** A forecast built on 90 minutes of history is not the same claim as one built on 90 days, and the UI must be able to tell them apart. A derived fact below the confidence floor is suppressed, not softened.

### 12.2 Journal isolation

The reclaim journal does **not** live in the main SQLite database. It is a separate append-only file, fsynced per entry. Every other piece of persisted state can be regenerated by rescanning; the journal cannot. It is also the only artefact that makes "zero data loss incidents" (§17) an enforceable claim rather than an aspiration.

**Ordering rule:** the journal entry is written and fsynced *before* the trash operation executes. If the journal cannot be written, the deletion does not happen.

### 12.3 Memory: intern the paths

The family-accounting map must hold every inode seen so far, because a clone family is only complete when the scan is. Storing a full path string per node on a 1.8M-file tree runs to hundreds of megabytes on its own and blows the 300 MB scan budget in §12.

Path components are interned into a tree; each node stores a component id and a parent pointer. This is the difference between roughly 300 MB and roughly 1 GB resident, and it is the single decision that determines whether the stated budget is achievable.

### 12.4 Signed data files

Channel maps and reclaim recipes are data files that tell an application holding Full Disk Access which hardware registers to probe and which files to delete. Remote update over HTTPS alone is not sufficient: whoever controls that endpoint chooses what gets deleted on other people's Macs.

Both are fetched over HTTPS and applied **only** if they carry a valid Ed25519 signature from a key embedded in the app at build time. Unsigned or invalidly signed payloads are refused and logged, never partially applied. The signing step lives in the release workflow; the private key never leaves the maintainer's control.

This preserves the same-day support loop for new silicon and new developer tooling, which is one of the better ideas in this document, without turning it into a supply chain hole.

## 13. Permissions, distribution, and macOS 26

### 13.1 The permission ladder

FATHOM must deliver real value at every rung, because demanding everything at first launch is the single largest install-abandonment risk.

**No permission** gets you the entire monitoring suite plus disk scanning of `~/Library/Caches`, `~/Library/Containers`, `~/Library/Developer`, `~/Library/Application Support`, `/Applications` and `/usr/local` — which, for the primary developer audience, is where the gigabytes actually are.

**Per-folder consent**, prompted naturally on first access, adds Desktop, Documents, Downloads and external volumes.

**Full Disk Access**, requested contextually and never at launch, adds Mail, Messages, Safari data, iOS backups and Time Machine.

FDA has a severe UX problem that must be designed around rather than wished away. It cannot be requested programmatically — there is no API and no prompt, so the user must be walked to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` manually. Worse, *"errors caused by FDA are indistinguishable from regular file permission errors"* — you get `EPERM` with no signal that FDA is the fix. The mitigation is a canary probe: attempt to read a known-protected path such as `~/Library/Application Support/com.apple.TCC/TCC.db` at launch; success means FDA is granted. This lets FATHOM distinguish the two error classes and upsell contextually: *"12 GB in Mail isn't visible to me. Grant access?"*

### 13.2 Why not the App Store

Apple DTS, on temperature and fan access: *"There's no supported API to get CPU temperatures and fan speeds on the Mac. Specifically, the `AppleSMC` service used by that code is not considered API, meaning that the question of how you access it from a sandboxed app is irrelevant."* The `temporary-exception.iokit-user-client-class` entitlement is rejected at review.

For disk scanning, the sandbox grants no whole-volume enumeration entitlement, and FDA and the sandbox are orthogonal — even with FDA granted, the sandbox still blocks you. DaisyDisk ships its App Store build with purgeable reclamation and snapshot deletion *disabled*, pointing users to Terminal instead. These vendors have already fought this and lost.

FATHOM ships Developer ID, notarized, with Hardened Runtime, distributed directly and via a Homebrew cask. No App Store SKU.

### 13.3 macOS 26 menu bar allow-list

This is the largest platform change affecting the product and it needs explicit design.

Tahoe added System Settings → Menu Bar → "Allow in the Menu Bar," letting users toggle any `NSStatusItem`. There is **no API to read or set that state** — Apple DTS, asked directly whether the state can be determined: *"No."* `NSStatusItem.isVisible` is actively misleading here: it stays `true` even when the user has disabled the item, because Control Center hosts a proxy window positioned offscreen at roughly `(0, -22, w, 22)`. The old detection heuristics all fail. Bugs are filed as FB20384263 and FB18341478.

Two consequences shape the implementation. First, apps have failed to appear in the allow-list *at all* when macOS cannot map the process back to a bundle identifier — specifically when a bare helper executable creates the status item, or when a framework bypasses `NSApplicationMain()`. So FATHOM creates its status item from a real `.app` bundle going through `NSApplicationMain()`; any separate menu bar process is a nested `.app` in `Contents/Resources`, never a bare executable. Second, because the blocked state cannot be detected, onboarding must handle it proactively with an explicit step and a deep link into System Settings. Stats, BetterDisplay and CodexBar have all been bitten by this in public.

Also in 26: the menu bar is translucent by default under Liquid Glass. Menu bar glyphs must be template images with correct alpha, legible against arbitrary wallpaper. Custom-drawn colour graphs in the menu bar — which Stats does — look wrong on 26. The widget rendering is designed around vibrancy from the start.

### 13.4 Login item

`SMAppService` agent, not a legacy login item, per DTS guidance. Unlike the menu bar setting, `SMAppService.status` *is* readable and stays in sync with the UI, so onboarding can verify it.

### 13.5 Privileged helper (v2)

Needed only for SMC writes, meaning only for fan control. Nothing else in this product requires root — and that is worth stating loudly, because it is a real differentiator: every paid competitor installs a root daemon.

When it does arrive it uses `SMAppService.daemon(plistName:)`, not `SMJobBless`. Stats and TG Pro both still use `SMJobBless` and both are legacy patterns; `SMAppService` keeps the daemon inside the app bundle so updates ship with the app rather than needing a re-bless. Caller validation uses `SecCodeCopyGuestWithAttributes` plus `SecCodeCheckValidity` against a requirement string pinning Team ID *and* a minimum version — a root helper with a weak XPC check is a local privilege-escalation vector, and for an open-source project the helper's source should be prominently auditable.

---

## 14. Roadmap

Six phases. Phases 0–3 are the shippable v1.0.

**Phase 0 — Spikes (2 weeks).** Six technical unknowns, resolved before any production code (§16). Deliverable: a spike report that either confirms the architecture or amends this PRD.

**Phase 1 — Core monitor (6 weeks).** Sampler registry, coalesced scheduler, runtime channel map, and the CPU, GPU, memory, disk-throughput and network modules on public APIs. Menu bar widget and popover. macOS 26 onboarding flow. **Exit criterion: the idle performance budget is met and measured in CI.**

**Phase 2 — Sensors and power (4 weeks).** IOHID temperatures, SMC fans and `PSTR`, IOReport power, frequency and memory bandwidth. Battery. Per-SoC channel map data files and the `dump-channels` diagnostic. **Exit criterion: full-window Energy Impact under 20, and under 3 with the window closed — the direct, measurable claim against Stats.**

**Phase 3 — Disk Intelligence (10 weeks).** The concurrent scanning engine with clone and hardlink family accounting, SQLite index, FSEvents incremental updates, the timeline, the consumer catalogue and recipe system, the snapshot and purgeable screens, and the reclaim engine with dry run, Trash and journal. **Exit criterion: two-number accounting verified against the golden fixtures in §20, and the partition property test green.**

**Phase 3.5 — Attribution (6 weeks).** Correlating size deltas with FSEvents causality to answer *why* space changed, not just what changed. Moved into v1 by the CEO review: shipping a first version that can only say *what* changed puts FATHOM on exactly the same screenshot as StorageRadar, and "why" is the half that makes the answer actionable. **Exit criterion: on a real developer machine, correctly attribute a DerivedData growth event to Xcode within one hour of it happening.**

**Phase 3.6 — The instrument earns its keep (9.5 weeks).** The six accepted expansions, sequenced so that each one is shippable on its own:

| | Weeks |
|---|---|
| SSD endurance forecast, including the day-one SMART backfill | 2 + 1.5 |
| Weekly digest and consequence alerts | 3 |
| ⌘K command palette | 2 |
| Contribution infrastructure: recipe schema, validator, `fathom recipe test`, CI fixtures | 3 |
| The seven details (§21) | 1.5 |

**→ v1.0 ships here. Roughly 39.5 weeks human, roughly 9-11 weeks with CC plus the two non-compressible spike weeks.**

**Phase 5 — Advanced reclaim (5 weeks).** Docker and VM image compaction with guided export-reset-import. Duplicate detection using clone-aware hashing, built on the same `PhysicalIdentity` primitive as family accounting. (The SSD wear intelligence originally scheduled here moved into v1 as the endurance forecast.)

**Phase 6 — Fan control (4 weeks, conditional).** Only if spike S5 confirms the `Ftst` sequence works reliably on current silicon. Behind a warning, via `SMAppService`.

### 14.1 Shipping something public before month nine

The review's one unresolved risk is not scope, it is that a 39-week solo project stalls around month four with nothing public to show for it. Cutting features is not the fix. Ordering is.

Three artefacts ship publicly before v1.0, each of which stands alone and each of which is a real thing people can use:

**`fathom explain <path>` as a standalone CLI, around week 8.** Falls out of the scanning engine, needs no UI, and does the whole two-number argument in a terminal. Ships to Homebrew on its own. Developers paste CLI output into threads in a way they never paste screenshots.

**The spike report, around week 2.** Seven measured answers about undocumented macOS behaviour, published as a document. Nobody has benchmarked `getattrlistbulk` against `enumeratorAtURL` against `fts` on Apple Silicon for this workload, and S6's answer about `fs_snapshot_list()` on macOS 26 is something a lot of people currently need and cannot find. This costs nothing extra because the work is already scheduled.

**The golden fixture suite, around week 20.** A public, reusable set of filesystem trees with known-correct clone, sparse and hardlink accounting. Any tool in the category can test against it. It is also the most credible possible statement that FATHOM's numbers are right.

None of these are marketing. Each is a real deliverable that happens to also be evidence the project is alive.

## 15. Open source strategy

MIT licence, matching Stats, chosen because it maximises adoption and permits commercial forks. The project is a personal-branding asset first, so reach beats control.

The repository leads with the things that make this project *different from* rather than *similar to* Stats: a published performance budget with CI enforcement, human-readable reclaim recipes anyone can audit or contribute to, the per-SoC channel maps as data files, and a documented list of what the app deliberately does *not* do and why — no fake ANE percentage, no FPS, no per-process network, no auto-delete.

The channel-map contribution loop is the thing that makes the project sustainable on hardware the maintainer does not own. `fathom dump-channels` produces a file, users open an issue, a map is merged, support ships without an app update. `socpowerbud` did exactly this with `iorepdump` and it is why that project supported hardware its author never touched.

Launch sequencing runs Show HN and r/macapps first, then Homebrew cask, then the Apple developer community — where the Xcode and simulator reclaim numbers do the selling — and finally Product Hunt once the screenshots are strong.

## 16. Spikes — resolve before Phase 1

| # | Question | Why it matters | Method |
|---|---|---|---|
| **S1** | Fastest traversal for names + sizes, concurrent: `getattrlistbulk` vs `enumeratorAtURL` vs `fts` | Apple DTS says avoid `getattrlistbulk`; `dumac` measured 6.4× the other way. No published benchmark covers this exact workload. Highest-value cheap unknown | Benchmark all three on a real 500k-file tree on M-series |
| **S2** | Are NVMe SMART fields — data units written, available spare, percentage used — readable without root on Apple-fabric SSDs? | SSD wear intelligence is a headline feature. `smartctl` generally needs root. If root is required the feature moves behind the helper | Attempt `IONVMeController` admin passthrough unprivileged; compare against `smartctl` |
| **S3** | E-core vs P-core logical index ordering from `host_processor_info` | Conventional assumption is E-cores at low indices; unverified and chip-dependent. Wrong mapping means wrong labels on every chart | Derive from IORegistry device tree, cross-check against `powermetrics` on M4 Pro |
| **S4** | Does `/usr/share/pmenergy/Mac-*.plist` still exist on macOS 26 Apple Silicon, and what is its schema? | Needed to make Energy Impact match Activity Monitor. Fallback is a documented approximation | Inspect on-device across 14/15/26 |
| **S5** | Does the `Ftst = 1` → retry → `Ftst = 0` fan sequence work on M4? | Determines whether Phase 6 exists at all. TG Pro says newer models are hardware-gated | Test on M4 Pro with a root helper |
| **S6** | Is `fs_snapshot_list()` usable on macOS 26 after `diskutil`'s snapshot commands were removed? | Snapshots are the largest invisible consumer and `tmutil` only sees Time Machine's | Test against snapshots created by `tmutil` and by CCC |
| **S7** | *Product, not technical:* do users want an always-on storage observer? | Two competitors advertise "no background daemon" as a feature. If the market distrusts daemons, the timeline must be reframed as opt-in | 20 user conversations before Phase 3 |

### 16.1 Fallbacks — added in v2.0

A spike without a stated fallback is a schedule risk pretending to be a question. Each of these is decided now so that a failed spike costs a day of re-planning, not a month.

| Spike | If it fails |
|---|---|
| **S1** traversal speed | Ship the slowest correct option and publish the benchmark anyway. Scan duration is a comfort metric, not a correctness one. No feature depends on the answer. |
| **S2** unprivileged SMART | The endurance forecast moves behind the `SMAppService` helper and inherits Phase 6's consent flow. The **day-one backfill still works**, because total-written and power-on-hours are the only two fields it needs and they are the most likely to be readable. If neither is readable unprivileged, SSD Health degrades to a read-only screen and the forecast becomes an opt-in that asks for the helper with a clear explanation of why. |
| **S3** core ordering | Label clusters rather than cores. "Efficiency cluster" and "Performance cluster" are more honest than a wrong per-core map, and they match how DVFS actually works on this silicon. |
| **S4** pmenergy plist | Ship the documented approximation, state in the UI that it is an approximation, and say what it is derived from. This is the honest-numbers principle applied to our own limitation. |
| **S5** fan control | Phase 6 does not exist. Documented in the README under what FATHOM deliberately does not do, with the reason. |
| **S6** `fs_snapshot_list()` | Fall back to `tmutil listlocalsnapshots`, which sees only Time Machine's snapshots, and say so explicitly on the snapshots screen. A partial answer that names its own blind spot beats a confident wrong total. |
| **S7** users distrust daemons | The timeline, digest and attribution become an explicit opt-in during onboarding rather than a default, with the background cost stated in the toggle. The features do not change; the consent model does. |

## 17. Success metrics

Adoption targets are 1,000 GitHub stars at three months and 10,000 at twelve, benchmarked against Stats' 38.8k over several years, with 5,000 downloads in the first month.

The quality metrics matter more, because they are the product thesis. Measured Energy Impact must be under 3 idle and under 20 with the full window open — a direct, reproducible comparison against Stats. Crash-free sessions above 99.5%. Zero reported incidents of data loss from the reclaim engine, which is a hard gate on any release.

### 17.1 How the energy claim is actually tested — corrected in v2.0

Phase 2's original exit criterion said Energy Impact is "measured in CI." **It cannot be.** Energy Impact is a derived macOS figure that depends on the physical machine, its thermal state at that moment, and coefficients from a board-specific plist. A hosted runner cannot produce a stable number, and a self-hosted Mac running other jobs cannot either. As written, the project's headline claim was gated on an untestable assertion, which in practice means it would have been disabled within a month.

CI gates on deterministic proxies that *are* the mechanism behind the energy claim:

| CI gate | Budget, menu bar idle |
|---|---|
| Timer wake-ups per minute | ≤ 30 |
| SMC transactions per minute | ≤ 6 |
| Syscalls per sample tick | ≤ 12 |
| Live IOReport subscriptions | exactly 1 |

Those are countable, stable across machines, and a regression in any of them is the regression that would have shown up as energy. Real Energy Impact is then verified by hand on a real Mac once per release and published in the release notes with the machine and macOS build stated. The competitive claim survives intact, and it stops being a flaky gate that blocks every merge.

### 17.2 Invariants that must never be violated

Two assertions stay live in release builds, because both failures are silent and both destroy the product's central claim:

**No reclaim without a journal entry.** Count must be zero, always.
**No clone family credited more than once.** Count must be zero, always.

The differentiation metrics are the ones to watch for product-market fit: median gigabytes reclaimed per user, the proportion of users who open the timeline more than once — validating the always-on thesis — and the proportion who grant Full Disk Access, validating the contextual-upsell design.

## 18. Out of scope

Intel Mac support is excluded; the entire architecture assumes Apple Silicon, and Intel would mean a second sensor and power path for a shrinking installed base. iOS and iPadOS companions, cross-platform Windows or Linux versions, remote and fleet monitoring, malware scanning, an app uninstaller, and any form of "speed up your Mac" optimisation are all out — the last one especially, because it is the category's credibility problem and staying out of it is a positioning choice, not an omission.

### 18.1 Considered in review and deliberately rejected

| Considered | Why not |
|---|---|
| Forking Stats rather than rebuilding | Fastest route to parity, and it would have made the energy fix a measurable before-and-after on identical code. Rejected because FATHOM stops being FATHOM: the design system has nowhere to live, and forks of healthy 40k-star projects rarely win the credit the fork was for. |
| Disk-forensics-only v1 | Ships the unclaimed half in a quarter of the time. Rejected by the owner: the thing worth being known for is the all-in-one instrument, and a v1 that ships only a disk analyser *is* a disk analyser. |
| Open-core commercialisation | Free monitor, paid disk forensics at $19-25. Rejected: MIT throughout, reach beats revenue, and the market evidence caps this category around $1-5k/month anyway. |
| Not building it, buying StorageRadar | Solves the measured pain for $19.99 this afternoon. Rejected: it does not build the brand asset, and it does not produce the two-number accounting nobody else has. |
| Energy Impact as a CI gate | Not measurable in CI. Replaced with deterministic proxies plus manual per-release verification (§17.1). |
| Auto-delete on a schedule | Unchanged from v1.0. The anti-pattern the product is defined against. |

---

## 19. Safety model — new in v2.0

Accepting community-contributed recipes (§15) turns the reclaim catalogue from an internal resource into a security boundary. Strangers now author deletion rules that run inside a process holding Full Disk Access on other people's machines. This section is the answer to that, and it is a hard requirement rather than a preference.

### 19.1 Recipes are declarative, never executable

A recipe has no scripting, no regular expressions, and no arbitrary paths. The vocabulary is closed:

| Field | Constraint |
|---|---|
| `root` | Drawn from a closed allow-list of known locations. Not user-supplied. |
| `glob` | Simple syntax. No `..` segment permitted anywhere, before or after expansion. |
| `age`, `size`, `extension` | Scalar predicates only. |
| `max_matches` | **Mandatory.** A recipe that matches more than it declared refuses to run. |
| `regeneration_cost` | **Mandatory**, in human terms. "One Xcode rebuild, about 8 minutes." |
| `min_app_version` | Older builds skip recipes they cannot fully parse rather than partially applying them. |

Table-driven dispatch over that vocabulary, not a chain of conditionals, so the validator and the matcher share one definition of what a recipe can express.

### 19.2 Three properties, enforced twice

The validator is the CI gate that §15's contribution infrastructure pays for. Every submitted recipe must satisfy all three or the pull request cannot merge:

1. Every resolved path is contained within its declared root, **after symlink resolution**.
2. The match set against the synthetic fixtures stays under the declared `max_matches`.
3. `regeneration_cost` is present and non-empty.

Containment is then checked **again at runtime**, immediately before any deletion, because a recipe that was safe on the fixture is not automatically safe on this machine.

### 19.3 The four critical gaps found in review

**Dataless files.** `SF_DATALESS` marks an iCloud file whose contents have been evicted. Opening it silently downloads it. A scanner walking a full disk could pull down gigabytes, over a metered connection, to answer a question about free space. **Rule: check `st_flags` before any read, never open a dataless file, report logical size with an explicit "evicted" marker, and credit zero freeable bytes.**

**`SQLITE_FULL` while indexing.** The app writes an index about a full disk, onto that full disk. This is the primary use case, not an edge case. **Rule: reserve an index budget at first launch. On write failure, hold results in memory and offer either an alternate index location or a memory-only session. A completed scan is never lost to a failed write.**

**Stale reclaim targets.** Time-of-check to time-of-use. The dry run listed a path; by the time the user clicks, that path may be a different file. **Rule: record inode, size and mtime at dry-run time. Re-stat immediately before each trash operation. Abort that item with a per-item report if anything changed. Never delete by path alone.**

**Recipe path escape.** Covered by §19.1 and §19.2.

### 19.4 Diagnostics redact by default

`fathom export-diagnostics` bundles the journal, recent `os_log` archives, `fathom doctor` output and the active channel map. Filenames are hashed by default, with an explicit opt-in flag for full paths. The natural thing a person does when reporting a bug is paste their entire file inventory into a public issue, and the tool should not make that the path of least resistance.

---

## 20. Failure modes and how they are tested — new in v2.0

### 20.1 Failure modes registry

| # | Failure | Visible how | Response |
|---|---|---|---|
| F1 | Private symbol missing on this macOS | Module hidden, reason shown in About | Degrade one module, log once |
| F2 | IOReport channel absent on this SoC | `—` with a tooltip naming the channel | Per-channel degrade, `dump-channels` prompt |
| F3 | SMC key absent or timing out | `—`, or stale value dimmed | Blacklist for session, never re-probe |
| F4 | SMART needs root (S2 fails) | "SSD wear needs the helper" with the why | Forecast opt-in behind `SMAppService` |
| F5 | No Full Disk Access | Permission ladder screen | Contextual prompt at the moment of need |
| F6 | Entry deleted or symlink-cycled mid-scan | "3 items skipped", expandable list | Skip, count, report |
| F7 | Bad sector (`EIO`) | Warning banner naming the path | Skip, flag volume as suspect |
| F8 | Volume ejected mid-scan | "Volume ejected, partial result" | Keep partial, mark incomplete, never show as total |
| F9 | Dataless file encountered | "Evicted" marker, zero freeable | Never open. See §19.3 |
| F10 | Disk full while indexing | Choice of alternate location or memory-only | See §19.3 |
| F11 | Index corrupt | "Rebuilding, history preserved" | Quarantine, rebuild from rescan, journal untouched |
| F12 | Stale reclaim target | Per-item skip report | Re-stat and abort item. See §19.3 |
| F13 | Trash on a different volume (`XDEV`) | Explicit choice, never silent | Offer alternative or abort |
| F14 | Killed mid-reclaim | Recovery offer on next launch | Journal replay |
| F15 | Recipe over-matches | "Recipe X matched 400k files" | Refuse, report, revocable |
| F16 | FSEvents dropped events | Timeline shows "recomputing" | Queue full rescan of that subtree |
| F17 | Sleep gap in the series | Gap rendered as a gap | Never interpolate across sleep |
| F18 | Not enough history for a forecast | Suppressed, not softened | Confidence floor |
| F19 | Signature invalid on a fetched data file | Silent to the user, logged | Refuse entirely, never partially apply |
| F20 | macOS 26 hides the menu bar item | Onboarding flow (§13) | No detection API exists; guide the user |

### 20.2 The tests that decide whether this ships

**Golden filesystem fixtures**, committed to the repository, each with a known-correct answer: a clone family wholly inside the tree, a family with one member outside it, a sparse file, a hardlink pair, a dataless file, a symlink cycle, and a path at `PATH_MAX`. Assert exact byte counts. These fixtures are the product expressed as a test, and they ship publicly (§14.1).

**The partition property.** For any partition of any tree, the sum of "freed if deleted" across the parts is less than or equal to the whole. The engine must never over-credit. This single property catches the entire class of accounting bugs that would end the project's credibility.

**The 2am Friday test.** Every shipped recipe against every fixture. Assert no path outside a declared root was touched, and that the journal reconstructs every operation. Green means the reclaim engine ships.

**The hostile QA test.** A recipe whose glob is `**`, against a fixture containing a symlink to `/`, with the disk artificially at 100% and the journal file read-only. Correct behaviour is refusing to act and saying why.

**The chaos test.** `SIGKILL` mid-reclaim, relaunch, and the journal shows the partial state and offers recovery rather than claiming success.

**Flakiness watch.** No test asserts on wall-clock duration. FSEvents tests settle-and-poll rather than sleep. Snapshot tests do not depend on `tmutil` having run.

### 20.3 Operational tooling

`fathom doctor` prints, in one command: macOS build, `hw.model`, which private symbols resolved, which channel map matched and its version, which SMC keys probed valid, permission state, index size and schema version, journal entry count, and last scan duration. Most issues a stranger opens are answered by pasting that output. It costs a day and it is the highest-leverage thing a solo maintainer can build.

Four runbooks before launch: corrupt index, journal replay after a crash, a recipe that over-matched in the field including how to ship a revocation, and unsupported new silicon.

---

## 21. Accepted expansions — new in v2.0

Six expansions were accepted during the CEO review. Each is now scope.

### 21.1 The SSD endurance forecast

The reference machine reports memory pressure normal, swap 8.49 GB, 149.97 TB written, health 95%, and 1,925 power-on hours. Every tool on the Mac shows those as five unrelated facts on four screens. They are one fact: memory pressure drives swap, swap drives write amplification, write amplification consumes endurance, and the drive is soldered to the logic board.

FATHOM computes the date at the end of that chain, and names what is causing it. **This is the only claim in this document that no competitor can copy without building both halves of the product**, and it is the actual reason the monitor and the disk engine belong in one application.

**Day-one backfill.** SMART already stores total data units written and power-on hours. Their ratio is a real lifetime average write rate available in the first sixty seconds, so the forecast produces a genuine number at first launch rather than in the fourth week. It is marked as derived from lifetime totals, and it sharpens as observed history accumulates.

### 21.2 Full attribution, moved into v1

"DerivedData grew 340 GB" is a fact. "Xcode rebuilt across six branches on Tuesday and left 340 GB behind" is advice. StorageRadar already ships *what* changed. Nothing on the Mac ships *why*. Shipping a v1 without it would have put FATHOM's launch screenshots on exactly the same ground as a competitor that got there first.

### 21.3 Weekly digest and consequence alerts

One notification, Sunday: what changed, with evidence, and one recommended action. Plus a short fixed list of consequence alerts, **off by default and individually toggleable**: snapshots crossing a share of the disk, the endurance forecast moving by more than a year, a directory gaining over 20 GB in a day.

**The digest is allowed to not fire.** A quiet week produces silence, not a notification announcing that nothing happened. That one rule is the entire difference between this and engagement bait, and it is a hard requirement.

### 21.4 The ⌘K command palette

One field that searches the file index, jumps to any section, and runs queries in plain terms: "over 1 GB", "changed this week", "clones", "node_modules". Closes `F-012` from the design audit and the Trunk Test navigation gap with a single object. Queries are parameterised, never interpolated, since a palette string becomes a SQL predicate. FTS5 over path components, not a `LIKE` scan.

### 21.5 The seven details

The Finder discrepancy card ("Finder says 114.8 GB free. Actually free: 71.2 GB. 31 GB of the difference cannot be purged for a write on this volume") sits on the **scan completion screen**, not buried in a sub-tab. It is the moment someone learns their Mac has been lying to them, and it is the moment they tell someone else about FATHOM.

Then: regeneration cost as a number on every reclaim card; the `fathom explain <path>` CLI, which ships standalone at week 8; hold-⌥ to flip every number in the tree between size-on-disk and freed-if-deleted; scan progress that names findings rather than showing a percentage; unsafe shutdowns with a 30-day window; and a menu bar glyph that grows a second row under memory pressure.

### 21.6 Contribution infrastructure

Recipe schema, validator, `fathom recipe test`, and CI that runs every submitted recipe against the synthetic fixtures so a stranger's pull request can be merged safely. Alongside the existing `fathom dump-channels` loop for silicon support.

The real risk on a project this size is not that the code is wrong. It is that in month nine the maintainer gets busy and the recipes go stale, because the app has to know about Xcode 27, Docker's new cache path, and whatever model runtime lands next spring. No one person tracks all of that. This is the mechanism that lets people who use software the maintainer does not use keep the catalogue current.

### 21.7 Two naming corrections

**Deep Scan, Storage Overview and Explore are three sidebar entries for one job.** Collapse to two: **Scan** is the verb you run, **Storage** is the noun where the result lives, with the overview and the explorable tree as two views of one screen.

**`Reading<T>` replaces `Optional<T>`** for every sampled value, carrying `.value(T)` or `.unavailable(Reason)`, so the interface can say *why* it is showing a dash. Honest numbers applies to failures as well as to values.

### 21.8 Accessibility gap

A treemap is a picture of numbers and it is invisible to a screen reader. Every node carries a VoiceOver label with name, size on disk, and freeable size. This needs specifying now rather than being discovered at the end, because it applies to the one visualisation the entire product is built around.

---

## Appendix A — Sources

**macOS system telemetry:** [Apple DTS 72330 (IOKit sandbox exception)](https://developer.apple.com/forums/thread/72330) · [DTS 802656 (memory pressure)](https://developer.apple.com/forums/thread/802656) · [DTS 806293 (disk throughput)](https://developer.apple.com/forums/thread/806293) · [DTS 757294 (nettop / per-process network)](https://developer.apple.com/forums/thread/757294) · [DTS 726789 (battery health)](https://developer.apple.com/forums/thread/726789) · [DTS 801489 (menu bar allow-list)](https://developer.apple.com/forums/thread/801489) · [DTS 788101 (allow-list detection)](https://developer.apple.com/forums/thread/788101) · [DTS 794920 (MenuBarExtra bundle mapping)](https://developer.apple.com/forums/thread/794920) · [Apple Energy Efficiency Guide — Timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) · [WWDC25 — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/)

**Reference implementations:** [Stats](https://github.com/exelban/stats) · [Stats #2554 (energy)](https://github.com/exelban/stats/issues/2554) · [Stats #2777 (IOReport delta)](https://github.com/exelban/stats/issues/2777) · [Stats #2928 (fan control)](https://github.com/exelban/stats/issues/2928) · [Stats #3120 (Tahoe menu bar)](https://github.com/exelban/stats/issues/3120) · [macmon](https://github.com/vladkens/macmon) · [SiliconScope channel map](https://github.com/kennss/SiliconScope) · [socpowerbud](https://github.com/dehydratedpotato/socpowerbud) · [mactop](https://github.com/metaspartan/mactop) · [zeus-apple-silicon](https://github.com/ml-energy/zeus-apple-silicon) · [apple_sensors](https://github.com/fermion-star/apple_sensors) · [iSMC](https://github.com/dkorunic/iSMC) · [macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) · [HelperToolApp (SMAppService)](https://github.com/alienator88/HelperToolApp) · [Bresink on ANE](https://www.bresink.com/osx/0SystemMonitor/Docs-en/pgs/0095-ANEActivity.html)

**Storage and APFS:** [Eclectic Light — Finder available space](https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/) · [Eclectic Light — System Data](https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/) · [Eclectic Light — managing snapshots](https://eclecticlight.co/2022/02/10/managing-snapshots-how-to-stop-them-eating-free-space/) · [Eclectic Light — Sonoma iCloud Drive / dataless files](https://eclecticlight.co/2023/10/25/macos-sonoma-has-changed-icloud-drive-radically/) · [Apple FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) · [DTS 760256 (enumeration performance)](https://developer.apple.com/forums/thread/760256) · [DTS 796852 (Tahoe diskutil snapshots removed)](https://developer.apple.com/forums/thread/796852) · [dumac benchmark](https://healeycodes.com/maybe-the-fastest-disk-usage-program-on-macos) · [duh — clone-aware du](https://github.com/cheapsteak/duh) · [Michael Tsai — Tahoe free space](https://mjtsai.com/blog/2025/08/19/tahoe-free-space-problems/) · [docker/for-mac#7517](https://github.com/docker/for-mac/issues/7517) · [OrbStack FAQ](https://docs.orbstack.dev/faq) · [Fileside — Full Disk Access](https://www.fileside.app/blog/2024-05-31_full-disk-access/)

**Competitors:** [DaisyDisk — purgeable](https://daisydiskapp.com/guide/4/en/PurgeableSpace/) · [DaisyDisk — snapshots](https://daisydiskapp.com/guide/4/en/Snapshots/) · [StorageRadar](https://storageradar.app/) · [DevCleaner](https://devcleaner.app/) · [GrandPerspective](https://grandperspectiv.sourceforge.net/) · [Sweep](https://www.sweepformac.com/) · [bjango — iStat Menus App Store differences](https://bjango.com/help/istatmenus7/macappstore/) · [MacPulse FAQ](https://www.macpulse.app/faq.html) · [TG Pro FAQ](https://www.tunabellysoftware.com/support/faq/) · [MacRumors — CleanMyMac discussion](https://forums.macrumors.com/threads/is-cleanmymac-actually-legit-or-snake-oil.2476091/) · [AppleInsider — MacKeeper settlement](https://appleinsider.com/articles/15/08/10/mackeeper-to-pay-out-2m-in-proposed-class-action-settlement)


---

# 22. Amendment v3.0 — design locked, hardware verified

*30 July 2026. Recorded here so nobody re-litigates it mid-sprint.*

## 22.1 The design is locked

`fathom-app.html` is the normative visual spec for all twenty sections.
`FATHOM-DESIGN.md` v1.0 documents it. Changes go prototype first, then the
design doc, then Swift.

## 22.2 Reference hardware

Every figure in the prototype was read from a real machine, not invented.
Mac mini M4 Pro, macOS Tahoe 26.5.2, 8 performance + 4 efficiency cores, 16-core
GPU, 24 GB, volume EXHIBINAUT 494.38 GB APFS, drive APPLE SSD AP0512Z.
Full table in `FATHOM-DATA-SOURCES.md`, which is now the controlling document
for every number in the product. These readings are the test fixtures.

## 22.3 Three corrections to earlier drafts

**Core topology.** Drafts assumed 4 performance + 4 efficiency. M4 Pro is 8 + 4.
`hw.perflevel0` is the *performance* cluster; getting this backwards is the most
common bug in Mac monitors and it was in ours.

**Per-core temperature.** A draft claimed Apple silicon does not publish per-core
temperatures and that any tool showing them interpolates. That is false — the SMC
publishes efficiency core 1–2, performance core 1–8, GPU 1–8, average GPU,
hottest GPU and memory proximity 1–2 on this hardware. The claim is withdrawn.
Per-core *frequency* genuinely does not exist (§12 stands, DVFS is per-cluster);
temperature and frequency were conflated.

**Endurance.** A draft displayed "March 2030 ±14 months". That date was invented.
The real arithmetic: 149.97 TB written, 5% consumed, 1,925 power-on hours,
77.9 GB/h, straight-line 38,500 power-on hours. At this machine's rate of use
that is decades. Apple publishes no TBW rating for the AP0512Z, so no calendar
date is defensible. The screen now shows the arithmetic and the words *decades,
not years*.

That last one matters beyond the number. A product built to oppose invented
metrics invented one, in its own prototype, and it survived several reviews. The
three-state `Measurement<T>` type in `AGENTS.md` exists to make that failure
mode a compile error rather than a matter of vigilance.

## 22.4 Sections: 20, in three archetypes

Splitting CPU / GPU / Memory, adding Bluetooth, and dropping Battery on desktop
hardware. Archetype assignment is a product decision, not a layout one — a Scan
button on a screen with nothing to scan is a lie about the data.

**Poster → result (11).** Deep Scan, Storage, Timeline, Explore, Reclaim,
Endurance, Attribution, Applications, Cloud, Maintenance, SSD Health.

**Live monitor (6), no Scan button.** CPU, GPU, Memory, Sensors & Power,
Network, Bluetooth.

**Surface (2).** Menu Bar, Weekly digest.

Plus Home, which assembles from the rest.

## 22.5 Accepted additions

**GPU section.** Utilisation, render, tiler, ANE, frame rate, GPU power. The ANE
reads 0% almost always; we report it because the user paid for it.

**Bluetooth replaces Battery.** On a Mac mini there is no battery, and the screen
says so in those words rather than hiding or faking the section. Peripherals that
do not implement the battery service render *does not report*.

**Public IP with country flag in the sidebar**, alongside the app's own idle cost.
This is FATHOM's only outbound request: cached ≥ 15 minutes, disableable, no
identifier, flags bundled rather than fetched. It must appear in the privacy
sheet.

**Network honesty note.** The Network screen states that macOS cannot attribute
traffic to processes reliably and names Little Snitch as the correct tool.
Pointing at a competitor that is better at something is the strongest honesty
signal available, and it costs nothing.

**FileVault state** surfaces on Home and SSD Health. The reference machine has it
off, which is a real finding a storage tool is well placed to notice.

## 22.6 Responsive

Fluid via `clamp()` and `auto-fit`/`minmax()`. Structural breakpoints at 1080px
(sidebar collapses to a 64px icon rail) and 760px (heroes stack, tables tighten).
Verified no horizontal overflow at 1520, 1200, 1000, 820, 720. Minimum window
720 × 560.
