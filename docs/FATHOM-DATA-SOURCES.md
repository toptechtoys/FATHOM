# FATHOM — Data Sources

**Every number in the product, and the exact API it comes from.**
Version 1.0 · locked 30 July 2026 · reference machine EXHIBINAUT

This is the most important engineering document in the project. FATHOM's entire
position is that it does not invent numbers. That promise is only as good as this
table. If a value cannot be traced to a row here, it does not ship.

---

## The reference machine

Every figure in the prototype came from this machine, read with Stats
(github.com/exelban/stats) on 29 July 2026. Use it as the fixture for tests.

| Property | Value |
|---|---|
| Model | Mac mini (M4 Pro) |
| OS | macOS Tahoe 26.5.2 |
| SoC | Apple M4 Pro, 12 cores, 12 threads, 8 performance + 4 efficiency |
| GPU | Apple M4 Pro, 16 cores |
| Memory | 24 GB unified |
| Volume | EXHIBINAUT, 494.38 GB, APFS |
| Drive | APPLE SSD AP0512Z, `disk3s1s1`, Apple Fabric |
| Network | Ethernet `en0`, 100 Mbps |

---

## The app's own cost

Rule 8 makes idle cost a shipped number. FATHOM measures it rather than
printing the budget, because a figure the app asserts about itself and never
checks is the kind of claim this document exists to prevent.

| Value | API | Notes |
|---|---|---|
| Widget CPU | `proc_pid_rusage(RUSAGE_INFO_CURRENT)` user + system time | Delta over the widget's own 5 s loop, as a percentage of one core |
| Items measured with | `FathomBarConfiguration.enabledItemCount` | The 0.2% target is stated for four; a measurement carries the count it was taken with |
| Measured at | Wall clock at the sample | Older than 60 s reads as stale, not as current |

**Energy Impact is not published to us.** Activity Monitor's composite comes
from `powermetrics`, which requires root, and FATHOM does not ask for root to
report on itself. The 2.1 figure in `AGENTS.md` therefore stays a manual
release-gate reading taken from Activity Monitor on the reference machine, and
the app does not display it at all rather than displaying a number it cannot
take.

**A first sample is not a rate.** The widget publishes nothing until it has two
samples, because one reading is a lifetime total and the lifetime average is
dominated by whatever the process did at startup.

---

## The menu bar widget's own geometry

| Value | API | Reference machine |
|---|---|---|
| Status-item height | `NSStatusBar.system.thickness` | 22.0 pt |

**This row exists because the number was asserted before it was measured.** The
prototype drew `22 pt` and the Swift copy repeated it, and it happened to be
right — `NSStatusBar.system.thickness` returns exactly 22.0 on the development
host. Being right is not the same as being traceable: the value differs on
machines with a notch and Apple is free to change it, and a claim nobody reads
from the system is a claim that goes stale silently.

`NSStatusBar` is AppKit, and FathomKit is deliberately AppKit-free, so this one
is read in the app layer rather than the measurement layer.

---

## Machine identity

The section header names the machine the numbers came from, so the reader knows
what they are looking at without opening another screen.

| Value | API | Reference machine |
|---|---|---|
| Model identifier | `sysctlbyname("hw.model")` | `Mac16,11` |
| Physical memory | `sysctlbyname("hw.memsize")` | 24 GB |
| Days recorded | Earliest entry in the local history store | 142 |

**We show the model identifier, not the marketing name.** `hw.model` returns
`Mac16,11`; turning that into "Mac mini (M4 Pro)" needs a lookup table we would
have to maintain, that goes stale the week Apple ships a machine we have not
seen, and that is wrong rather than absent when it misses. `system_profiler`
publishes the marketing name but shelling out is forbidden in the shipping
build. Where a friendlier name is genuinely wanted, the table has to be added
here first with a stated update policy.

**Days recorded is a count of what was recorded, not of elapsed time.** A Mac
that was asleep for a week has fewer days than the calendar suggests, and the
Timeline draws those absences rather than smoothing them.

---

## Rule zero

Three states, and the UI must be able to render all three for every value.

**Known.** The value was read successfully. Show it.

**Not published.** The API exists but this hardware does not expose the value.
Show the row, greyed, labelled *not published*. Never interpolate a neighbour.

**Not attributable.** We measured an aggregate but cannot break it down honestly.
Show the remainder as its own line, named *unattributed*. Never distribute it
across the named rows to make the percentages sum to 100.

