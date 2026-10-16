import Darwin
import Foundation
import IOKit

/// Reads the raw system counters and turns them into a `StatsSample`. Lives off the main
/// actor so the Mach, BSD and IOKit calls never block the island, and keeps the previous
/// counters so usage and throughput come out as deltas over the sampling span. Public APIs
/// only: `host_statistics`, `host_processor_info`, `host_statistics64`, `sysctlbyname`,
/// `getloadavg`, `getifaddrs`, `statfs` and IORegistry property reads.
actor SystemStatsProbe {
    private let hostPort: mach_port_t
    private let pageSize: UInt64
    private let totalMemory: UInt64

    private var previousCPUTicks: CPUTicks?
    private var previousCoreTicks: [CPUTicks]?
    private var previousLinkCounters: [String: LinkCounters]?
    private var previousDiskCounters: TransferDelta?
    private var previousTimestamp: Date?
    private var lastCPU: CPULoadBreakdown = .zero
    private var lastCoreUsage: [Double] = []
    private var lastMemory: MemorySnapshot = .zero
    private var lastLoadAverage: LoadAverage = .zero

    init() {
        // One send right for the lifetime of the probe; asking again on every tick would
        // leak a right each time.
        let port = mach_host_self()
        hostPort = port
        var size: vm_size_t = 0
        pageSize = host_page_size(port, &size) == KERN_SUCCESS && size > 0 ? UInt64(size) : 4_096
        totalMemory = ProcessInfo.processInfo.physicalMemory
    }

    /// Re-reads the throughput counters so the first tick after a start reports no rate and
    /// counts no bytes it did not watch.
    func prepareForMonitoring() {
        previousLinkCounters = readLinkCounters()
        previousDiskCounters = readDiskCounters()
        previousTimestamp = Date()
    }

    /// Forgets all delta state so the first tick after a restart is an absolute reading.
    func reset() {
        previousCPUTicks = nil
        previousCoreTicks = nil
        previousLinkCounters = nil
        previousDiskCounters = nil
        previousTimestamp = nil
        lastCoreUsage = []
    }

    func sample() -> StatsSample {
        let now = Date()
        let elapsed = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0

        if let ticks = readCPUTicks() {
            if let breakdown = ticks.breakdown(since: previousCPUTicks) { lastCPU = breakdown }
            previousCPUTicks = ticks
        }
        if let coreTicks = readCoreTicks() {
            lastCoreUsage = CPUTicks.coreUsage(current: coreTicks, previous: previousCoreTicks)
            previousCoreTicks = coreTicks
        }
        if let memory = readMemory() { lastMemory = memory }
        if let load = readLoadAverage() { lastLoadAverage = load }

        let gpuDevices = readGPUDevices()

        let links = readLinkCounters()
        let networkDelta = previousLinkCounters.map { TransferMath.delta(from: $0, to: links) } ?? .zero
        previousLinkCounters = links

        var diskRate: TransferRate?
        var diskDelta = TransferDelta.zero
        if let counters = readDiskCounters() {
            if let previous = previousDiskCounters {
                diskDelta = TransferMath.delta(from: previous, to: counters)
            }
            diskRate = TransferRate(delta: diskDelta, elapsed: elapsed)
            previousDiskCounters = counters
        } else {
            previousDiskCounters = nil
        }
        previousTimestamp = now

        return StatsSample(
            timestamp: now,
            cpu: lastCPU,
            coreUsage: lastCoreUsage,
            loadAverage: lastLoadAverage,
            uptime: ProcessInfo.processInfo.systemUptime,
            memory: lastMemory,
            gpuUsage: GPUDevice.averageUtilization(of: gpuDevices),
            gpuDevices: gpuDevices,
            network: TransferRate(delta: networkDelta, elapsed: elapsed),
            networkDelta: networkDelta,
            disk: diskRate,
            diskDelta: diskDelta,
            rootVolume: readRootVolume()
        )
    }

    // MARK: - CPU

    private func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// Copies the per-core tick table out of the Mach-allocated buffer and frees it at once,
    /// so nothing from the kernel has to be kept between ticks.
    private func readCoreTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        let stride = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(cpuCount) * stride else { return nil }
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            func tick(_ state: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: info[base + Int(state)]))
            }
            return CPUTicks(
                user: tick(CPU_STATE_USER),
                system: tick(CPU_STATE_SYSTEM),
                idle: tick(CPU_STATE_IDLE),
                nice: tick(CPU_STATE_NICE)
            )
        }
    }

    private func readLoadAverage() -> LoadAverage? {
        var loads = [Double](repeating: 0, count: 3)
        let filled = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return 0 }
            return getloadavg(base, 3)
        }
        guard filled == 3 else { return nil }
        return LoadAverage(oneMinute: loads[0], fiveMinutes: loads[1], fifteenMinutes: loads[2])
    }

    // MARK: - Memory

    private func readMemory() -> MemorySnapshot? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = VMPageCounts(
            free: UInt64(statistics.free_count),
            active: UInt64(statistics.active_count),
            inactive: UInt64(statistics.inactive_count),
            speculative: UInt64(statistics.speculative_count),
            wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count),
            purgeable: UInt64(statistics.purgeable_count),
            external: UInt64(statistics.external_page_count)
        )
        return MemorySnapshot.make(
            pages: pages,
            pageSize: pageSize,
            total: totalMemory,
            pressure: readMemoryPressure(),
            swap: readSwapUsage()
        )
    }

    private func readMemoryPressure() -> MemoryPressureLevel {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressureLevel(sysctlLevel: level)
    }

    private func readSwapUsage() -> SwapUsage {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return .zero }
        return SwapUsage(total: usage.xsu_total, used: usage.xsu_used, free: usage.xsu_avail)
    }

    // MARK: - Network

    private static let uncountedInterfacePrefixes = ["lo", "gif", "stf", "bridge", "utun", "awdl", "llw", "p2p", "vmnet"]

    /// Loopback, tunnels, bridges, peer-to-peer and VM links are left out so VPN, AirDrop and
    /// virtual-machine traffic is not counted twice on top of the physical interface that
    /// carries it.
    static func isCountedInterface(_ name: String) -> Bool {
        !uncountedInterfacePrefixes.contains { name.hasPrefix($0) }
    }

    private func readLinkCounters() -> [String: LinkCounters] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [:] }
        defer { freeifaddrs(first) }
        var counters: [String: LinkCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let data = entry.pointee.ifa_data else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard Self.isCountedInterface(name) else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = LinkCounters(inbound: stats.ifi_ibytes, outbound: stats.ifi_obytes)
        }
        return counters
    }

    // MARK: - Disk

    /// Cumulative bytes read and written by every block-storage driver, or nil when none
    /// publishes statistics (the disk card then shows dashes).
    private func readDiskCounters() -> TransferDelta? {
        if let drivers = Self.sumStatistics(
            serviceClass: "IOBlockStorageDriver",
            readKey: "Bytes (Read)",
            writeKey: "Bytes (Write)"
        ) {
            return drivers
        }
        return Self.sumStatistics(
            serviceClass: "IOStorage",
            readKey: "Bytes read from block device",
            writeKey: "Bytes written to block device"
        )
    }

    private func readRootVolume() -> VolumeUsage? {
        var status = statfs()
        guard statfs("/", &status) == 0 else { return nil }
        let blockSize = UInt64(status.f_bsize)
        return VolumeUsage(
            total: UInt64(status.f_blocks) * blockSize,
            free: UInt64(status.f_bavail) * blockSize
        )
    }

    // MARK: - GPU

    private func readGPUDevices() -> [GPUDevice] {
        var devices: [GPUDevice] = []
        var index = 0
        Self.forEachService(matching: "IOAccelerator") { properties in
            if let device = GPUDevice(registryProperties: properties, index: index) {
                devices.append(device)
            }
            index += 1
        }
        return devices
    }

    // MARK: - IORegistry helpers

    /// Sums a "Statistics" key pair over every service of `serviceClass`; nil when no service
    /// publishes either key.
    private static func sumStatistics(serviceClass: String, readKey: String, writeKey: String) -> TransferDelta? {
        var found = false
        var totals = TransferDelta.zero
        forEachService(matching: serviceClass) { properties in
            guard let statistics = properties["Statistics"] as? [String: Any] else { return }
            if let read = (statistics[readKey] as? NSNumber)?.uint64Value {
                totals.inbound &+= read
                found = true
            }
            if let written = (statistics[writeKey] as? NSNumber)?.uint64Value {
                totals.outbound &+= written
                found = true
            }
        }
        return found ? totals : nil
    }

    /// Walks the IORegistry services matching `className`, handing each one's properties to
    /// `body` and releasing every object it touched.
    private static func forEachService(matching className: String, _ body: ([String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let properties = copyProperties(of: service) {
                body(properties)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private static func copyProperties(of service: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() else { return nil }
        return (dictionary as NSDictionary) as? [String: Any]
    }
}
