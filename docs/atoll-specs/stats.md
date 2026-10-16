# Atoll spec: STATS (system performance tab: StatsManager sampling, SMC/IOReport sensors, NotchStatsView grid, mini graphs, detail popovers, settings)

Source: Atoll 2.3.3 source clone plus REA evidence from the installed binary (see ../atoll-behaviour-evidence.md). Values are quoted with file:line from the Atoll source. Reimplement behaviour, do not copy code (GPL-3).

## Summary

Atoll's Stats tab is a notch tab (label "Stats", SF Symbol "chart.xyaxis.line") that shows up to five metric cards (CPU, Memory, GPU, Network, Disk) laid out in a 1-row (1-3 cards) or 2-row (4 = 2+2, 5 = 3+2) grid inside the open notch; with 4+ cards the open notch grows by exactly 132pt (120 content + 12 spacing) on top of the 200pt base open height. Each card is a 8pt-padded rounded rect (radius 8, white 8% fill, 1pt white 18%/45% stroke) with icon+title header, an 18pt-high value line, and a 36pt-high graph: a single line+gradient-area sparkline for CPU/Memory/GPU, or a mirrored "dual quadrant" graph (download/read above the centre line, upload/write below) for Network/Disk. History is a fixed 30-sample sliding window initialised with zeros. Hovering scales a card to 1.02 and reveals "Click for details"; clicking opens an NSPopover-backed SwiftUI .popover (420x420 CPU, 400x380 Memory, 380x360 GPU, 360x320 Network/Disk) with scrollable 12pt-radius cards (rings, gauges, per-core bars, top-8 processes, interfaces, volumes, swap/pressure). Sampling is "smart": a repeating Timer at statsUpdateInterval (default 1s, clamped 1-60) starts 0.5s after the notch is open AND the Stats tab is current, stops 0.1s after switching away to another tab, and stops 3.0s after the notch closes when statsStopWhenNotchCloses (default true). Metrics come from public Mach/BSD/IOKit APIs (host_statistics, host_statistics64, host_processor_info, getloadavg, sysctlbyname, getifaddrs, IOAccelerator/IOStorage registry properties, FileManager volumes, /bin/ps, proc_pidinfo) plus two non-public paths confirmed in the shipped 2.3.3 binary: CPU temperature over the AppleSMC user client (IOServiceOpen + IOConnectCallStructMethod selector 2, undocumented protocol) and CPU frequency through the PRIVATE IOReport framework loaded at runtime via dlopen/dlsym (never linked; REA macho.json shows _dlopen/_dlsym and no IOReport import, while binary strings contain "/usr/lib/libIOReport.dylib" and every IOReport* symbol name). Paths below are relative to the Atoll clone root (…/scratchpad/atoll-clone/Atoll/).

## Stats tab entry, empty states and tab gating

### Behaviour

A "Stats" tab appears in the notch tab strip only when enableStatsFeature is true (DynamicIsland/components/Tabs/TabSelectionView.swift:81-82, TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats)). The tab is counted toward the minimum open-notch width (sizing/matters.swift:119-122; width 640 for <5 tabs, 690 for 5, 770 for 6+ at :138-142). In Minimalistic UI the coordinator forces currentView back to .home, so the tab is unreachable (DynamicIslandViewCoordinator.swift:109-112). If the feature is off the view shows a disabled placeholder; if on but no graph toggles are enabled it shows a "No Graphs Enabled" placeholder; otherwise the card grid.

### Layout

NotchStatsView.body (components/Notch/NotchStatsView.swift:314-366): VStack(spacing: 0) filling maxWidth/maxHeight .infinity. Disabled state (:316-334): VStack(spacing: 12) { Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 40)).foregroundColor(.secondary); Text("Stats Disabled").font(.headline).primary; Text("Enable stats monitoring in Settings to view system performance data.").font(.caption).secondary.multilineTextAlignment(.center).padding(.horizontal) }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(). No-graphs state (:335-354) identical but icon "chart.xyaxis.line", title "No Graphs Enabled", caption "Enable graph visibility in Settings → Stats to view performance data.". Grid state (:355-363): VStack(spacing: 8) { statsGridLayout }.padding(12). Settings tab icon for Stats is also "chart.xyaxis.line" tinted .teal (components/Settings/SettingsView.swift:127,153).

### Animations

.animation(.easeInOut(duration: 0.4), value: availableGraphs.count) on the grid container (NotchStatsView.swift:359) and again on the outer VStack (:375); .animation(.easeInOut(duration: 0.4), value: enableStatsFeature) (:374). Grid container transition: .asymmetric(insertion: .scale.combined(with: .opacity).animation(.easeInOut(duration: 0.4)), removal: same) (:360-363).

### State and timing

ContentView switches on coordinator.currentView and instantiates NotchStatsView() for .stats only while vm.notchState == .open (ContentView.swift:1286-1296). Tab order index for direction: [.home,.shelf,.timer,.stats,...] (DynamicIslandViewCoordinator.swift:102).

### Data sources and APIs

Defaults keys (public, Defaults package): enableStatsFeature, showCpuGraph/showMemoryGraph/showGpuGraph/showNetworkGraph/showDiskGraph read via @Default (NotchStatsView.swift:64-69). StatsManager.shared observed via @ObservedObject (:63). DynamicIslandViewModel.isStatsPopoverActive (models/DynamicIslandViewModel.swift:50) written from updateStatsPopoverState (:407-421).

### Settings

enableStatsFeature Bool default false (models/Constants.swift:1282). Toggling it off calls StatsManager.stopMonitoring() (SettingsView.swift:8023-8028). DynamicIslandApp observes enableStatsFeature and the five show*Graph keys with options: [] and calls debouncedUpdateWindowSize() (DynamicIslandApp.swift:839-860).

### Implementation notes

Notchy: add a `.stats` case to the tab model and gate it on a `stats.enabled` UserSettings key (default false). Render placeholders with the same three-element VStack. ~80 lines of view code.

### Key files

- `DynamicIsland/components/Notch/NotchStatsView.swift`
- `DynamicIsland/components/Tabs/TabSelectionView.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/sizing/matters.swift`

## Smart monitoring lifecycle (start/stop rules, timer, interval clamp)

### Behaviour

Sampling only runs while the user is looking at the Stats tab: it starts half a second after the notch is open with Stats selected, stops 100 ms after switching to another tab, and (by default) stops 3 s after the notch closes. Settings shows a "Monitoring Status" row with a green/red 8pt dot and "Active"/"Stopped" plus live CPU/Memory/GPU/Network/Disk strings while active (SettingsView.swift:8228-8270). History values persist across stop/start (they are not cleared on stop), but per-sample caches are.

### Layout

No UI of its own; see Settings feature for the status section.

### Animations

None.

### State and timing

updateMonitoringState(notchIsOpen:currentView:) (StatsManager.swift:514-548) is called from ContentView on vm.notchState change (ContentView.swift:764-772) and coordinator.currentView change (:831-838), passing currentView string "stats" or "other"; it early-returns unless notch state or view string changed (:518). shouldMonitorForStats = notchIsOpen && currentView == "stats" (:528). If true: cancel pending timers and schedule startMonitoring after 0.5 s (:532; the comment at :531 says 3.5 s but the code is 0.5). Else: open && other tab → scheduleDelayedStop(0.1) (tabSwitchStopDelay :467, :539); closed → if statsStopWhenNotchCloses scheduleDelayedStop(3.0) (notchCloseStopDelay :466, :541-543) else keep running; any other case → 0.1 s (:545). If the user turns statsStopWhenNotchCloses on while monitoring with the notch already closed, a 3 s stop is scheduled; turning it off cancels any pending stop (:493-504). startMonitoring (:551-577): guard !isMonitoring; re-baseline network and disk counters; previousTimestamp = now; isMonitoring = true; lastUpdated = now; networkTotals = .zero; diskTotals = .zero; scheduleMonitoringTimer(); then one immediate updateSystemStats() on MainActor. scheduleMonitoringTimer (:611-628): repeating Timer at the clamped interval invoking updateSystemStats on MainActor. Interval change while monitoring reschedules on main queue (:630-643). stopMonitoring (:579-609): invalidates all three timers; isMonitoring = false; clears cachedProcessStats, lastProcessStatsUpdate = .distantPast, isProcessRefreshInFlight = false, previousCPULoadInfo = nil, vm_deallocate previous per-core buffer, processorCount = 0, topCPUProcesses = [], cpuCoreUsage = [], networkInterfaces = [], diskDevices = [], per-interface counters/totals cleared, cpuTemperature = (celsius: nil), cpuFrequency = nil. History arrays are NOT cleared (clearHistory() at :1402-1410 exists but is never called by the lifecycle). deinit stops monitoring (:507-511).

### Data sources and APIs

Timer.scheduledTimer (Foundation, public) for the repeating sampler, delayed start, and delayed stop (managers/StatsManager.swift:532, :621, :657). Defaults.publisher(.statsUpdateInterval, options: []) and Defaults.publisher(.statsStopWhenNotchCloses, options: []) (StatsManager.swift:489-504). REA: dispatch.json lists Swift class _TtC5Atoll12StatsManager with 60 ivars / instance_size 280 and ivars _isMonitoring, _cpuUsage, cachedProcessStats, lastProcessStatsUpdate, confirming the manager ships as in source.

### Settings

statsUpdateInterval Double default 1.0 (Constants.swift:1292), clamped to [1.0, 60.0] by validatedUpdateInterval (StatsManager.swift:464-465, :645-647); the clamped value is written back to Defaults if it differs by >0.0001 (:617-619, :633-636). statsStopWhenNotchCloses Bool default true (Constants.swift:1291). autoStartStatsMonitoring Bool default true (Constants.swift:1290) is declared but never read anywhere.

### Implementation notes

