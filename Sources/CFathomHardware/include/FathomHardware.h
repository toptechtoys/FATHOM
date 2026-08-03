#ifndef FATHOM_HARDWARE_H
#define FATHOM_HARDWARE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fathom_nvme_smart_data {
    uint8_t critical_warning;
    uint16_t temperature_kelvin;
    uint8_t available_spare;
    uint8_t available_spare_threshold;
    uint8_t percentage_used;
    uint64_t data_units_read_low;
    uint64_t data_units_read_high;
    uint64_t data_units_written_low;
    uint64_t data_units_written_high;
    uint64_t power_cycles_low;
    uint64_t power_cycles_high;
    uint64_t power_on_hours_low;
    uint64_t power_on_hours_high;
    uint64_t unsafe_shutdowns_low;
    uint64_t unsafe_shutdowns_high;
    uint64_t media_errors_low;
    uint64_t media_errors_high;
} fathom_nvme_smart_data;

/// Reads the first NVMe controller that both advertises SMART capability and
/// permits the documented IONVMeSMART user client to open.
///
/// Returns zero on success. On failure, `error_code` receives the IOReturn (or
/// a POSIX-style sentinel) and `controllers_seen` says whether matching
/// hardware existed. No command changes controller state.
int32_t fathom_nvme_smart_read(
    fathom_nvme_smart_data *output,
    int32_t *error_code,
    uint32_t *controllers_seen
);

typedef struct fathom_smc_value {
    uint32_t key;
    uint32_t data_type;
    uint32_t data_size;
    uint8_t bytes[32];
} fathom_smc_value;

/// Copies the key names published by AppleSMC. The returned buffer is owned by
/// the caller and must be passed to fathom_hardware_free. This performs reads
/// only; it never invokes an SMC write command.
int32_t fathom_smc_copy_keys(
    uint32_t **keys,
    uint32_t *count,
    int32_t *error_code
);

/// Reads one SMC key selected from the enumerated inventory.
int32_t fathom_smc_read_key(
    uint32_t key,
    fathom_smc_value *output,
    int32_t *error_code
);

/// Decodes only documented-by-convention numeric SMC wire formats. Unknown
/// formats return failure rather than being guessed.
int32_t fathom_smc_decode_numeric(
    const fathom_smc_value *value,
    double *output
);

void fathom_hardware_free(void *pointer);

/// Serializes the runtime IOReport channel inventory as a property-list array
/// of group/subgroup/channel/unit dictionaries. Private symbols are resolved
/// dynamically so their absence produces an explicit error instead of a load
/// failure on unsupported Macs.
int32_t fathom_ioreport_copy_channel_inventory(
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
);

typedef void *fathom_ioreport_sampler;

/// Creates one subscription spanning only the groups FATHOM consumes.
int32_t fathom_ioreport_sampler_create(
    fathom_ioreport_sampler *sampler,
    int32_t *error_code
);

/// Captures the first sample used as the delta baseline.
int32_t fathom_ioreport_sampler_prime(
    fathom_ioreport_sampler sampler,
    int32_t *error_code
);

/// Captures a delta and serializes its channel values as a binary plist.
int32_t fathom_ioreport_sampler_copy_delta(
    fathom_ioreport_sampler sampler,
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
);

void fathom_ioreport_sampler_destroy(fathom_ioreport_sampler sampler);

/// Reads temperature events (usage page 0xff00, usage 5, event type 15) from
/// IOHIDEventSystem and serializes name/value dictionaries as a binary plist.
int32_t fathom_iohid_copy_temperature_sensors(
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
);

#define FATHOM_MAX_CPU_CORES 64

typedef struct fathom_cpu_ticks {
    uint32_t core_count;
    uint64_t user[FATHOM_MAX_CPU_CORES];
    uint64_t system[FATHOM_MAX_CPU_CORES];
    uint64_t idle[FATHOM_MAX_CPU_CORES];
    uint64_t nice[FATHOM_MAX_CPU_CORES];
} fathom_cpu_ticks;

int32_t fathom_cpu_read_ticks(
    fathom_cpu_ticks *output,
    int32_t *error_code
);

typedef struct fathom_memory_counters {
    uint64_t page_size;
    uint64_t free_pages;
    uint64_t active_pages;
    uint64_t inactive_pages;
    uint64_t speculative_pages;
    uint64_t wired_pages;
    uint64_t compressed_pages;
    uint64_t purgeable_pages;
    uint64_t swap_used_bytes;
    uint64_t swap_total_bytes;
} fathom_memory_counters;

int32_t fathom_memory_read_counters(
    fathom_memory_counters *output,
    int32_t *error_code
);

enum {
    FATHOM_GPU_DEVICE_UTILIZATION = 1u << 0,
    FATHOM_GPU_RENDERER_UTILIZATION = 1u << 1,
    FATHOM_GPU_TILER_UTILIZATION = 1u << 2,
    FATHOM_GPU_CORE_COUNT = 1u << 3
};

typedef struct fathom_gpu_counters {
    uint32_t published_fields;
    double device_utilization_percent;
    double renderer_utilization_percent;
    double tiler_utilization_percent;
    uint64_t core_count;
} fathom_gpu_counters;

int32_t fathom_gpu_read_counters(
    fathom_gpu_counters *output,
    int32_t *error_code
);

#define FATHOM_MAX_NETWORK_INTERFACES 64
#define FATHOM_NETWORK_NAME_LENGTH 32

typedef struct fathom_network_interface {
    char name[FATHOM_NETWORK_NAME_LENGTH];
    uint64_t received_bytes;
    uint64_t sent_bytes;
    uint32_t flags;
} fathom_network_interface;

typedef struct fathom_network_counters {
    uint32_t interface_count;
    fathom_network_interface interfaces[FATHOM_MAX_NETWORK_INTERFACES];
} fathom_network_counters;

int32_t fathom_network_read_counters(
    fathom_network_counters *output,
    int32_t *error_code
);

#define FATHOM_MAX_NETWORK_ADDRESSES 128
#define FATHOM_NETWORK_ADDRESS_LENGTH 46

typedef struct fathom_network_address {
    char interface_name[FATHOM_NETWORK_NAME_LENGTH];
    char address[FATHOM_NETWORK_ADDRESS_LENGTH];
    uint8_t family;
} fathom_network_address;

typedef struct fathom_network_addresses {
    uint32_t address_count;
    fathom_network_address addresses[FATHOM_MAX_NETWORK_ADDRESSES];
} fathom_network_addresses;

int32_t fathom_network_read_addresses(
    fathom_network_addresses *output,
    int32_t *error_code
);

typedef struct fathom_disk_counters {
    uint64_t bytes_read;
    uint64_t bytes_written;
    uint32_t drivers_seen;
    uint32_t drivers_publishing_statistics;
} fathom_disk_counters;

/// Aggregates the cumulative byte counters published by
/// IOBlockStorageDriver/Statistics. This is a read-only IORegistry query.
int32_t fathom_disk_read_counters(
    fathom_disk_counters *output,
    int32_t *error_code
);

typedef void *fathom_display_refresh_sampler;

int32_t fathom_display_refresh_sampler_create(
    fathom_display_refresh_sampler *sampler,
    int32_t *error_code
);

uint64_t fathom_display_refresh_sampler_count(
    fathom_display_refresh_sampler sampler
);

void fathom_display_refresh_sampler_destroy(
    fathom_display_refresh_sampler sampler
);

#ifdef __cplusplus
}
#endif

#endif