The Attribution screen's 4.5% unattributed row and the Bluetooth screen's
*does not report* keyboard exist specifically to prove this rule visually.

---

## Storage and filesystem

| Value | Source | Notes |
|---|---|---|
| Volume capacity, free | `URLResourceValues.volumeAvailableCapacityForImportantUsage` | This is the honest free number. Not `volumeAvailableCapacity`. |
| Finder's free number | `statfs(2)` `f_bavail × f_bsize` | Read it only to show the discrepancy. |
| Logical size | `NSURLFileSizeKey` | What Finder's Get Info shows. |
| Physical size on disk | `NSURLFileAllocatedSizeKey` | Differs from logical for sparse and compressed files. |
| File modification time | `stat(2).st_mtimespec` | Persisted for scan diffs and stale-target checks. |
| Filesystem allocation block size | `fstatfs(2).f_bsize` | Used to normalize `F_LOG2PHYS_EXT` logical spans to physical allocation ranges; the union must reconcile exactly to `st_blocks × 512`. |
| Total allocated incl. clones | `NSURLTotalFileAllocatedSizeKey` | |
| Clone identity / reference count | `getattrlist(2)` / `fgetattrlist(2)` with `ATTR_CMNEXT_CLONEID` (`0x100`) and `ATTR_CMNEXT_CLONE_REFCNT` | Identifies full-clone families and members outside the scanned tree. |
| Shared physical extents | `F_LOG2PHYS_EXT` via `fcntl(2)` | Detects shared ranges, including partially diverged clones. Deleting one file may free nothing. |
| Clone-family accounting | Derived from physical-extent overlap, `(st_dev, st_ino, st_nlink)`, and clone reference count | Shared blocks are credited once at the members' lowest common ancestor. A proven outside member makes the family zero-freeable. |
| Storage tree totals | Derived from `stat(2)` allocated bytes and clone-family lowest-common-ancestor credits | Family members are removed from additive totals and their physical union is credited exactly once. |
| Freed if deleted | Derived from physical-extent reference sets, complete-volume scope, read-only snapshot extent manifests, and open-file identities | A physical range is credited only when every live reference is in the deletion set and no mounted snapshot manifest still references it. |
| Open file identities | `proc_listallpids(3)`, `proc_pidinfo(PROC_PIDLISTFDS)`, and `proc_pidfdinfo(PROC_PIDFDVNODEPATHINFO)` | Private-but-shipped libproc interface. If any live process denies enumeration, the complete identity set is *not published*. |
| Sparse file real occupancy | `SEEK_HOLE` / `SEEK_DATA` via `lseek(2)` | This is how Docker's 62.4 GB resolves to 0 GB freeable. |
| Purgeable space | `APFSVolumeGetPurgeableSpace` (private) **or** difference of the two capacity keys | Prefer the public difference. Document which you used. |
| Local snapshots | `fs_snapshot_list(2)` | Programmatic and read-only, but Apple documents it as requiring superuser privileges plus an additional entitlement. If denied, render *not published*. `tmutil` is prototype-only because the shipping build does not shell out. |
| Snapshot physical references | Read-only `fs_snapshot_mount(2)`, then `FTS(3)` plus `F_LOG2PHYS_EXT` for each mounted snapshot | Manifests are published only when every listed snapshot mounts, traverses, maps, and unmounts successfully. Apple documents the mount call as entitlement-gated; denial renders *not published*. |
| Directory tree walk | `FTS(3)` (`fts_open`/`fts_read`) | Fastest correct walk. `NSDirectoryEnumerator` is 3–5× slower. |
| Filesystem events | `FSEvents` with `kFSEventStreamCreateFlagFileEvents` | Feeds Timeline and Attribution. |
| Directory growth consequence | Difference between matching directory `staged_node_totals.subtree_size` rows in two completed SQLite scans no more than 24 hours apart | Published only when both directory totals are complete; a missing prior scan renders *not published*. |
| Interrupted reclaim intents | Append-only reclaim journal: an `intent` row without a later matching `outcome` row | Read-only replay on launch; never assumes whether the Trash move completed. |

**The two-number rule.** Every row in Explore shows *on disk* and *freed if
deleted*. The second is computed from clone status, sparseness, and whether any
open file descriptor or snapshot still references the extents. This column is the
product's moat. It is also the hardest thing in the codebase. Budget for it.

---

## SSD health and endurance

