import Darwin
import Foundation
import IOKit.ps
import Observation

// MARK: - SystemStatsSnapshot
/// Six jauges, toutes lues via des API publiques — aucune n'exige de
/// permission ni d'entitlement, contrairement a la luminosite (§3) ou
/// l'agenda (§ CalendarService).
struct SystemStatsSnapshot: Equatable, Sendable {
    /// 0…1.
    let cpuUsage: Double
    /// 0…1.
    let memoryUsage: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    /// 0…1 : part du disque de demarrage occupee.
    let diskUsage: Double
    let diskFreeBytes: UInt64
    let diskTotalBytes: UInt64
    /// Octets/seconde, calcules par difference entre deux releves.
    let networkBytesPerSecond: Double
    /// 0…100, ou `nil` sur un Mac de bureau (§ PowerSnapshot, meme convention).
    let batteryPercentage: Int?
}

// MARK: - SystemStatsService
/// Six jauges systeme (CPU, memoire, disque, reseau, batterie, espace libre),
/// rafraichies a intervalle court : contrairement a la meteo ou l'agenda,
/// ces valeurs bougent seconde par seconde et l'onglet n'a de sens que
/// visible — `start()`/`stop()` suivent donc l'affichage de l'onglet, pas
/// le cycle de vie du panneau entier.
@MainActor
@Observable
final class SystemStatsService {

    private(set) var snapshot: SystemStatsSnapshot?

    private var refreshTask: Task<Void, Never>?
    private let refreshInterval: Duration = .seconds(2)

    /// Compteurs bruts du releve precedent, pour deriver un debit reseau.
    private var lastNetworkBytes: UInt64?
    private var lastNetworkSampleDate: Date?
    /// Charge CPU brute du releve precedent (ticks), pour deriver un taux
    /// d'usage entre deux instantanes plutot qu'une moyenne depuis le boot.
    private var lastCPUTicks: (used: UInt64, total: UInt64)?

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        lastNetworkBytes = nil
        lastNetworkSampleDate = nil
        lastCPUTicks = nil
    }

    private func refresh() {
        let memory = Self.memoryUsage()
        let disk = Self.diskUsage()
        snapshot = SystemStatsSnapshot(
            cpuUsage: cpuUsage(),
            memoryUsage: memory.usage,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            diskUsage: disk.usage,
            diskFreeBytes: disk.free,
            diskTotalBytes: disk.total,
            networkBytesPerSecond: networkBytesPerSecond(),
            batteryPercentage: Self.batteryPercentage()
        )
    }

    // MARK: CPU

    /// `host_processor_info` renvoie les ticks cumules depuis le demarrage ;
    /// l'usage instantane est la part de ticks "actifs" DANS L'INTERVALLE
    /// ecoule depuis le releve precedent, pas une moyenne depuis le boot.
    private func cpuUsage() -> Double {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount
        )
        guard result == KERN_SUCCESS, let infoArray else {
            lastCPUTicks = nil
            return 0
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: infoArray),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let ticks = infoArray.withMemoryRebound(
            to: integer_t.self, capacity: Int(infoCount)
        ) { pointer in
            (0..<Int(cpuCount)).reduce(into: (used: UInt64(0), total: UInt64(0))) { sum, core in
                let base = core * Int(CPU_STATE_MAX)
                let user = UInt64(pointer[base + Int(CPU_STATE_USER)])
                let system = UInt64(pointer[base + Int(CPU_STATE_SYSTEM)])
                let nice = UInt64(pointer[base + Int(CPU_STATE_NICE)])
                let idle = UInt64(pointer[base + Int(CPU_STATE_IDLE)])
                sum.used += user + system + nice
                sum.total += user + system + nice + idle
            }
        }

        defer { lastCPUTicks = ticks }
        guard let previous = lastCPUTicks else { return 0 }

        let usedDelta = Double(ticks.used &- previous.used)
        let totalDelta = Double(ticks.total &- previous.total)
        guard totalDelta > 0 else { return 0 }
        return min(max(usedDelta / totalDelta, 0), 1)
    }

    // MARK: Memoire

    private static func memoryUsage() -> (usage: Double, used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0) }

        let pageSize = UInt64(getpagesize())
        let free = UInt64(stats.free_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let used = active + inactive + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return (0, used, 0) }
        _ = free
        return (Double(used) / Double(total), used, total)
    }

    // MARK: Disque

    private static func diskUsage() -> (usage: Double, free: UInt64, total: UInt64) {
        guard
            let values = try? URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            ),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage
        else { return (0, 0, 0) }

        let totalBytes = UInt64(total)
        let freeBytes = UInt64(max(free, 0))
        guard totalBytes > 0 else { return (0, freeBytes, 0) }
        let used = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return (Double(used) / Double(totalBytes), freeBytes, totalBytes)
    }

    // MARK: Reseau

    /// Somme des octets entrants+sortants sur toutes les interfaces actives
    /// (hors loopback), differenciee entre deux releves pour un debit.
    private func networkBytesPerSecond() -> Double {
        let now = Date()
        let total = Self.totalNetworkBytes()

        defer {
            lastNetworkBytes = total
            lastNetworkSampleDate = now
        }
        guard let previous = lastNetworkBytes, let previousDate = lastNetworkSampleDate else {
            return 0
        }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0, total >= previous else { return 0 }
        return Double(total - previous) / elapsed
    }

    private static func totalNetworkBytes() -> UInt64 {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return 0 }
        defer { freeifaddrs(first) }

        var sum: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            // Boucle locale exclue : elle ne reflete aucun trafic reseau reel.
            guard name != "lo0", let data = entry.pointee.ifa_data else { continue }
            let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
            sum += UInt64(networkData.ifi_ibytes) + UInt64(networkData.ifi_obytes)
        }
        return sum
    }

    // MARK: Batterie

    /// Reutilise la meme source que `PowerService`, en lecture ponctuelle :
    /// un second `IOPSNotificationCreateRunLoopSource` pour un simple
    /// pourcentage deja disponible ailleurs serait une duplication inutile.
    private static func batteryPercentage() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }
            return Int((Double(capacity) / Double(maximum) * 100).rounded())
        }
        return nil
    }
}
