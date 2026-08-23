/// The operating-system interface from which a value was obtained.
///
/// Keep cases specific enough that a rendered value can be traced back to the
/// corresponding row in `docs/FATHOM-DATA-SOURCES.md`.
public enum DataSource: String, Sendable, Equatable, Codable {
    case volumeAvailableCapacityForImportantUsage =
        "URLResourceValues.volumeAvailableCapacityForImportantUsage"
    case statfsAvailableCapacity = "statfs(2).f_bavail × f_bsize"
    case derivedPurgeableCapacity =
        "derived: Finder available − important-usage available"
    case fts = "fts(3)"
    case statLogicalSize = "stat(2).st_size"
    case statAllocatedBlocks = "stat(2).st_blocks × 512"
    case statModificationTime = "stat(2).st_mtimespec"
    case statfsAllocationBlockSize = "fstatfs(2).f_bsize"
    case statDatalessFlag = "stat(2).st_flags & SF_DATALESS"
    case getattrlistCloneIdentity =
        "fgetattrlist(2).ATTR_CMNEXT_CLONEID/CLONE_REFCNT"
    case fcntlPhysicalExtents = "fcntl(2).F_LOG2PHYS_EXT"
    case cloneFamilyAccounting =
        "derived: physical extents + inode/link/clone references"
    case storageTreeAccounting =
        "derived: allocated bytes + clone-family LCA credits"
    case physicalReferenceAccounting =
        "derived: physical extent reference sets"
    case procOpenFileDescriptors =
        "libproc: PROC_PIDLISTFDS/PROC_PIDFDVNODEPATHINFO"
    case seekDataAndHole = "lseek(2).SEEK_DATA/SEEK_HOLE"
    case snapshotManifestDiff = "APFS snapshot manifest diff"
    case fsSnapshotList = "fs_snapshot_list(2)"
    case nvmeSMARTLogPage =
        "IONVMeSMARTInterface.SMARTReadData (NVMe log page 0x02)"
    case nvmeSMARTLifetimeDerivation =
        "derived: NVMe lifetime totals"
    case appleSMCKeyInventory = "AppleSMC key enumeration"
    case appleSMCReadKey = "AppleSMC read-only key read"
    case ioReportChannelInventory =
        "libIOReport.IOReportCopyAllChannels"
    case ioReportSampleDelta =
        "libIOReport.IOReportCreateSamplesDelta"
    case ioReportEnergyDelta =
        "derived: IOReport energy delta ÷ elapsed time"
    case ioHIDTemperatureEvent =
        "IOHIDEventSystemClient temperature event type 15"
    case hostProcessorLoadInfo =
        "host_processor_info(PROCESSOR_CPU_LOAD_INFO) delta"
    case getLoadAverage = "getloadavg(3)"
    case sysctlPerformanceLogicalCPU =
        "sysctl hw.perflevel0.logicalcpu"
    case sysctlEfficiencyLogicalCPU =
        "sysctl hw.perflevel1.logicalcpu"
    case hostVMStatistics64 = "host_statistics64(HOST_VM_INFO64)"
    case sysctlPhysicalMemory = "sysctl hw.memsize"
    case sysctlMachineModel = "sysctl hw.model"
    case statusBarThickness = "NSStatusBar.system.thickness"
    case procPidRusage =
        "proc_pid_rusage(RUSAGE_INFO_CURRENT) user + system time"
    case sysctlSwapUsage = "sysctl vm.swapusage"
    case dispatchMemoryPressure =
        "DispatchSource.makeMemoryPressureSource"
    case ioAcceleratorPerformanceStatistics =
        "IOAccelerator.PerformanceStatistics"
    case ioRegistryGPUCoreCount =
        "IORegistry gpu-core-count"
    case cvDisplayLinkCallbackDelta =
        "CVDisplayLink output callback delta"
    case sysctlNetworkInterfaceList =
        "sysctl NET_RT_IFLIST2 interface counters"
    case getifaddrsNetworkAddresses =
        "getifaddrs(3) active IPv4/IPv6 addresses"
    case scDynamicStoreNetworkState =
        "SCDynamicStore global IPv4 and DNS state"
    case coreWLANAssociationState =
        "CoreWLAN associated SSID and RSSI"
    case ioBlockStorageDriverStatistics =
        "IOBlockStorageDriver.Statistics cumulative byte counters"
    case cloudflareTracePublicAddress =
        "GET cloudflare.com/cdn-cgi/trace: ip + loc"
    case ioBluetoothPairedDevices =
        "IOBluetoothDevice.pairedDevices"
    case ioBluetoothConnectionStatus =
        "IOBluetoothDevice.isConnected"
    case ioBluetoothBatteryPercent =
        "IOBluetooth device BatteryPercent property"
    case persistedStorageHistoryDelta =
        "derived: two completed persisted FATHOM scans"
    case applicationInfoPlist = "Application bundle Info.plist"
    case contentAccessDate = "URLResourceValues.contentAccessDate"
    case exactBundleIDLeftoverMatch =
        "exact bundle identifier path-component match"
    case ubiquitousDownloadingStatus =
        "URLResourceValues.ubiquitousItemDownloadingStatus"
    case ubiquitousAllocatedSize =
        "URLResourceValues.fileAllocatedSize"
    case ubiquitousExcludedFromSync =
        "NSURLUbiquitousItemIsExcludedFromSyncKey"
    case signedBundledChannelMap =
        "bundled Ed25519-verified IOReport channel map"
    case fseventsCausalWindow =
        "FSEventStreamCreate curated-path causal window"
    case fullDiskAccessCanary =
        "open ~/Library/Application Support/com.apple.TCC/TCC.db"
    case serviceManagementAgentStatus =
        "SMAppService.agent(plistName:).status"
    case userNotificationCenter =
        "UNUserNotificationCenter authorization + pending request"
    case storageIndexFTS5 =
        "SQLite FTS5 staged path/component query"
    case persistedDirectoryGrowthDelta =
        "derived: two completed SQLite directory totals within 24 hours"
    case reclaimJournalReplay =
        "append-only reclaim intent/outcome journal replay"
    case volumeIsEncrypted =
        "URLResourceValues.volumeIsEncrypted"
    case persistedSMARTCounterDelta =
        "derived: persisted NVMe SMART counter observations"
}