Read via **NVMe SMART**, `IOKit` → `IONVMeSMARTUserClient` on Apple Fabric.
This requires an entitlement or falls back to `IOKit` registry properties.
Verify which on Tahoe before committing to the approach.

| Value | Reference reading | Key |
|---|---|---|
| Data units written | 149.97 TB | `data_units_written × 512000` |
| Data units read | 170.68 TB | `data_units_read × 512000` |
| Percentage used | 5% | `percentage_used` — health = 100 − this |
| Available spare | 100% | `available_spare` |
| Power on hours | 1,925 | `power_on_hours` |
| Power cycles | 520 | `power_cycles` |
| Unsafe shutdowns | 43 | `unsafe_shutdowns` |
| Media errors | 0 | `media_errors` |
| Critical warning | None | `critical_warning` bitfield |
| Temperature | 47.8 °C | `temperature`, kelvin, subtract 273.15 |

### The endurance calculation, and what we refuse to do

```
consumed        = percentage_used                    = 5%
rate            = data_written / power_on_hours      = 77.9 GB/h
linear_to_100   = power_on_hours / (consumed/100)    = 38,500 power-on hours
```

**We do not convert that to a calendar date.** Apple does not publish a TBW
rating for the AP0512Z. Wear is not linear near end of life. A date implies a
precision we do not have. Ship the hours and the phrase *decades, not years*
when `linear_to_100 / observed_hours_per_year > 15`.

An earlier draft of this product displayed "March 2030 ±14 months". That number
was invented. It is the exact failure mode FATHOM exists to oppose, and it got
into our own prototype, which is why this section is written this firmly.

---

## CPU