Notchy (Swift 6): make `StatsMonitor` a @MainActor ObservableObject; replace Timers with a `Task` loop using `Task.sleep(for: .seconds(interval))` cancelled on stop; keep the three delays (0.5 start, 0.1 tab-switch stop, 3.0 close stop) as constants; drive it from NotchViewModel state transitions (expanded + stats tab). ~150 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/components/Settings/SettingsView.swift`

## Per-sample pipeline, history window and derived strings

### Behaviour

Every tick all metrics are refreshed together; graphs show the last 30 samples (at 1 s default = 30 s of history). Network/disk speeds are shown in MB/s derived from byte-counter deltas; cumulative session totals accumulate while monitoring.

### Layout

N/A

### Animations

None (SwiftUI Path redraw on @Published change; no explicit animation on graph data).

### State and timing

maxHistoryPoints = 30 (StatsManager.swift:416); the seven history arrays (cpu, memory, gpu, networkDownload, networkUpload, diskRead, diskWrite :405-411) are initialised with 30 zeros (:472-478) and updated by removeFirst-then-append when count >= 30 (:779-785). updateSystemStats (:665-777) order: CPU breakdown → memory snapshot → GPU snapshot → per-core usage → network counters (speed only if elapsed > 0.1 s and previous counters nonzero :686; negative deltas clamp to 0 :687-690) → disk counters (same rule :704-708) → add deltas to networkTotals/diskTotals in MB (:715-734) → publish cpuUsage, gpuUsage, memoryUsage, networkDownload/Upload, diskRead/Write (max(0, x)), lastUpdated = now, cpuBreakdown, memoryBreakdown, cpuLoadAverage, gpuBreakdown, gpuDevices (only if changed), cpuCoreUsage (only if changed), cpuUptime = ProcessInfo.systemUptime, cpuTemperature = sensor read, cpuFrequency (kept if read returns nil) (:736-759) → push 7 history values (:762-768) → store previous counters/timestamp → networkInterfaces = collectNetworkInterfaces(deltaTime:) → diskDevices = collectDiskDevices() → refreshProcessStatsIfNeeded(force: true) (:771-776). Display strings: cpuUsageString/memoryUsageString/gpuUsageString = String(format: "%.1f%%") (:1343-1353); networkDownloadString/UploadString = StatsFormatting.throughput (:1355-1361); diskReadString/WriteString = "%.1f MB/s" (:1363-1369). maxCpu/Memory/GpuUsage = history.max() (:1371-1381); avg* = mean of non-zero history values (:1383-1399). StatsFormatting (components/Stats/StatsFormatting.swift): bytes() ByteCountFormatter MB/GB .memory (:22-28); mbPerSecond() 1 fraction digit if >= 10 else 2, suffix " MB/s" (:30-37); throughput(): >= 1 MB/s → MB/s (1 digit if >= 10 else 2); else KB = x*1024, >= 1 → KB/s (0 digits if >= 10 else 1); else B = x*1_048_576, >= 1 → B/s 0 digits; else "0 B/s" (:39-67); percentage() "%.1f%%" (:69-71); gigabytes() (:73-78); abbreviatedDuration() DateComponentsFormatter day/hour/minute, max 2 units, .abbreviated, fallback "—" (:80-86).

### Data sources and APIs

All public: see per-metric features. Speed conversion divides bytes by elapsed seconds and by 1_048_576 (StatsManager.swift:692-693, :710-711).

### Settings

None beyond interval.

### Implementation notes

Model a `StatsSample` Sendable struct produced off-main, then applied on MainActor. Keep ring buffers of 30 Doubles. ~120 lines plus a `StatsFormatting` enum (~80 lines) reproducing the thresholds above.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/StatsFormatting.swift`

## CPU metrics: usage breakdown, per-core, load average, uptime

### Behaviour

CPU card value = active usage (user+system) with one decimal; CPU popover shows System/User/Idle/Active percentages, logical core count, uptime, 1/5/15-minute load averages, and a per-core bar grid.

### Layout

See CPU detail popover feature.

### Animations

None.

### State and timing

previousCPULoadInfo and previousCpuInfo reset on stop (:593-600) so the first tick after restart is an absolute (not delta) reading.

### Data sources and APIs

PUBLIC Mach: host_statistics(hostPort, HOST_CPU_LOAD_INFO) (StatsManager.swift:789-846); hostPort cached from mach_host_self() once (:420) with the comment about send-right leaks. user% = (userΔ+niceΔ)/totalΔ*100, system% = systemΔ/totalΔ*100, idle% = idleΔ/totalΔ*100, all clamped 0-100 (:810-824); first sample uses absolute tick totals (:829-838); on failure returns previous breakdown. CPULoadBreakdown (models/CPUMetrics.swift:21-40): zero = (user 0, system 0, idle 100); activeUsage = clamp(user+system) (:28-31); normalizedSegments divides by max(sum, 0.001) (:33-39). Load average: getloadavg(buffer, 3) (:848-858) → LoadAverage(oneMinute, fiveMinutes, fifteenMinutes) (CPUMetrics.swift:42-48). Per-core: host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) (:983-1028); per core usage = (user+system+nice)/(user+system+nice+idle) delta vs previous buffer, clamped 0-100 (:995-1019); previous buffer freed with vm_deallocate (:1020-1023). Uptime: ProcessInfo.processInfo.systemUptime (:755). REA macho.json imports confirm _host_statistics, _host_processor_info, _getloadavg, _vm_deallocate, _mach_host_self, _mach_port_deallocate, _host_info.

### Settings

showCpuGraph Bool default true (Constants.swift:1293).

### Implementation notes

All public API; port verbatim semantics with `withUnsafeMutablePointer`/`withMemoryRebound` under a nonisolated sampler. ~150 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/models/CPUMetrics.swift`

## CPU temperature via AppleSMC (undocumented IOKit user-client protocol)

### Behaviour

CPU popover's left gauge shows CPU temperature as a ring (0-110 °C or 0-230 °F scale) with a "%.0f°C"/"°F" label, or "—" when no sensor is readable. Unit follows the cpuTemperatureUnit setting.

### Layout

CPUTemperatureGauge → CircularGaugeView(title "Temperature", size 78, lineWidth 8, tint Color(red: 0.98, green: 0.53, blue: 0.18)) (components/Stats/CPUStatsSharedViews.swift:143, :108, :162-198).

### Animations

None.

### State and timing

Read synchronously on every tick on the main actor (StatsManager.swift:756). SMC.shared is a process-wide singleton opened once (SMC.swift:163).

### Data sources and APIs

PUBLIC IOKit calls with an UNDOCUMENTED protocol (treat as private): IOServiceMatching("AppleSMC") + IOServiceGetMatchingServices(kIOMasterPortDefault) + IOServiceOpen(device, mach_task_self_, 0, &conn) (utils/SMC.swift:171-190); reads use IOConnectCallStructMethod(conn, selector 2 /*kernelIndex*/, SMCKeyData_t in/out) (:533-538, :44) with data8 = 9 (readKeyInfo) then data8 = 5 (readBytes) (:489, :499, :43-51). Value decoding by 4-char type: ui8/ui16/ui32, sp1e/16384, sp3c/4096, sp5b/2048, sp5a/1024, sp669/512, sp78/256, sp87/128, sp96/64, spa5/32, spb4/16, spf0, flt, fpe2 (:219-269); all-zero payload returns nil except FS!/F0Md/F1Md (:215). CPUSensorCollector.readTemperature (utils/CPUSensorCollector.swift:56-74): first try primary keys ["TC0D","TC0E","TC0F","TC0P","TC0H"] (:235-237) and accept the first value < 110; else average all readable platform fallback keys < 110 (:61-73): M1 family ["Tp09","Tp0T","Tp01","Tp05","Tp0D","Tp0H","Tp0L","Tp0P","Tp0X","Tp0b"] (:242); M2 ["Tp1h","Tp1t","Tp1p","Tp1l","Tp01","Tp05","Tp09","Tp0D","Tp0X","Tp0b","Tp0f","Tp0j"] (:244); M3 ["Te05","Te0L","Te0P","Te0S","Tf04","Tf09","Tf0A","Tf0B","Tf0D","Tf0E","Tf44","Tf49","Tf4A","Tf4B","Tf4D","Tf4E"] (:246); M4 ["Te05","Te09","Te0H","Te0S","Tp01","Tp05","Tp09","Tp0D","Tp0V","Tp0Y","Tp0b","Tp0e"] (:248); M5 ["Tp00","Tp04","Tp08","Tp0C","Tp0G","Tp0K","Tp0O","Tp0R","Tp0U","Tp0X","Tp0a","Tp0d","Tp0g","Tp0j","Tp0m","Tp0p","Tp0u","Tp0y"] (:250); default/Intel ["TC0P","TC0E","TC0F","TC0H","TC0D"] (:252). Platform from sysctl machdep.cpu.brand_string substring match (utils/AppleHardwareInfo.swift:74-82, :91-125). REA: macho.json imports _IOServiceOpen, _IOServiceClose, _IOConnectCallStructMethod; dispatch.json has class _TtC5Atoll3SMC (1 ivar = io_connect_t); binary strings contain "AppleSMC", "machdep.cpu.brand_string" and the key literals TC0P, Te05, Te09, Te0H, Te0L, Te0P, Te0S, Tf04, Tf09, Tf0A, Tf0B, Tf0D, Tf0E, Tf44, Tf49, Tf4A, Tf4B, Tf4D, Tf4E, Tp01, Tp05, Tp09, Tp0D, Tp0H, Tp0L, Tp0P, Tp0T, Tp0V, Tp0X, Tp0Y, Tp0b, Tp0e, Tp0f, Tp0j, Tp1h, Tp1l, Tp1p, Tp1t. No TCC permission; works unsandboxed (Atoll has no app-sandbox entitlement: signature.json entitlements; hardened runtime with disable-library-validation).

### Settings

cpuTemperatureUnit: LockScreenWeatherTemperatureUnit (rawValues "Celsius"/"Fahrenheit"), default .matchingSystemPreference = UnitTemperature(forLocale: .current) == .fahrenheit ? .fahrenheit : .celsius (Constants.swift:1298; enums/generic.swift:251-279; symbol "°C"/"°F" :274-279). Picker shown only when showCpuGraph is on (SettingsView.swift:8188-8195).

### Implementation notes

Write an original minimal SMC reader (open AppleSMC, keyInfo+readBytes, decode sp78/flt/ui types). Keep the key lists as data. Because the protocol is undocumented, wrap in a Sendable actor and degrade to nil. ~250 lines.

### Key files

- `DynamicIsland/utils/SMC.swift`
- `DynamicIsland/utils/CPUSensorCollector.swift`
- `DynamicIsland/utils/AppleHardwareInfo.swift`

## CPU frequency via IOReport (PRIVATE framework, dlopen/dlsym)

### Behaviour

CPU popover's right gauge shows overall CPU clock in GHz ("%.1f" + "GHz") with subtitle "E x.x • P y.y" (E/P cluster averages), ring filled to overall/maxOverall; "—" when unavailable.

### Layout

CPUFrequencyGauge → CircularGaugeView(title "Frequency", size 78, lineWidth 8, tint = userColor Color(red: 0.27, green: 0.52, blue: 0.97)) (CPUStatsSharedViews.swift:155, :200-242; CPUStatsDetailView.swift:26).

### Animations

None.

### State and timing

First readFrequency() after start returns nil (needs a previous sample); StatsManager keeps the last non-nil cpuFrequency (StatsManager.swift:757-759) and resets it to nil on stop (:608).

### Data sources and APIs

PRIVATE: IOReport.framework resolved at runtime: dlopen("/System/Library/PrivateFrameworks/IOReport.framework/IOReport") then "/usr/lib/libIOReport.dylib" (utils/IOReportBridging.swift:24-36), dlsym for IOReportCopyChannelsInGroup, IOReportMergeChannels, IOReportCreateSubscription, IOReportCreateSamples, IOReportCreateSamplesDelta, IOReportChannelGetGroup/SubGroup/ChannelName/UnitLabel, IOReportStateGetCount/GetNameForIndex/GetResidency, IOReportSimpleGetIntegerValue (:46-122). Channels: group "CPU Stats", subgroups "CPU Complex Performance States" and "CPU Core Performance States", merged, then IOReportCreateSubscription (CPUSensorCollector.swift:151-175). Per tick: IOReportCreateSamples, delta vs previous sample via IOReportCreateSamplesDelta (:76-89); for each channel in "CPU Stats" whose name hasPrefix "ECPU"/"PCPU", frequency = Σ(residency_i / Σ non-idle residencies × freq_i) skipping states named "IDLE","DOWN","OFF" (:99-107, :217-233); E/P averages, overall = core-count-weighted mean, all /1000 → GHz (:109-147). Cluster core counts from IOKit registry: IOServiceMatching("AppleARMPE") → child named "cpus" → Data props "e-core-count"/"p-core-count" (AppleHardwareInfo.swift:127-155); available frequencies from IOServiceMatching("AppleARMIODevice") entry named "pmgr" props "voltage-states1-sram" (E) and "voltage-states5-sram" (P) (:157-183), decoded as 8-byte records whose first 4 LE bytes are Hz, divided by 1_000 on M4/M5 and 1_000_000 otherwise to give MHz (utils/IOKitHelpers.swift:45-63). Logical core count sysctl hw.logicalcpu (:84-89). REA: macho.json imports _dlopen/_dlsym/_dlclose/_dlerror, _IORegistryEntryGetChildIterator, _IORegistryEntryGetName; dylib.json lists no IOReport dependency (confirming runtime loading); strings in /Applications/Atoll.app/Contents/MacOS/Atoll contain "/usr/lib/libIOReport.dylib", "IOReportChannels", all 12 IOReport* function names, "CPU Complex Performance States", "CPU Core Performance States", "voltage-states1-sram", "voltage-states5-sram"; dispatch.json has _TtC5Atoll18CPUSensorCollector (4 ivars) and _TtC5Atoll17AppleHardwareInfo (5 ivars).

### Settings

None.

### Implementation notes

This is the only hard PRIVATE dependency. Options for Notchy: (a) replicate the dlopen/dlsym shim behind a feature flag and show "—" if any symbol is missing; (b) drop the frequency gauge. If replicating, isolate in a `nonisolated` final class with @unchecked Sendable; ~200 lines.

### Key files

- `DynamicIsland/utils/IOReportBridging.swift`
- `DynamicIsland/utils/CPUSensorCollector.swift`
- `DynamicIsland/utils/AppleHardwareInfo.swift`
- `DynamicIsland/utils/IOKitHelpers.swift`

## Memory metrics (usage %, breakdown, pressure, swap)

### Behaviour

Memory card value = used % (one decimal). Popover shows a 128pt ring (used vs free), Used/Free/Total bytes, App/Cached/Wired/Compressed breakdown with bytes · %, a memory-pressure capsule (Normal/Warning/Critical) and swap Used/Free/Total with a bar, or "Swap is disabled on this system."

### Layout

See Memory detail popover feature.

### Animations

None.

### State and timing

Sampled every tick; on failure returns previous values.

### Data sources and APIs

PUBLIC: host_statistics64(hostPort, HOST_VM_INFO64) (StatsManager.swift:860-942); pageSize = vm_kernel_page_size (:875); used = active+inactive+speculative+wired+compressed − (purgeable+external) (:895-897); cache = purgeable+external (:896); app = used − (wired+compressed) (:900-901); total = host_info(HOST_BASIC_INFO).max_mem cached once, fallback ProcessInfo.physicalMemory (:421-435); usage % = used/total*100 clamped (:926, :941). Pressure: sysctlbyname("kern.memorystatus_vm_pressure_level") → 2 = .warning, 4 = .critical, else .normal (:903-915). Swap: sysctlbyname("vm.swapusage") xsw_usage xsu_total/xsu_used/xsu_avail (:917-924). Models MemoryBreakdown/MemorySwap/MemoryPressure (:30-97). REA: macho.json imports _host_statistics64, _sysctlbyname, _vm_kernel_page_size; strings contain "kern.memorystatus_vm_pressure_level" and "vm.swapusage".

### Settings

showMemoryGraph Bool default true (Constants.swift:1294).

### Implementation notes

Public API; ~90 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/MemoryStatsDetailView.swift`