| Value | Source | Reference |
|---|---|---|
| Per-core load | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` | E1–E4, P1–P8 |
| Core topology | `sysctlbyname("hw.perflevel0.logicalcpu")` / `perflevel1` | 8P + 4E |
| Cluster frequency | `IOReport` subscription, `CPU Stats` group | P 3307 MHz, E 1441 MHz |
| Load average | `getloadavg(3)` | 4.22 / 3.14 / 3.66 |
| System / user / idle | Sum of per-processor `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` deltas | 9% / 26% / 65% |

`perflevel0` is the **performance** cluster on Apple silicon. Getting this
backwards is the single most common bug in Mac monitors, and the prototype had
it wrong until the reference machine corrected it.

---

## GPU and Neural Engine

| Value | Source | Reference |
|---|---|---|
| GPU utilisation | `IOAccelerator` → `PerformanceStatistics` → `Device Utilization %` | 24% |
| Renderer / tiler | Same dictionary, `Renderer Utilization %`, `Tiler Utilization %` | 24%, 11% |
| ANE utilisation | `IOReport`, `ANE` channel | 0% |
| Core count | `IORegistry` `gpu-core-count` | 16 |
| Display refresh callbacks | `CVDisplayLink` output callback delta while GPU screen is visible | 65 Hz |

ANE reads 0% on virtually every machine outside Core ML workloads. Report it,
do not dramatise it.

---

## Memory

| Value | Source | Reference |
|---|---|---|
| Active | `host_statistics64(HOST_VM_INFO64).active_count × page_size` | direct Mach VM category |
| Inactive | `host_statistics64(HOST_VM_INFO64).inactive_count × page_size` | direct Mach VM category |
| Wired | `host_statistics64(HOST_VM_INFO64).wire_count × page_size` | 3.39 GB |
| Compressed | `host_statistics64(HOST_VM_INFO64).compressor_page_count × page_size` | 2.45 GB |
| Free | `host_statistics64(HOST_VM_INFO64).free_count × page_size` | 6.94 GB |
| Speculative | `host_statistics64(HOST_VM_INFO64).speculative_count × page_size` | direct Mach VM category |
| Purgeable | `host_statistics64(HOST_VM_INFO64).purgeable_count × page_size` | direct Mach VM category |
| Pressure level | `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` | Normal |
| Swap used | `sysctlbyname("vm.swapusage")` | 8.49 GB |
| Total | `sysctlbyname("hw.memsize")` | 24 GB |

FATHOM does not label any sum of these public Mach counters as “App.” Activity
Monitor's app-memory accounting is not published as a stable API, so that
headline is not attributable and does not render.

**Pressure and swap must appear in the same viewport.** This adjacency is a
product requirement, not a layout preference. It is the visual argument for the
entire Endurance feature.

---

## Sensors and power

Read from the **SMC** (`AppleSMC` via `IOKit`). Enumerate keys, do not hardcode
a list — the set varies by model and by OS version.

Friendly IOReport channel labels come only from an Ed25519-verified map bundled
with the app. A missing model/build match renders *not published*. FATHOM does
not fetch map updates because public IP is the only outbound request permitted
by the product rules.

Confirmed present on M4 Pro: per-core CPU temperature (efficiency 1–2,
performance 1–8), GPU 1–8, average GPU, hottest GPU, memory proximity 1–2, NAND,
Airport, Fan #0, and power channels for CPU, GPU, ANE, RAM, PCI, plus average
system total.

> **Correction.** An earlier design draft claimed Apple silicon does not publish
> per-core temperatures and that any tool showing them is interpolating. That is
> false. Stats reads them directly from the SMC on this machine. The copy has
> been corrected. Do not reintroduce the claim.

---

## Permissions and background service

| Value | Source |
|---|---|
| Full Disk Access canary | `open(O_RDONLY | O_CLOEXEC)` on `~/Library/Application Support/com.apple.TCC/TCC.db`; contents are never read |
| Menu bar agent registration | `SMAppService.agent(plistName:).status` |
| macOS 26 “Allow in the Menu Bar” state | Not published — Apple provides no read or write API |
| Root volume encryption | `URLResourceValues.volumeIsEncrypted` |
| Bluetooth usage declaration | `Bundle.main` `NSBluetoothAlwaysUsageDescription` | Precondition for paired-device enumeration; absent means *not published*, never a crash |

An `EACCES` or `EPERM` result from the protected canary is a known negative.
A missing canary or another filesystem error is *not published*. The allow-list
state is never inferred from `NSStatusItem.isVisible` or window geometry.

Foundation publishes whether the volume is encrypted. It does not name the
policy that produced that state, so the UI does not relabel this Boolean as a
definitive FileVault policy status.

---

## Network

| Value | Source | Reference |
|---|---|---|
| Per-interface throughput | `sysctl` `NET_RT_IFLIST2`, delta `ifi_ibytes`/`ifi_obytes` | 10 / 4 KB/s |
| Lifetime totals | Same counters, cumulative | 3.14 TB down, 687.52 GB up |
| Interface, link speed | `SystemConfiguration` + `IORegistry` | en0, 100 Mbps |
| Local IP | `getifaddrs(3)`, active non-loopback IPv4/IPv6 addresses | 192.168.1.149 |
| DNS, router, MAC | `SCDynamicStore` | 192.168.1.1 |
| Wi-Fi SSID, RSSI | `CoreWLAN` associated interface; SSID read is user-triggered because macOS gates it behind Location Services | not captured on Ethernet reference |
| Latency, jitter | ICMP to the gateway, rolling window | 229 ms, 7 ms |
| Public IP + country | `GET https://cloudflare.com/cdn-cgi/trace`, fields `ip` and `loc`; one HTTPS request, redirect refused, persisted cache 6 h | 193.19.109.117, US |

**Public IP is the only outbound request FATHOM makes.** It must be listed in
the privacy sheet, be disableable, cache aggressively, and never carry an
identifier. The flag in the sidebar is rendered from the returned country code
against a bundled asset set — no flag CDN.

The endpoint and response fields are documented by Cloudflare. FATHOM uses an
ephemeral `URLSession`, sends no cookies, credentials or custom identifier, and
refuses redirects so a refresh cannot silently become a second outbound
request. Public-IP lookup is off until the user enables it in the privacy sheet.

**No per-process attribution.** `nettop` drifts and misses daemon traffic. The
Network screen says so and names Little Snitch as the correct tool. Do not
"improve" this into a guess.

---

## Bluetooth

`IOBluetooth` device enumeration; battery via `BatteryPercent` in the device
properties dictionary. Reference: mouse 98%, K68 keyboard reports nothing.

Peripherals that do not implement the battery service must render as *does not
report*. No estimation from connection age or any other proxy.

Paired-device enumeration issues a TCC access request, and macOS **terminates**
any process that makes that request without an `NSBluetoothAlwaysUsageDescription`
string in its bundle. `BluetoothReader` therefore confirms the declaration is
present before it asks; a host without the key renders *not published* naming the
missing key rather than crashing. The shipping declaration lives in `project.yml`
as `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`, and CI asserts it survives
into the built `FATHOM.app` Info.plist.

---

## Applications