## GPU metrics (IOAccelerator PerformanceStatistics)

### Behaviour

GPU card value = average "Device Utilization %" across accelerators. Popover shows an engine-utilization trio (Render gauge, big usage ring, Tiler gauge), a Render/Compute/Video/Other breakdown, session average, last-update time, active GPU name/status/temperature/cores, and a per-device list.

### Layout

See GPU detail popover feature.

### Animations

None.

### State and timing

gpuDevices only republished when the array changes (Equatable) (:749-751). Per-process GPU ranking is just the CPU ranking (:1426-1430).

### Data sources and APIs

PUBLIC IOKit registry with undocumented property names: IOServiceMatching(kIOAcceleratorClassName = "IOAccelerator") + IORegistryEntryCreateCFProperties (StatsManager.swift:106-136). Per device (:138-169): IOClass → vendor by substring nvidia/amd/intel/agx|apple (:171-183); model from PerformanceStatistics["model"] else dict["model"] else "<Vendor> Graphics" else "GPU" (:185-198); id = "\(model)#\(index+1)"; utilization from ["Device Utilization %","GPU Activity(%)"], renderUtilization "Renderer Utilization %", tilerUtilization "Tiler Utilization %", temperature ["Temperature(C)","temperature"], fanSpeed "Fan Speed(%)", coreClock "Core Clock(MHz)", memoryClock "Memory Clock(MHz)", cores dict["gpu-core-count"] or ["Cores"]; isActive = AGCInfo.poweredOffByAGC == 0 (default true) (:249-260); percentages clamped 0-100. gpuUsage = mean of non-nil utilizations (:944-958). Breakdown (:960-981) is partly SYNTHETIC: from the first device with any nonzero utilization, total = utilization (or render+tiler), render = min(renderUtil, total), compute slot = min(tilerUtil, total−render), remaining = total−render−tiler, then compute = remaining*0.6, video = remaining*0.25, other = rest. REA: strings "IOAccelerator", "PerformanceStatistics", "Device Utilization %", "Renderer Utilization %", "Tiler Utilization %"; dispatch.json private class …GPUInfoCollector.

### Settings

showGpuGraph Bool default true (Constants.swift:1295).

### Implementation notes

Public API; keep the same keys. ~160 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/GPUStatsDetailView.swift`

## Network metrics (throughput, interfaces, session totals)

### Behaviour

Network card shows "↓<download>" in orange and "↑<upload>" in red separated by "•", with a mirrored graph. Popover shows Download/Upload current speed, average, peak, an interface list (Wi-Fi/Ethernet/USB/Virtual/Hotspot…) with IPv4/IPv6, Active badge, session ↓/↑ bytes, Down/Up speeds, and session totals.

### Layout

See Network detail popover feature.

### Animations

None.

### State and timing

Session totals reset to zero on each startMonitoring (:567); per-interface totals cleared on stop (:605-606).

### Data sources and APIs

PUBLIC BSD: getifaddrs/freeifaddrs; AF_LINK if_data.ifi_ibytes/ifi_obytes; inet_ntop for AF_INET/AF_INET6 (StatsManager.swift:1030-1104, :1157-1174). Headline counters (getNetworkStats :1254-1296) skip lo/gif/stf/bridge/utun/awdl and SUM ONLY interfaces whose name hasPrefix "en" or contains "Wi-Fi". Per-interface list (collectNetworkInterfaces) excludes prefixes lo, gif, stf, awdl, llw, utun, p2p (:1176-1187); isActive = IFF_UP && IFF_RUNNING (:1189-1193); displayName: en0 → "Wi-Fi", other en* → "Ethernet", bridge* → "Bridge", pd* → "USB", vmnet* → "Virtual", ap* → "Hotspot", awdl* → "AirDrop", else name.uppercased() (:1195-1215); type: en0 → .wifi, en* → .ethernet, bridge/vmnet → .ethernet, ap → .wifi, pdp_ip → .cellular, lo → .loopback, else .other (:1217-1237); sort by type order wifi 0, ethernet 1, cellular 2, other 3, loopback 4 then displayName (:1098-1103, :1239-1252); per-interface speed uses max(deltaTime, 0.001) (:1075). REA: macho.json imports _getifaddrs, _freeifaddrs, _inet_ntop.

### Settings

showNetworkGraph Bool default false (Constants.swift:1296).

### Implementation notes

Public API; ~200 lines including the name/type tables.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/NetworkStatsDetailView.swift`

## Disk metrics (I/O throughput via IOStorage, mounted volumes)

### Behaviour

Disk card shows "R <read>" in cyan and "W <write>" in yellow ("%.1f MB/s"), mirrored graph. Popover shows Read/Write current + peak, a Storage Devices list (name, path, System/External badge, used bar, Used/Free/Total) and session totals.

### Layout

See Disk detail popover feature.

### Animations

None.

### State and timing

Baseline counters captured in init and on startMonitoring; speed only when previous counters nonzero.

### Data sources and APIs

PUBLIC IOKit registry with undocumented keys: IOServiceMatching("IOStorage") → properties["Statistics"]["Bytes read from block device"] / ["Bytes written to block device"] summed over all services (StatsManager.swift:1298-1340). Volumes: FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey, .volumeIsRootFileSystemKey, .volumeIsRemovableKey], options: [.skipHiddenVolumes]) (:1106-1145); free = availableCapacity ?? importantUsage ?? opportunistic ?? 0; sorted root first, non-removable first, then name (:1146-1154). REA: strings "IOStorage", "Bytes read from block device", "Bytes written to block device".

### Settings

showDiskGraph Bool default false (Constants.swift:1297).

### Implementation notes

Public API; ~100 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/DiskStatsDetailView.swift`

## Top-process ranking (ps sampling)

### Behaviour

CPU/Memory/GPU popovers show up to 8 processes with app icon, name, resident memory and CPU % (CPU-sorted for CPU/GPU, memory-sorted for Memory); "No process data yet. Keep stats open for a moment." until first sample.

### Layout

CPUProcessList/CPUProcessRow (CPUStatsSharedViews.swift:483-562): VStack(spacing: 8); row HStack(spacing: 12): icon 24x24 clipped RoundedRectangle(6, .continuous) with 0.5pt white 8% stroke; VStack(spacing: 2) { name .system(size: 13, weight: .semibold) lineLimit 1; memory .caption2 .secondary }; Spacer; cpu .system(13, .semibold, .monospaced) in accent color; Divider().padding(.leading, 32) between rows; fallback icon ZStack(accent 15% + "app" symbol 12pt medium). Empty text .footnote .secondary.

### Animations

None.

### State and timing

maxProcessEntries = 20 (:459); processStatsUpdateInterval = 2.0 s (:458) for on-demand refreshes from getProcessesRankedBy* (:1413-1430), but updateSystemStats calls refreshProcessStatsIfNeeded(force: true) every tick (:776) guarded by isProcessRefreshInFlight; work runs in Task.detached and publishes topCPUProcesses on MainActor (:1440-1449). Detail views take prefix(8) (CPUStatsDetailView.swift:59,62; GPU/Memory processDisplayLimit = 8).

### Data sources and APIs

PUBLIC: Process() launching /bin/ps with arguments ["-Aceo", "pid,pcpu,comm", "-r"] (StatsManager.swift:1452-1507), parsed with Scanner (:1509-1528, accepts "," decimal); name/icon via NSRunningApplication(processIdentifier:) (:1530-1536); resident memory via proc_pidinfo(pid, PROC_PIDTASKINFO).pti_resident_size (libproc, :1538-1543). ProcessStats model (components/Stats/ProcessStats.swift:24-42) with memoryUsageString (ByteCountFormatter MB/GB .memory) and cpuUsageString "%.1f%%". REA: strings "-Aceo", "pid,pcpu,comm"; macho.json imports _proc_pidinfo and NSRunningApplication usage.

### Settings

None.

### Implementation notes

Public API; consider libproc proc_listpids + proc_pid_rusage instead of spawning ps. ~120 lines.

### Key files

- `DynamicIsland/managers/StatsManager.swift`
- `DynamicIsland/components/Stats/ProcessStats.swift`
- `DynamicIsland/components/Stats/CPUStatsSharedViews.swift`

## Stats card grid layout and 1-row vs 2-row notch sizing

### Behaviour

1-3 enabled graphs: one row of equal-width cards. 4: two rows of two. 5: a row of three above a row of two. With 4 or 5 graphs the open notch is 132pt taller (332pt instead of 200pt base). Toggling graphs in Settings resizes the window (debounced) and the grid animates.

### Layout

statsGridLayout (NotchStatsView.swift:153-208): graphCount <= 3 → LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: graphCount), spacing: 12). graphCount == 4 → VStack(spacing: statsGridSpacingHeight = 12) { LazyVGrid(2 cols, GridItem spacing 8, row spacing 12) [0,1]; LazyVGrid(2 cols, same) [2,3] } (:169-186). graphCount 5 → VStack(spacing: 12) { LazyVGrid(3 cols, spacing 8, row spacing 8) [0..2]; LazyVGrid(2 cols, spacing 8, row spacing 8) [3,4] } (:189-206). Container VStack(spacing: 8).padding(12) (:355-358). Graph order is always CPU, Memory, GPU, Network, Disk filtered by toggles (:83-150). Sizing constants: openNotchSize height 200 (sizing/matters.swift:69-75); statsSecondRowContentHeight = 120, statsGridSpacingHeight = 12 (:169-170); statsAdditionalRowHeight = 132 (ContentView.swift:305); statsRowCount: 0 graphs → 0, <= 3 → 1, else 2 (:2501-2505); notch size for .stats = base + (rows−1)*132 (:233-240). statsAdjustedNotchSize (matters.swift:287-317) adds (120+12)*clamp(secondRowProgress) only when enabled graph count >= 4 and the stats tab is active; used by DynamicIslandViewModel.calculateDynamicNotchSize (models/DynamicIslandViewModel.swift:421-441) and AppDelegate window sizing (+ shadow padding 18 standard) (DynamicIslandApp.swift:582-597; matters.swift:171,319-325). Width is unchanged by the stats tab (the Settings footer claiming horizontal expansion is inaccurate).

### Animations

Grid count change: .animation(.easeInOut(duration: 0.4), value: availableGraphs.count) (NotchStatsView.swift:359, :375); each card transition .scale.combined(with: .opacity) easeInOut 0.4 (:257-266). Notch size change driven by statsSecondRowExpansion: withAnimation(.easeInOut(duration: 0.3)) { notchSize = target } (DynamicIslandViewModel.swift:228-238). statsSecondRowExpansion is a @Published CGFloat that is always 1 (DynamicIslandViewCoordinator.swift:121) and is re-set to 1 on entering .stats (:253-258); no collapse/expand gesture exists in 2.3.3 (comment at NotchStatsView.swift:168 "without a collapsible expansion").

### State and timing

Window-size recomputation is debounced on each graph toggle (DynamicIslandApp.swift:839-860, debouncedUpdateWindowSize).

### Data sources and APIs

Defaults show*Graph keys; coordinator.currentView; ViewModel notchSize publisher. All public.

### Settings

showCpuGraph true, showMemoryGraph true, showGpuGraph true, showNetworkGraph false, showDiskGraph false (Constants.swift:1293-1297) → default is a single row of three cards and a 200pt-high notch.

### Implementation notes

In Notchy's NotchGeometryResolver add `statsExtraRowHeight = 132` applied when the stats tab is active and >= 4 graphs enabled; animate the panel frame with easeInOut 0.3. Grid: use LazyVGrid/VStack exactly as above. ~120 lines.

### Key files

- `DynamicIsland/components/Notch/NotchStatsView.swift`
- `DynamicIsland/sizing/matters.swift`
- `DynamicIsland/ContentView.swift`
- `DynamicIsland/models/DynamicIslandViewModel.swift`
- `DynamicIsland/DynamicIslandViewCoordinator.swift`
- `DynamicIsland/DynamicIslandApp.swift`

## UnifiedStatsCard, MiniGraph and DualQuadrantGraph rendering

### Behaviour

Each card: coloured SF Symbol + title on the left, a centred bold value (or ↓/↑ pair), and a 36pt graph. Hover: card scales to 102%, border brightens, and "Click for details" fades in under the graph. Single graphs auto-scale to the window max (not fixed 0-100); dual graphs share one max across both series.

### Layout

UnifiedStatsCard (NotchStatsView.swift:425-513): VStack(spacing: 3) { header HStack(spacing: 4) { Image(systemName: icon).foregroundStyle(color).font(.caption); Text(title).font(.caption).fontWeight(.medium).foregroundStyle(Color.white.opacity(0.8)); Spacer() }; values Group.frame(height: 18): single → Text(value).font(.caption).fontWeight(.bold).foregroundStyle(.white).frame(maxWidth: .infinity); dual → HStack(spacing: 6) { Text(positive).font(.caption).fontWeight(.semibold).foregroundColor(positiveColor); Text("•").font(.caption2).foregroundStyle(Color.white.opacity(0.45)); Text(negative) same in negativeColor }; graph Group.frame(height: 36); if rankingType != nil: Text("Click for details").font(.caption2).foregroundStyle(Color.white.opacity(0.75)).opacity(isHovered ? 1 : 0) }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(isHovered ? 0.45 : 0.18), lineWidth: 1))).scaleEffect(isHovered ? 1.02 : 1.0).frame(maxWidth: .infinity, maxHeight: .infinity).onHover. Card colours/icons (:86-147): CPU .blue "cpu"; Memory .green "memorychip"; GPU .purple "display"; Network positive .orange / negative .red, primary .orange, "network", values "↓"+download, "↑"+upload; Disk positive .cyan / negative .yellow, primary .cyan, "internaldrive", values "R "+read, "W "+write. The card is wrapped in Button(...).buttonStyle(PlainButtonStyle()) (:215-220). MiniGraph (:515-568): GeometryReader; maxValue = data.max() ?? 1; normalized = v/max when max > 0; stepX = width/(count−1); y = height*(1−v); stroke Path lineWidth 2 in color; fill Path closed to the bottom with LinearGradient([color.opacity(0.3), color.opacity(0.1)], .top → .bottom). DualQuadrantGraph (:572-687): maxValue = max(positive.max(), negative.max()); centerY = height/2; centre line Path stroked Color.secondary.opacity(0.3) lineWidth 1; positive series y = centerY − centerY*v stroked positiveColor lineWidth 2 with gradient fill [0.3, 0.1] .top → .center closed to centre; negative series y = centerY + centerY*v stroked negativeColor lineWidth 2 with gradient [0.3, 0.1] .bottom → .center.

### Animations

Hover: .animation(.easeInOut(duration: 0.2), value: isHovered) on both the hint opacity (:494) and the card scale/border (:507). Card insertion/removal: .scale + .opacity easeInOut 0.4 (:257-260, :263-266).

### State and timing

Graphs redraw whenever the history @Published arrays change (every tick).

### Data sources and APIs

SwiftUI Path/GeometryReader only (public).

### Settings

None.

### Implementation notes

Direct SwiftUI port using Path; consider Canvas for fewer layout passes. ~250 lines.

### Key files

- `DynamicIsland/components/Notch/NotchStatsView.swift`

## Detail popover container (RankedProcessPopover) and auto-close interplay

### Behaviour

Clicking a card opens a floating popover anchored to the card with a close (x) button at top-right; while any stats popover is open (or hovered) the notch will not auto-close; 0.1 s after the last popover closes, the notch closes if the pointer is not over it.

### Layout

RankedProcessPopover (components/Stats/RankedProcessPopover.swift:24-85): content .padding(0).frame(width: W).frame(minHeight: H) with (W,H) = cpu (420, 420), memory (400, 380), gpu (380, 360), network/disk (360, 320) (:31-42); .background(Color(NSColor.controlBackgroundColor)); .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)); .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 8); overlay topTrailing Button { Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.secondary).padding(10) } PlainButtonStyle (:52-60); full-size PopoverHoverSensor NSViewRepresentable with NSTrackingArea [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], allowsHitTesting(false) (:61-67, :87-131). Presented via SwiftUI .popover(isPresented:) on the card button (NotchStatsView.swift:221-256), default arrow edge.

### Animations

System NSPopover appearance; no custom animation.

### State and timing

Five @State showing*Popover + five isHovering*Popover flags (NotchStatsView.swift:70-79); updateStatsPopoverState sets vm.isStatsPopoverActive = any showing flag (:407-421), also on onDisappear (:239-255, :370-373). ContentView: isStatsPopoverActive is part of hasAnyActivePopovers() → shouldPreventAutoClose() (ContentView.swift:2461-2479); onChange(isStatsPopoverActive) → after 0.1 s close the notch if !popover && !isHovering && open && !shouldPreventAutoClose (:799-805).

### Data sources and APIs

SwiftUI .popover, AppKit NSTrackingArea (public).

### Settings

None.

### Implementation notes

Notchy already has preventsAutomaticClose states (NotchState.previewing etc.); add a `statsPopoverPresented` flag that maps to a close-suppressing state. ~100 lines.

### Key files

- `DynamicIsland/components/Stats/RankedProcessPopover.swift`
- `DynamicIsland/components/Notch/NotchStatsView.swift`
- `DynamicIsland/ContentView.swift`

## CPU detail popover (dashboard, gauges, ring, per-core grid)

### Behaviour

Scrollable cards: "CPU Overview" (temperature gauge, segmented usage donut, frequency gauge; Usage rows System/User/Idle/Active; System rows Logical cores, Uptime, Load 1m/5m/15m), "Top Processes" (8), "Per-Core Usage" (Core N label, % and a bar per logical core).

### Layout

CPUStatsDetailView (components/Stats/CPUStatsDetailView.swift:29-64): ScrollView { VStack(spacing: 16) { cards }.padding(16) }; colours systemColor Color(red: 0.94, green: 0.32, blue: 0.28), userColor Color(red: 0.27, green: 0.52, blue: 0.97), idleColor Color.gray.opacity(0.28) (:25-27). StatsCard (CPUStatsSharedViews.swift:22-62): VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline).primary; content }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))).overlay(stroke Color.white.opacity(0.05), lineWidth: 0.5). CPUUsageDashboard (:64-129): ViewThatFits(in: .horizontal) { VStack(alignment: .leading, spacing: 20) { gauges; usageSection; Divider().padding(.vertical, 4); systemSection } | HStack(alignment: .top, spacing: 28) { gauges; usageSection; systemSection } }; usageSection VStack(spacing 12) with Text("Usage").caption.secondary and DetailRows (System systemColor 0.95, User userColor 0.95, Idle idleColor 0.7, Active no dot) (:76-85); systemSection VStack(spacing 10) Text("System"), Logical cores, Uptime, Divider().padding(.vertical,4), Load 1m/5m/15m "%.2f" (:87-98). CPUSensorGaugeGroup (:131-160): HStack(alignment: .center, spacing: 18) { CPUTemperatureGauge(size 78, lineWidth 8); CPUSegmentDonut(diameter 118, lineWidth 13).frame(118x118); CPUFrequencyGauge(size 78, lineWidth 8) } each .frame(maxWidth: .infinity). CPUSegmentDonut (:244-273): Circle().stroke(idleColor.opacity(0.3), lineWidth) + CPUUsageRing + VStack(spacing 4) { Text(active%).font(.system(size: 30, weight: .bold, design: .rounded)); Text("Active").font(.footnote).secondary }. CPUUsageRing (:275-292): system arc from 0 to systemFraction then user arc; RingArc (:294-306) = Circle().trim(from:to:).stroke(color, StrokeStyle(lineWidth, lineCap: .round)).rotationEffect(-90°). CircularGaugeView (components/Stats/CircularGaugeView.swift:21-66): VStack(spacing: 8) { ZStack { Circle().stroke(backgroundTint = Color.primary.opacity(0.08), lineWidth); RingArc if value > 0; VStack(spacing 2) { Text(primary).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(tint); secondary .system(size: 11, weight: .medium).secondary } }; VStack(spacing 2) { Text(title).caption.secondary; subtitle .footnote.secondary centered } }; defaults size 72, lineWidth 8. DetailRow (:362-388): HStack { optional Circle 8x8; label .system(12, .medium).secondary lineLimit 1 layoutPriority 0.5; Spacer; value .system(13, .semibold, .monospaced).primary lineLimit 1 minimumScaleFactor 0.85 layoutPriority 1 }. LegendRow (:308-327) dot 10, label 12 medium, value 13 semibold mono. LoadAverageRow/Value (:329-360): caption header, HStack(spacing 12) of VStack(spacing 2){label .caption2; value "%.2f" 13 semibold mono}. CPUCoreUsageGrid (:390-405): LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 14, alignment: .top)], spacing: 14); CPUCoreUsageCell (:407-441): VStack(alignment: .leading, spacing: 8) { HStack { Text("Core \(id+1)").caption.secondary; Spacer; Text(%).system(12, .semibold, .monospaced).accent }; GeometryReader bar: Capsule primary 0.08 under Capsule accent width*progress, .frame(height: 8) }.padding(10).background(RoundedRectangle(10, .continuous).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))). CPUDetailsGrid (:443-480, alternative layout, unused by CPUStatsDetailView): spacing 14/8, idle dot Color.gray.opacity(0.4).

### Animations

None explicit (ring trims change without animation).

### State and timing

Temperature gauge scale max 110 (°C) / 230 (°F) (CPUStatsSharedViews.swift:168-170); frequency gauge value = overall/max(maxOverall or overall, 1.0) (:219-224).

### Data sources and APIs

StatsManager published values; topProcesses via onReceive($topCPUProcesses).prefix(8) (CPUStatsDetailView.swift:58-63).

### Settings

cpuTemperatureUnit (see temperature feature).

### Implementation notes

~450 lines of SwiftUI; all public.

### Key files

- `DynamicIsland/components/Stats/CPUStatsDetailView.swift`
- `DynamicIsland/components/Stats/CPUStatsSharedViews.swift`
- `DynamicIsland/components/Stats/CircularGaugeView.swift`

## GPU detail popover

### Behaviour

Cards: "GPU Overview" (Engine Utilization: Render gauge, usage ring, Tiler gauge; breakdown Render/Compute/Video/Other; Averages: Session Avg, Last Update time, Active GPU, Status Active/Idle, Temperature, Cores), "Top Processes" (8), "Devices" (per accelerator row with green/red dot, name, Active/Idle, utilization, Renderer/Tiler/Temperature/Fan Speed/Core Clock/Memory Clock/Cores rows when present).

### Layout

GPUStatsDetailView (components/Stats/GPUStatsDetailView.swift:29-60): ScrollView { VStack(spacing: 16).padding(16) }.frame(minWidth: 360, minHeight: 380); accent Color.purple; cards padding 16, background windowBackgroundColor 0.65, radius 12. GPUUsageDashboard (:68-157): ViewThatFits { HStack(.top, spacing 20) { leftColumn; breakdownAndMeta } | VStack(.leading, spacing 20) }; breakdownAndMeta ViewThatFits { HStack(.top, 20) | VStack(.leading, 16) with Divider().padding(.vertical,4) }; breakdown DetailRows with accent opacities 0.9/0.7/0.55/0.45 (:120-128); meta VStack(spacing 8) "Averages" caption, Session Avg, Last Update (DateFormatter timeStyle .medium), Divider, Active GPU, Status, Temperature ("%.0f°C"), Cores (:130-148). GPUEngineGauges (:159-180): VStack(.leading, spacing 10) { Text("Engine Utilization").caption.secondary; HStack(.center, spacing 18) { EngineGaugeView("Render", size 72); GPUUsageRing(diameter 112, lineWidth 12); EngineGaugeView("Tiler", tint accent.opacity(0.75), size 72) } }. GPUUsageRing (:182-203): Circle().stroke(accent.opacity(0.25), lineWidth 12); RingArc; VStack(spacing 4) { Text(%).system(size 26, .bold, .rounded); Text("Active").footnote.secondary }. EngineGaugeView (:205-244): CircularGaugeView(lineWidth 7, backgroundTint tint.opacity(0.18)) or placeholder ring primary 0.08 lineWidth 7 with "—" .system(18, .semibold).secondary. GPUDeviceList (:246-260) VStack(spacing 16) with Divider between. GPUDeviceRow (:262-314): HStack(spacing 12) { Circle 8 fill green 0.85 / red 0.7; VStack(spacing 2) { name .system(13, .semibold); status .caption2 green/secondary }; Spacer; VStack(.trailing, spacing 2) { utilization .system(14, .semibold, .monospaced) accent; "Utilization" .caption2.secondary } }; then VStack(spacing 8) of DetailRows (Renderer accent 0.9, Tiler accent 0.6, others no dot).

### Animations

None.

### State and timing

Render gauge value = primaryDevice.renderUtilization ?? breakdown.render; Tiler = primaryDevice.tilerUtilization (nil → placeholder) (:150-156).

### Data sources and APIs

statsManager.gpuUsage, gpuBreakdown, avgGpuUsage, lastUpdated, gpuDevices; processes via getProcessesRankedByGPU() on appear and on every $lastUpdated (:56-66).

### Settings

None.

### Implementation notes

~300 lines SwiftUI.

### Key files

- `DynamicIsland/components/Stats/GPUStatsDetailView.swift`
- `DynamicIsland/components/Stats/CPUStatsSharedViews.swift`

## Memory detail popover

### Behaviour

Cards: "Memory Overview" (128pt used/free ring with big % and "Used"; Used/Free/Total; Breakdown App/Cached/Wired/Compressed as "bytes · %"), "Top Processes" (8, memory-sorted), "Pressure & Swap" (Normal/Warning/Critical capsule with description; Swap Used/Free/Total + bar or "Swap is disabled on this system.").

### Layout

MemoryStatsDetailView (components/Stats/MemoryStatsDetailView.swift:29-56): ScrollView/VStack(16)/padding 16; .frame(minWidth: 380, minHeight: 420); accent Color.green. MemoryUsageDashboard (:59-121): ViewThatFits { VStack(.leading, 20) { ring; totals; Divider; breakdown } | HStack(.top, 28) }; totals DetailRows Used accent 0.8, Free gray-0.28 at 0.9, Total; breakdown rows App 0.85, Cached 0.65, Wired 0.45, Compressed 0.35 (:73-81); usageRing: Circle().stroke(freeColor.opacity(0.35), lineWidth 14).frame(128x128) + MemoryUsageRing (used arc accent then free arc freeColor 0.65, lineWidth 14) + VStack(spacing 4) { Text(%).system(size 30, .bold, .rounded); Text("Used").footnote.secondary } (:103-140). MemoryPressureIndicator (:167-210): "Pressure" caption; Capsule fill status.opacity(0.16) height 28 containing HStack(spacing 8){Circle 10 status color; title .system(13, .semibold) status color}.padding(.horizontal, 12); description .footnote.secondary; colours normal green / warning orange / critical red with texts "System memory pressure is nominal." / "Memory pressure is elevated. Closing apps may help." / "Memory pressure is critical; the system may purge aggressively.". SwapUsageView (:212-235): VStack(.leading, 10) "Swap" caption; rows Used accent 0.85, Free accent 0.55, Total; SwapUsageBar height 8 (Capsule primary 0.08 under Capsule tint 0.8) (:237-255).

### Animations

None.

### State and timing

Refreshes every tick via $lastUpdated.

### Data sources and APIs

statsManager.memoryBreakdown; getProcessesRankedByMemory() on appear and each $lastUpdated (:47-56).

### Settings

None.

### Implementation notes

~250 lines SwiftUI.

### Key files

- `DynamicIsland/components/Stats/MemoryStatsDetailView.swift`

## Network detail popover

### Behaviour

Cards: "Network Overview" (Download in orange / Upload in red: big current speed, Average, Peak), "Interfaces" (icon tile, name, Active capsule, IPv4/IPv6, session ↓/↑ bytes, Down/Up speeds) or "No active interfaces detected yet.", "Session Totals" (Downloaded/Uploaded).

### Layout

NetworkStatsDetailView (components/Stats/NetworkStatsDetailView.swift:28-66): ScrollView/VStack(16)/padding 16; .frame(minWidth: 360, minHeight: 340); downloadColor .orange, uploadColor .red. NetworkOverview (:69-110): HStack(.center, spacing 24) { VStack(.leading, 10) { Text("Download").headline downloadColor; Text(throughput).system(size 26, .bold, .rounded).primary; DetailRow Average (0.6), Peak (0.45) }; Divider().frame(height: 110).overlay(Color.white.opacity(0.06)); same for Upload }. Average = mean of non-zero history, Peak = history.max() (:35-38, :61-66). NetworkInterfacesCard (:130-180): sorted active first then type priority; VStack(spacing 12) with Divider().padding(.leading, 44). NetworkInterfaceRow (:182-273): HStack(.top, spacing 12) { icon RoundedRectangle(8, .continuous) fill downloadColor 0.18 (active) / primary 0.05, symbol .system(16, .semibold), frame 32x32; VStack(.leading, 6) { HStack(8) { name .system(13, .semibold); Active capsule .caption2 downloadColor padding h6 v2 bg downloadColor 0.16 }; "IPv4 · x" / "IPv6 · x" .caption2.secondary; "Session · ↓ a · ↑ b" .caption2.secondary }; Spacer; VStack(.trailing, 4) { Down/Up rows: label .caption2.secondary + value .system(13, .semibold, .monospaced) coloured } }; icons wifi → "wifi", ethernet → "cable.connector", cellular → "antenna.radiowaves.left.and.right", loopback → "arrow.triangle.2.circlepath", other → "network" (:243-256). NetworkTotalsView (:112-128): VStack(spacing 10) DetailRows Downloaded (download 0.75) / Uploaded (upload 0.75) formatted via StatsFormatting.bytes(MB*1_048_576).

### Animations

None.

### State and timing

No process list in this popover.

### Data sources and APIs

statsManager.networkDownload/Upload, histories, networkInterfaces, networkTotals.

### Settings

None.

### Implementation notes

~270 lines SwiftUI.

### Key files

- `DynamicIsland/components/Stats/NetworkStatsDetailView.swift`

## Disk detail popover

### Behaviour

Cards: "Disk Overview" (Read cyan / Write yellow: big MB/s, Peak), "Storage Devices" (icon, name, path, System/External badge, usage bar, Used/Free, Total) or "No storage devices detected yet.", "Session Totals" (Read/Written bytes).

### Layout

DiskStatsDetailView (components/Stats/DiskStatsDetailView.swift:28-53): ScrollView/VStack(16)/padding 16; .frame(minWidth: 360, minHeight: 340); readColor .cyan, writeColor .yellow. DiskOverview (:56-93): same shape as NetworkOverview (HStack spacing 24, headline coloured title, .system(26, .bold, .rounded) value via StatsFormatting.mbPerSecond, Peak DetailRow at 0.6, Divider height 110 white 0.06). DiskDevicesCard (:113-146): sorted root first, non-removable first, name; VStack(spacing 12) with Divider().padding(.leading, 36). DiskDeviceRow (:148-209): VStack(.leading, 8) { HStack(10) { RoundedRectangle(8, .continuous).fill(accent 0.16) with symbol "externaldrive"/"internaldrive" .system(16, .semibold) accent, 32x32; VStack(2) { name .system(13, .semibold); path .caption2.secondary lineLimit 1 }; Spacer; badge "System" (isRoot) or "External" (isRemovable): .caption2 accent, padding h6 v2, bg accent 0.16, Capsule }; DiskUsageBar height 8 (Capsule primary 0.08 under Capsule tint 0.8); HStack { "Used · bytes" .caption2.secondary; Spacer; "Free · bytes" }; "Total · bytes" .caption2.secondary }. DiskTotalsView (:95-111): DetailRows Read (read 0.75) / Written (write 0.75).

### Animations

None.

### State and timing

No process list.

### Data sources and APIs

statsManager.diskRead/Write, histories, diskDevices, diskTotals.

### Settings

None.

### Implementation notes

~230 lines SwiftUI.

### Key files

- `DynamicIsland/components/Stats/DiskStatsDetailView.swift`

## Stats settings pane

### Behaviour

Settings → Stats: "Enable system stats monitoring" toggle (General section, footer: "When enabled, the Stats tab will display real-time system performance graphs. This feature requires system permissions and may use additional battery. …"); when enabled: "Monitoring Behavior" section with "Stop monitoring after closing the notch" toggle (help: "When enabled, stats monitoring stops a few seconds after the notch closes."), "Update interval" slider 1-60 s step 1 labelled "1 s" / "N s" / "60 s (1 min)" with caption "Controls how often system metrics refresh while monitoring is active.", an orange warning "High-frequency updates without a timeout can increase battery usage." when stop-on-close is off and interval <= 5, footer "Sampling can continue while the notch is closed when the timeout is disabled."; "Graph Visibility" section with toggles CPU Usage (+ Temperature unit segmented picker Celsius/Fahrenheit when on), Memory Usage, GPU Usage, Network Activity, Disk I/O; footer either "With N graphs enabled, the Dynamic Island will expand horizontally to accommodate all graphs in a single row." (N >= 4) or "Each graph can be individually enabled or disabled. Network activity shows download/upload speeds, and disk I/O shows read/write speeds."; "Monitoring Status" section with Active/Stopped dot and live values.

### Layout

StatsSettings Form (components/Settings/SettingsView.swift:7974-8270): Section General (:8018-8040); Section Monitoring Behavior (:8140-8180) with VStack(.leading, spacing 8) { HStack { Text("Update interval"); Spacer; Text(formatted).secondary }; Slider(value:in: 1...60, step: 1); caption }; warning Label with "exclamationmark.triangle.fill" .font(.caption).foregroundStyle(.orange).padding(.top, 4) (:8163-8172); Section Graph Visibility (:8182-8226); Section Monitoring Status (:8228-8270) with Circle 8x8 green/red. Search entries registered at :435-450.

### Animations

None.

### State and timing

formattedUpdateInterval rounds to Int seconds (:8001-8010); shouldShowStatsBatteryWarning = !stop && interval <= 5 (:8012-8014).

### Data sources and APIs

Defaults.Toggle, SettingsSegmentedPicker (app-internal), StatsManager.shared observed.

### Settings

Full key list (Constants.swift:1281-1298): enableStatsFeature=false; autoStartStatsMonitoring=true (unused); statsStopWhenNotchCloses=true; statsUpdateInterval=1.0; showCpuGraph=true; showMemoryGraph=true; showGpuGraph=true; showNetworkGraph=false; showDiskGraph=false; cpuTemperatureUnit="Celsius"|"Fahrenheit" defaulting to locale.

### Implementation notes

Map to UserSettings keys e.g. stats.enabled, stats.stopWhenClosed, stats.updateInterval, stats.showCPU/Memory/GPU/Network/Disk, stats.temperatureUnit. ~150 lines in Notchy SettingsView.

### Key files

- `DynamicIsland/components/Settings/SettingsView.swift`
- `DynamicIsland/models/Constants.swift`

## Unknowns

- components/Stats/DetailedTimelineGraph.swift and DualTimelineGraph.swift contain only the license header (18 lines each) — dead files; no larger timeline graph exists in 2.3.3.
- Defaults key autoStartStatsMonitoring (Constants.swift:1290, default true) is declared but never read anywhere in the source; behaviour if it were honoured is unknown.
- DynamicIslandViewCoordinator.statsSecondRowExpansion is always 1 and no gesture/animation collapses the second row; the 0.3 s easeInOut notch-size animation (DynamicIslandViewModel.swift:236) only fires if the value changed, so in practice the 2-row height change is applied by the regular tab-switch window resize path, not by this publisher. Exact resize curve when entering the Stats tab with 4+ graphs belongs to the general notch-open/tab-switch animation subsystem.
- StatsManager.swift:531 comment says monitoring starts after 3.5 s; the code uses 0.5 s. Shipped binary behaviour follows the code (not verified at runtime).
- Settings footer (SettingsView.swift:8216) claims the island expands horizontally for 4+ graphs; code only adds 132 pt of height. Not verified by screenshot.
- GPU breakdown Compute/Video/Other are synthetic fractions (0.6/0.25/rest of the remainder) of a single utilization number, not measured engine counters.
- Per-process GPU ranking reuses the CPU-sorted list (StatsManager.swift:1426-1430).
- Headline network throughput (getNetworkStats) counts only en*/"Wi-Fi" interfaces while the Interfaces list includes bridge/pd/vmnet/ap; so the card value and the sum of interface rows can differ.
- Which SMC temperature keys actually resolve on the user's machine (and therefore whether the gauge shows a value or '—') depends on the chip; the strings scan confirms the key literals ship, but not which ones succeed. 'TC0D/TC0E/TC0F/TC0H' were not found as standalone strings in the binary (only TC0P), possibly due to string merging — unverified.
- IOReport channel availability (ECPU*/PCPU* under 'CPU Stats') and the pmgr voltage-states decoding are Apple-Silicon specific and undocumented; on Intel the frequency gauge is nil.
- The REA dispatch.json does not carry Swift method names for StatsManager/CPUSensorCollector (methods: [] on the ObjC class records), so per-method presence was confirmed via the imports and string literals rather than symbol tables.
- Exact SwiftUI .popover arrow edge/attachment anchor is the framework default; AppKit NSPopover behaviour (e.g. transient vs semitransient) is not configured in source.
- Localized string table (Localizable.xcstrings) may override the English copy quoted here (e.g. key "stats_resource_active").

## Critic pass

Missing from the spec:

- Settings 'Controls' section (components/Settings/SettingsView.swift:8312-8334): a 'Start Monitoring'/'Stop Monitoring' .borderedProminent button (foreground .red while monitoring, .blue otherwise) that calls statsManager.startMonitoring()/stopMonitoring() directly, bypassing smart monitoring; and a 'Clear Data' .bordered button that calls statsManager.clearHistory() (StatsManager.swift:1402-1410) and is .disabled while monitoring. The spec says clearHistory() is never called by the lifecycle, but this button is its one real caller.
- Settings live-data section is mis-described: the section at SettingsView.swift:8228-8310 has header 'Live Performance Data' (:8309), not 'Monitoring Status' (that is only the first row label :8230). It also contains a 'Last Updated' row rendering Text(statsManager.lastUpdated, style: .relative) (:8301-8306), and its Network Download/Upload and Disk Read/Write rows use String(format: "%.1f MB/s") (:8273, :8280, :8289, :8296), not StatsFormatting.throughput. Section footers are styled .multilineTextAlignment(.trailing).foregroundStyle(.secondary).font(.caption) (:8039-8041 etc.).
- The Stats settings pane is shared with the LLM Usage subsystem: the General section also has an 'Enable LLM Usage Monitor' toggle (SettingsView.swift:8030-8033) and the General footer continues '...Enabling LLM Usage Monitor adds a Usage tab that tracks token usage and spend across your configured AI providers.' (:8038); when enableLLMUsageFeature is on, 'LLM Providers' and 'New API Accounts' sections appear (:8044-8137). SettingsTab.stats belongs to the .developer category (:82) with title 'Stats' (:101).
- Onboarding profile defaults (components/Onboarding/ProfileSelectionView.swift): applyProfileSettings sets Defaults[.enableStatsFeature] = true for the 'developer' profile (:211) and = false for 'designer' (:226), 'lightuse' (:238) and 'student' (:252); the Developer card description mentions 'stats monitoring' (:39). This is the only place the feature is turned on automatically.
- Eager initialisation cost: ContentView holds @ObservedObject var statsManager = StatsManager.shared (ContentView.swift:50), so the singleton is created at launch regardless of enableStatsFeature. Its init takes network/disk baselines (StatsManager.swift:481-487) and builds CPUSensorCollector() (:462) whose init calls setupFrequencyChannel() -> dlopen(IOReport) + IOReportCopyChannelsInGroup x2 + IOReportMergeChannels + IOReportCreateSubscription (CPUSensorCollector.swift:46-47, :151-175), and touches AppleHardwareInfo.shared (sysctl brand string/hw.logicalcpu, IOKit AppleARMPE and AppleARMIODevice registry walks; AppleHardwareInfo.swift:65-72). Only SMC.shared (IOServiceOpen on AppleSMC) is lazy, created on the first readTemperature() tick (SMC.swift:163, CPUSensorCollector.swift:58).
- Effective popover sizes: the detail views carry their own minimum frames that override RankedProcessPopover's minHeight: GPUStatsDetailView .frame(minWidth: 360, minHeight: 380) (GPUStatsDetailView.swift:55) vs popover (380, 360); MemoryStatsDetailView .frame(minWidth: 380, minHeight: 420) (MemoryStatsDetailView.swift:46) vs popover (400, 380); Network/Disk .frame(minWidth: 360, minHeight: 340) (NetworkStatsDetailView.swift:58, DiskStatsDetailView.swift:52) vs popover (360, 320). So the real minimum heights are CPU 420, Memory 420, GPU 380, Network/Disk 340. CPUStatsDetailView has no min frame.
- Card identity semantics: the grid uses ForEach(0..<graphCount, id: \.self) (NotchStatsView.swift:163, :174, :182, :194, :202), so cards are keyed by index, not by metric. Toggling e.g. CPU off makes every remaining card cross-fade its content into the previous slot and only the last index plays the .scale+.opacity removal transition. The else-branch at :261-267 (card without rankingType) is dead because every GraphData has a non-nil rankingType (:93, :104, :115, :130, :145); graphView(for:) at :310-312 is unused.
- Popover hover tracking is dead for auto-close: the five isHovering*Popover @State flags (NotchStatsView.swift:75-79) are set from PopoverHoverSensor and trigger updateStatsPopoverState() (:391-405), but that function computes newState = anyPopoverOpen from the showing* flags only (:408-409). Hovering a popover therefore never influences vm.isStatsPopoverActive; PopoverHoverSensor.TrackingView (confirmed in REA dispatch.json as _TtCV5AtollP33_..._PopoverHoverSensor12TrackingView with updateTrackingAreas/mouseEntered:/mouseExited:) is effectively telemetry. TrackingView.deinit also calls onHoverChange(false) (RankedProcessPopover.swift:124-129).
- MiniGraph/DualQuadrantGraph draw order: inside the GeometryReader the stroke Path is emitted before the gradient fill Path (NotchStatsView.swift:524-565; :598-683), so the 0.3->0.1 alpha gradient is composited on top of the 2pt line. For a 30-sample series, stepX = width/29 (:527).
- GPU model/vendor fallbacks omitted: vendor = vendorName(from: IOClass) ?? dict["vendor"] as? String (StatsManager.swift:141); GPUDeviceMetrics.formattedVendorModel returns model when vendor == model, else "<vendor> <model>" (:344-349); utilizationText returns "—" when nil (:351-354). makeGPUBreakdown has an extra branch: when total.isZero but render/tiler are non-zero it returns GPUBreakdown(render: renderUtil, compute: tilerUtil, video: 0, other: 0) (:966-973). gpuDevices uses kIOMainPortDefault (:111) while SMC/AppleHardwareInfo use the deprecated kIOMasterPortDefault (SMC.swift:172, AppleHardwareInfo.swift:129, :159).
- Memory total fallback: if the cached host_info max_mem is 0, total = free+speculative+active+inactive+wired+compressed (StatsManager.swift:885-890); MemoryBreakdown exposes usedPercentage/freePercentage/appPercentage/cachePercentage (:57-75); MemoryPressure.unknown = (rawValue 0, .normal) (:96); the sysctl return codes for kern.memorystatus_vm_pressure_level and vm.swapusage are ignored (:905, :919).
- ProcessStats identity: ProcessStats.id = UUID() (components/Stats/ProcessStats.swift:25) is regenerated on every ps refresh (every tick), so the Top Processes ForEach rebuilds all rows each second with no row diffing/animation. ProcessRankingType also declares title/icon/color tables ('CPU Usage','Memory Usage','GPU Usage','Network Activity','Disk Activity'; cpu/memorychip/display/network/internaldrive; blue/green/purple/orange/cyan) at ProcessStats.swift:51-78 that mirror the card tables.
- CPU detail details omitted: the 'Per-Core Usage' StatsCard is only rendered when statsManager.cpuCoreUsage is non-empty (CPUStatsDetailView.swift:50-54); 'Logical cores' displays max(statsManager.cpuCoreUsage.count, 1) (CPUStatsDetailView.swift:37, CPUStatsSharedViews.swift:91), i.e. the host_processor_info CPU count, not AppleHardwareInfo.logicalCoreCount (hw.logicalcpu), which is computed but never read. Localised key 'stats_resource_active' (default 'Active') is used for the Active labels (CPUStatsSharedViews.swift:83, :267; GPUStatsDetailView.swift:196, :275; NetworkStatsDetailView.swift:196).
- Dead/unused StatsManager API worth knowing before porting: maxCpuUsage/maxMemoryUsage/maxGpuUsage/avgCpuUsage/avgMemoryUsage (StatsManager.swift:1371-1393) have no callers (only avgGpuUsage is used, GPUStatsDetailView.swift:36); StatsFormatting.gigabytes (StatsFormatting.swift:73-78), LegendRow (CPUStatsSharedViews.swift:308-327), CPUDetailsGrid (:443-480), LoadAverageRow (:329-344, only referenced by CPUDetailsGrid), CPUTemperatureMetrics.fahrenheit (CPUSensorCollector.swift:34-37), GPUBreakdown.totalUsage (StatsManager.swift:275-277) and IOReportSimpleGetIntegerValue (IOReportBridging.swift:118-122) are unused.
- SMC.swift carries a full fan-control/write surface that the stats feature never calls: write(_:_:) (:346-357), setFanMode (:361-432), setFanSpeed (:434-469), resetFans (:471-479), getAllKeys via '#KEY' + readIndex selector 8 (:315-344), getStringValue for '{fds' (:275-313), plus SMCKeys writeBytes=6, readIndex=8, readPLimit=11, readVers=12 (:43-51). Decoder quirks: SMCDataType.SP69 raw value is the 5-char 'sp669' (:31) so it can never equal a 4-char FourCC and that branch is dead; 'fp2e' is declared (:39) but not decoded by getValue; getValue prints an error line for every failed key read (:210), i.e. several console lines per tick on machines lacking TC0x keys.
- Timer scheduling details: all three timers are Timer.scheduledTimer on the main run loop in default mode (StatsManager.swift:532, :621, :657), so sampling pauses during tracking loops (slider drags, scroll). scheduleDelayedStop(after:) stops synchronously when delay <= 0 (:650-653). handleUpdateIntervalChange returns early after writing the clamped value back (:633-636) and relies on the Defaults publisher re-firing with the clamped value to reschedule.
- Window-size debounce value: debouncedUpdateWindowSize uses a DispatchWorkItem scheduled after 0.15 s (DynamicIslandApp.swift:147-159). The coordinator's enforceMinimumNotchWidth re-run on enableStatsFeature changes is debounced 100 ms (DynamicIslandViewCoordinator.swift:228, :235-238). The statsSecondRowExpansion sink also calls AppDelegate.ensureWindowSize(addShadowPadding(...), animated: false, force: false) after the 0.3 s easeInOut (DynamicIslandViewModel.swift:239-244).
- statsAdditionalRowHeight is reused outside stats: extension tab/minimalistic preferred heights are clamped to baseSize.height + statsAdditionalRowHeight (ContentView.swift:2520-2527, :2530-2536), so 132 pt is also the maximum extra height any tab may request.
- Reachability of the 'Stats Disabled' placeholder: NotchStatsView is only mounted for coordinator.currentView == .stats (ContentView.swift:1295-1296) and the tab only exists while enableStatsFeature is true (TabSelectionView.swift:81-82); the placeholder can only appear if the feature is switched off while the notch is already open on the Stats tab (currentView is not reset by the toggle).
- Source/binary skew: the clone is at commit 868c25d (2026-10-15) with MARKETING_VERSION 2.3.3 (project.pbxproj:831) while the installed app is 2.3.3 build 20260720004 (plist.json). The M5 platform cases (AppleHardwareInfo.swift:41-44, :118-123, :166) and the M5 SMC key list (CPUSensorCollector.swift:249-250: Tp00, Tp04, Tp08, Tp0C, Tp0G, Tp0K, Tp0O, Tp0R, Tp0U, Tp0X, Tp0a, Tp0d, Tp0g, Tp0j, Tp0m, Tp0p, Tp0u, Tp0y) are NOT present in the shipped binary (strings scan finds none of the M5-only keys), so they are post-2.3.3 additions; everything else in the spec matches the binary.

Corrections:

- WRONG (unknowns): 'TC0D/TC0E/TC0F/TC0H were not found as standalone strings in the binary (only TC0P)'. A `strings -a` scan of /Applications/Atoll.app/Contents/MacOS/Atoll finds all five primary keys TC0D, TC0E, TC0F, TC0H, TC0P plus AppleSMC, machdep.cpu.brand_string and hw.logicalcpu, so the primary candidate list (CPUSensorCollector.swift:236) ships as written.
- WRONG: 'while any stats popover is open (or hovered) the notch will not auto-close'. Only the showing* flags feed vm.isStatsPopoverActive (NotchStatsView.swift:408-411); the isHovering*Popover flags never affect auto-close. Remove '(or hovered)'.
- WRONG/INCOMPLETE: 'Monitoring Status section (:8228-8270)'. The section spans SettingsView.swift:8228-8310, its header is 'Live Performance Data' (:8309), it has a 'Last Updated' relative-time row (:8301-8306), and Network/Disk values use '%.1f MB/s' (:8273, :8280, :8289, :8296), not StatsFormatting.throughput. A further 'Controls' section (:8312-8334) with Start/Stop Monitoring and Clear Data buttons is missing entirely.
- INACCURATE: 'Logical core count sysctl hw.logicalcpu (:84-89)' is listed as the source of the CPU popover's 'Logical cores' row. AppleHardwareInfo.logicalCoreCount is never read; the row shows max(statsManager.cpuCoreUsage.count, 1) from host_processor_info (CPUStatsDetailView.swift:37; CPUStatsSharedViews.swift:91).
- INACCURATE: 'binary strings contain ... every IOReport* symbol name' / 'all 12 IOReport* function names'. The source declares 13 shims (IOReportBridging.swift:46-122); the binary contains 12 (IOReportCopyChannelsInGroup, MergeChannels, CreateSubscription, CreateSamples, CreateSamplesDelta, ChannelGetGroup/SubGroup/ChannelName/UnitLabel, StateGetCount/GetNameForIndex/GetResidency). IOReportSimpleGetIntegerValue (:118-122) has no callers and is absent from the binary (dead-stripped).
- INACCURATE popover sizes: '(W,H) = cpu (420, 420), memory (400, 380), gpu (380, 360), network/disk (360, 320)' are the RankedProcessPopover frames (RankedProcessPopover.swift:31-42), but the content views impose larger minimums (Memory minHeight 420 at MemoryStatsDetailView.swift:46; GPU minHeight 380 at GPUStatsDetailView.swift:55; Network/Disk minHeight 340 at NetworkStatsDetailView.swift:58 / DiskStatsDetailView.swift:52). Effective minimum heights: CPU 420, Memory 420, GPU 380, Network 340, Disk 340.
- INCOMPLETE: 'clearHistory() at :1402-1410 exists but is never called by the lifecycle' is true, but it IS called by the Settings 'Clear Data' button (SettingsView.swift:8326-8330), so history can be reset by the user while monitoring is stopped.
- INCOMPLETE: the frequency-decoding statement 'skipping states named IDLE, DOWN, OFF' describes the code loosely. calculateFrequency finds the FIRST state index whose label is not IDLE/DOWN/OFF (CPUSensorCollector.swift:220), sums residencies from that offset to the end (:223), and maps freqs[i] to state[offset+i] (:226-231); it does not skip arbitrary idle-named states after the offset.
- INCOMPLETE: SMC decode table lists 'sp669/512' as a working case; SMCDataType.SP69.rawValue is the 5-character string 'sp669' (SMC.swift:31) and can never match a 4-char FourCC string from keyInfo.dataType.toString() (:497, :124-129), so that branch is dead. Also 'fp2e' (:39) is declared but not decoded by getValue (falls to default -> nil).
- MINOR line-reference: 'notch size for .stats = base + (rows-1)*132 (:233-240)' — the guard that routes non-stats tabs to inlineLyricsAdjustedNotchSize starts at ContentView.swift:226; the stats branch is :226-241.
- MINOR: 'ContentView.swift:764-772 ... passing currentView string "stats" or "other"' is correct, but note both call sites are gated on enableStatsFeature (ContentView.swift:766, :832); with the feature off, updateMonitoringState is never invoked and only SettingsView's onChange (:8023-8028) stops monitoring.
- MINOR: GPU collector matching uses kIOMainPortDefault (StatsManager.swift:111, :1305) whereas the spec's SMC/hardware paths use kIOMasterPortDefault (SMC.swift:172; AppleHardwareInfo.swift:129, :159). Both resolve to the same default port; mention only to avoid copying the deprecated constant.

Private API summary:

PRIVATE (hard dependency, confirmed shipping): IOReport.framework for CPU frequency. utils/IOReportBridging.swift:24-36 dlopen()s "/System/Library/PrivateFrameworks/IOReport.framework/IOReport" then "/usr/lib/libIOReport.dylib" with RTLD_LAZY|RTLD_LOCAL and dlsym()s 12 C functions (IOReportCopyChannelsInGroup, IOReportMergeChannels, IOReportCreateSubscription, IOReportCreateSamples, IOReportCreateSamplesDelta, IOReportChannelGetGroup/SubGroup/ChannelName/UnitLabel, IOReportStateGetCount/GetNameForIndex/GetResidency; a 13th shim IOReportSimpleGetIntegerValue is unused). CPUSensorCollector.swift:151-175 subscribes to group "CPU Stats", subgroups "CPU Complex Performance States" and "CPU Core Performance States" and reads ECPU*/PCPU* residencies per tick (:76-147). REA evidence: macho.json imports _dlopen/_dlsym/_dlclose/_dlerror; dylib.json lists no IOReport dependency (runtime-loaded only); the binary contains both library paths, "IOReportChannels", the two subgroup names and the 12 symbol names. Missing symbols degrade to nil (frequency gauge shows an em dash); on Intel the channels/pmgr data do not exist.

UNDOCUMENTED PROTOCOL OVER PUBLIC IOKIT (treat as private): CPU temperature via the AppleSMC user client. SMC.swift:171-190 uses IOServiceMatching("AppleSMC") + IOServiceGetMatchingServices(kIOMasterPortDefault) + IOServiceOpen(device, mach_task_self_, 0); reads are IOConnectCallStructMethod(conn, selector 2 /*kernelIndex*/, SMCKeyData_t in/out, stride-sized) with data8 = 9 (readKeyInfo) then 5 (readBytes) (:483-509, :533-538). The struct layout and selectors are reverse-engineered, not API. REA: macho.json imports _IOServiceOpen, _IOServiceClose, _IOConnectCallStructMethod; dispatch.json has _TtC5Atoll3SMC (1 ivar: io_connect_t); binary contains "AppleSMC" and all TC0x/Tp/Te/Tf key literals except the post-2.3.3 M5 list.

UNDOCUMENTED REGISTRY DATA READ WITH PUBLIC API: (a) GPU: IOServiceMatching(kIOAcceleratorClassName="IOAccelerator") + IORegistryEntryCreateCFProperties, reading "PerformanceStatistics" keys "Device Utilization %", "GPU Activity(%)", "Renderer Utilization %", "Tiler Utilization %", "Temperature(C)", "Fan Speed(%)", "Core Clock(MHz)", "Memory Clock(MHz)", plus "gpu-core-count", "model", "vendor", "AGCInfo"/"poweredOffByAGC" (StatsManager.swift:106-264). (b) Disk I/O: IOServiceMatching("IOStorage") "Statistics" -> "Bytes read from block device"/"Bytes written to block device" (:1298-1340). (c) Apple-silicon topology: AppleARMPE child "cpus" Data props "e-core-count"/"p-core-count" via IORegistryEntryGetChildIterator/IORegistryEntryGetName (AppleHardwareInfo.swift:127-155; both imported per macho.json) and AppleARMIODevice entry "pmgr" props "voltage-states1-sram"/"voltage-states5-sram" decoded as 8-byte LE records (:157-183, IOKitHelpers.swift:45-63). (d) sysctl "kern.memorystatus_vm_pressure_level" (not in public headers; values 2=warning, 4=critical) (StatsManager.swift:903-915). Binary strings confirm IOAccelerator, PerformanceStatistics, the utilization keys, IOStorage, both block-device keys, AppleARMPE, AppleARMIODevice, voltage-states1/5-sram, kern.memorystatus_vm_pressure_level and vm.swapusage.

PUBLIC: host_statistics(HOST_CPU_LOAD_INFO), host_statistics64(HOST_VM_INFO64), host_processor_info(PROCESSOR_CPU_LOAD_INFO), host_info(HOST_BASIC_INFO), mach_host_self/mach_port_deallocate, vm_deallocate, vm_kernel_page_size, getloadavg, sysctlbyname (hw.logicalcpu, machdep.cpu.brand_string, vm.swapusage), getifaddrs/freeifaddrs/inet_ntop/if_data, FileManager.mountedVolumeURLs + URLResourceValues, ProcessInfo.systemUptime/physicalMemory, Process launching /bin/ps -Aceo pid,pcpu,comm -r, NSRunningApplication(processIdentifier:), and libproc proc_pidinfo(PROC_PIDTASKINFO) (semi-public header, imported per macho.json). All UI is plain SwiftUI/AppKit (NSPopover via .popover, NSTrackingArea, Defaults package).

PERMISSIONS/ENTITLEMENTS: no TCC prompt is involved. The feature requires a NON-SANDBOXED process: signature.json shows Atoll has no com.apple.security.app-sandbox entitlement (hardened runtime on, com.apple.security.cs.disable-library-validation true, which is unrelated to IOReport since it is an Apple-signed system library). Under App Sandbox, IOServiceOpen on AppleSMC, dlopen of the private framework, spawning /bin/ps and reading other processes' proc_pidinfo would fail or be blocked. The Settings footer's "requires system permissions" wording (SettingsView.swift:8038) does not correspond to any runtime permission request.