| Value | Source |
|---|---|
| Bundle size | `FTS` walk of the `.app`, allocated size |
| Leftovers | Scan of `~/Library/{Application Support,Caches,Containers,Preferences,Logs,Saved Application State}` matched on bundle ID |
| Last opened | `NSURLContentAccessDateKey`, with the volume's `noatime` caveat |
| Version, updates | `Info.plist` + Sparkle feed where present |

FATHOM currently reads version metadata from `Info.plist`; it does not contact
Sparkle feeds because public IP is the product's only permitted outbound
request. Leftovers require an exact bundle identifier as the complete path
component (or exact filename stem for preferences), never a prefix.

Never delete a leftover on a bundle-ID prefix match alone. Require an exact
match or an explicit user confirmation showing the full path.

---

## iCloud

| Value | Source |
|---|---|
| Downloaded vs evicted | `NSURLUbiquitousItemDownloadingStatusKey` |
| Pinned | `NSURLUbiquitousItemIsExcludedFromSyncKey` and pin state |
| Evictable bytes | Sum of allocated size where status is `current` and not pinned |

Eviction uses `evictUbiquitousItem(at:)`. The word *delete* must never appear on
this screen.

---

## Menu bar widget

The widget's own cost is a shipped, measured number: **0.2% CPU, energy impact
2.1** with four items enabled. Re-measure it every release with Activity Monitor
and Instruments. If it regresses past 0.5% or energy 4.0, the release is blocked.

The default steady-state sampling plan is also test-capped at 34 high-level
reads per minute: 12 CPU, 12 network, 6 capacity and 4 temperature inventory
reads. This is a deterministic regression proxy, not a substitute for the
reference-machine CPU and Energy Impact measurements.

Sampling stops entirely when the menu bar is hidden — observe
`NSMenuBarOwningApplication` / occlusion state, do not poll blindly.

---

## Timeline and digest

| Value | Source | Retention |
|---|---|---|
| Volume free, on-disk, freeable and purgeable history | Completed whole-volume FATHOM scan; each encoded `Measurement` retains its original syscall/API `DataSource` | Full resolution 7 days, hourly 90 days, daily thereafter |
| Wall time | `Date` at completed scan | Stored on every row |
| Monotonic stamp | `mach_absolute_time()` at completed scan | Stored on every row; sleep gaps are not interpolated |
| Change between scans | Exact subtraction of two completed persisted FATHOM scan measurements | Requires two known values; otherwise not published |
| Per-process or app attribution | Not published until a complete FSEvents causal window exists | Unattributed remainder must remain its own row |
| Curated-path causal events | `FSEventStreamCreate`, file-event flags and durable event IDs | Opt-in; event paths are evidence, not process attribution |
| Weekly notification authorization and pending delivery | `UNUserNotificationCenter` authorization settings and pending request identifier | Requested only after an explicit user action |
| Unsafe shutdown change window | Exact subtraction of persisted NVMe SMART unsafe-shutdown counters | Requires a known observation at least 30 days old; counter resets are not published |

The weekly digest compares persisted completed scans only. With fewer than two
eligible samples, change is *not published*; it is never extrapolated from a
single observation.

The Sunday notification is a one-shot request derived from the latest eligible
pair of scans. It is not repeating, because repeating content could become stale.
A known zero-byte change schedules nothing; missing or unattributable evidence
schedules nothing.

---

## Command palette

| Query | Source |
|---|---|
| Path/component text | FTS5 over staged `component` and `path`, scoped to the selected completed scan |
| `over N KB/MB/GB/TB` | Parameter-bound comparison against indexed allocated subtree bytes |
| `clones` | Indexed nonzero APFS clone identity from `ATTR_CMNEXT_CLONEID` |
| `changed this week` | Exact allocated subtree difference between the latest and preceding staged scans, only when the preceding scan began within seven days |

Palette strings are always bound SQLite parameters. They are never interpolated
into SQL. Every file result renders both indexed on-disk and freeable values.

---

## Things we have decided not to measure

Recorded so nobody re-litigates them mid-sprint.

| Not measured | Why |
|---|---|
| Per-process network | macOS cannot attribute it honestly |
| Per-process disk I/O attribution beyond FSEvents | Same |
| A single "health score" | Unfalsifiable, and the thing we are positioned against |
| Battery health on desktop Macs | There is no battery |
| Predicted failure date | Wear is non-linear and TBW is unpublished |
| Registry / "junk" counts as a headline | Count without freeable bytes is theatre |
