#include "FathomHardware.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreVideo/CoreVideo.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <dlfcn.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <sys/sysctl.h>

typedef struct fathom_smc_version {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} fathom_smc_version;

typedef struct fathom_smc_power_limit {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_limit;
    uint32_t gpu_limit;
    uint32_t memory_limit;
} fathom_smc_power_limit;

typedef struct fathom_smc_key_info {
    uint32_t data_size;
    uint32_t data_type;
    uint8_t data_attributes;
} fathom_smc_key_info;

typedef struct fathom_smc_key_data {
    uint32_t key;
    fathom_smc_version version;
    fathom_smc_power_limit power_limit;
    fathom_smc_key_info key_info;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} fathom_smc_key_data;

enum {
    fathom_smc_selector = 2,
    fathom_smc_command_read_bytes = 5,
    fathom_smc_command_read_index = 8,
    fathom_smc_command_read_key_info = 9
};

static uint32_t fathom_fourcc(
    char a,
    char b,
    char c,
    char d
) {
    return ((uint32_t)(uint8_t)a << 24) |
        ((uint32_t)(uint8_t)b << 16) |
        ((uint32_t)(uint8_t)c << 8) |
        (uint32_t)(uint8_t)d;
}

static uint32_t fathom_read_be32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0] << 24) |
        ((uint32_t)bytes[1] << 16) |
        ((uint32_t)bytes[2] << 8) |
        (uint32_t)bytes[3];
}

static kern_return_t fathom_smc_open(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSMC")
    );
    if (service == IO_OBJECT_NULL) {
        return kIOReturnNotFound;
    }
    kern_return_t result = IOServiceOpen(
        service,
        mach_task_self(),
        0,
        connection
    );
    IOObjectRelease(service);
    return result;
}

static kern_return_t fathom_smc_call(
    io_connect_t connection,
    fathom_smc_key_data *input,
    fathom_smc_key_data *output
) {
    size_t output_size = sizeof(*output);
    memset(output, 0, sizeof(*output));
    return IOConnectCallStructMethod(
        connection,
        fathom_smc_selector,
        input,
        sizeof(*input),
        output,
        &output_size
    );
}

static kern_return_t fathom_smc_read(
    io_connect_t connection,
    uint32_t key,
    fathom_smc_key_data *output
) {
    fathom_smc_key_data input;
    fathom_smc_key_data key_info;
    memset(&input, 0, sizeof(input));
    input.key = key;
    input.data8 = fathom_smc_command_read_key_info;
    kern_return_t result = fathom_smc_call(
        connection,
        &input,
        &key_info
    );
    if (result != KERN_SUCCESS || key_info.result != 0) {
        return result == KERN_SUCCESS
            ? kIOReturnNotFound
            : result;
    }

    memset(&input, 0, sizeof(input));
    input.key = key;
    input.key_info.data_size = key_info.key_info.data_size;
    input.data8 = fathom_smc_command_read_bytes;
    result = fathom_smc_call(connection, &input, output);
    if (result == KERN_SUCCESS) {
        output->key_info = key_info.key_info;
    }
    return result;
}

static void fathom_copy_smart(
    const NVMeSMARTData *source,
    fathom_nvme_smart_data *destination
) {
    memset(destination, 0, sizeof(*destination));
    destination->critical_warning = source->CRITICAL_WARNING;
    destination->temperature_kelvin = source->TEMPERATURE;
    destination->available_spare = source->AVAILABLE_SPARE;
    destination->available_spare_threshold =
        source->AVAILABLE_SPARE_THRESHOLD;
    destination->percentage_used = source->PERCENTAGE_USED;
    destination->data_units_read_low = source->DATA_UNITS_READ[0];
    destination->data_units_read_high = source->DATA_UNITS_READ[1];
    destination->data_units_written_low = source->DATA_UNITS_WRITTEN[0];
    destination->data_units_written_high = source->DATA_UNITS_WRITTEN[1];
    destination->power_cycles_low = source->POWER_CYCLES[0];
    destination->power_cycles_high = source->POWER_CYCLES[1];
    destination->power_on_hours_low = source->POWER_ON_HOURS[0];
    destination->power_on_hours_high = source->POWER_ON_HOURS[1];
    destination->unsafe_shutdowns_low = source->UNSAFE_SHUTDOWNS[0];
    destination->unsafe_shutdowns_high = source->UNSAFE_SHUTDOWNS[1];
    destination->media_errors_low = source->MEDIA_ERRORS[0];
    destination->media_errors_high = source->MEDIA_ERRORS[1];
}

int32_t fathom_nvme_smart_read(
    fathom_nvme_smart_data *output,
    int32_t *error_code,
    uint32_t *controllers_seen
) {
    if (output == NULL || error_code == NULL || controllers_seen == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = (int32_t)kIOReturnNotFound;
    *controllers_seen = 0;

    CFMutableDictionaryRef matching = IOServiceMatching("IONVMeController");
    if (matching == NULL) {
        *error_code = (int32_t)kIOReturnNoMemory;
        return -1;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        matching,
        &iterator
    );
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }

    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        *controllers_seen += 1;
        CFTypeRef capable = IORegistryEntryCreateCFProperty(
            service,
            CFSTR(kIOPropertyNVMeSMARTCapableKey),
            kCFAllocatorDefault,
            0
        );
        Boolean is_capable = capable == NULL ||
            (CFGetTypeID(capable) == CFBooleanGetTypeID() &&
             CFBooleanGetValue((CFBooleanRef)capable));
        if (capable != NULL) {
            CFRelease(capable);
        }
        if (!is_capable) {
            IOObjectRelease(service);
            continue;
        }

        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        result = IOCreatePlugInInterfaceForService(
            service,
            kIONVMeSMARTUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        );
        IOObjectRelease(service);
        if (result != KERN_SUCCESS || plugin == NULL) {
            *error_code = (int32_t)result;
            continue;
        }

        IONVMeSMARTInterface **smart = NULL;
        HRESULT query = (*plugin)->QueryInterface(
            plugin,
            CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
            (LPVOID *)&smart
        );
        if (query != S_OK || smart == NULL) {
            *error_code = (int32_t)query;
            IODestroyPlugInInterface(plugin);
            continue;
        }

        NVMeSMARTData data;
        memset(&data, 0, sizeof(data));
        IOReturn read_result = (*smart)->SMARTReadData(smart, &data);
        (*smart)->Release(smart);
        IODestroyPlugInInterface(plugin);
        if (read_result == kIOReturnSuccess) {
            fathom_copy_smart(&data, output);
            *error_code = 0;
            IOObjectRelease(iterator);
            return 0;
        }
        *error_code = (int32_t)read_result;
    }

    IOObjectRelease(iterator);
    return -1;
}

int32_t fathom_smc_copy_keys(
    uint32_t **keys,
    uint32_t *count,
    int32_t *error_code
) {
    if (keys == NULL || count == NULL || error_code == NULL) {
        return -1;
    }
    *keys = NULL;
    *count = 0;
    *error_code = 0;

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = fathom_smc_open(&connection);
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }

    fathom_smc_key_data count_data;
    result = fathom_smc_read(
        connection,
        fathom_fourcc('#', 'K', 'E', 'Y'),
        &count_data
    );
    if (result != KERN_SUCCESS || count_data.key_info.data_size < 4) {
        IOServiceClose(connection);
        *error_code = (int32_t)result;
        return -1;
    }
    uint32_t key_count = fathom_read_be32(count_data.bytes);
    if (key_count == 0 || key_count > 65536) {
        IOServiceClose(connection);
        *error_code = (int32_t)kIOReturnBadArgument;
        return -1;
    }
    uint32_t *buffer = calloc(key_count, sizeof(uint32_t));
    if (buffer == NULL) {
        IOServiceClose(connection);
        *error_code = (int32_t)kIOReturnNoMemory;
        return -1;
    }

    for (uint32_t index = 0; index < key_count; index += 1) {
        fathom_smc_key_data input;
        fathom_smc_key_data output;
        memset(&input, 0, sizeof(input));
        input.data8 = fathom_smc_command_read_index;
        input.data32 = index;
        result = fathom_smc_call(connection, &input, &output);
        if (result != KERN_SUCCESS || output.result != 0) {
            free(buffer);
            IOServiceClose(connection);
            *error_code = (int32_t)(
                result == KERN_SUCCESS ? kIOReturnNotFound : result
            );
            return -1;
        }
        buffer[index] = output.key;
    }
    IOServiceClose(connection);
    *keys = buffer;
    *count = key_count;
    return 0;
}

int32_t fathom_smc_read_key(
    uint32_t key,
    fathom_smc_value *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = fathom_smc_open(&connection);
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }

    fathom_smc_key_data data;
    result = fathom_smc_read(connection, key, &data);
    IOServiceClose(connection);
    if (result != KERN_SUCCESS || data.result != 0) {
        *error_code = (int32_t)(
            result == KERN_SUCCESS ? kIOReturnNotFound : result
        );
        return -1;
    }
    output->key = key;
    output->data_type = data.key_info.data_type;
    output->data_size = data.key_info.data_size;
    if (output->data_size > sizeof(output->bytes)) {
        *error_code = (int32_t)kIOReturnMessageTooLarge;
        return -1;
    }
    memcpy(output->bytes, data.bytes, output->data_size);
    return 0;
}

void fathom_hardware_free(void *pointer) {
    free(pointer);
}

typedef CFDictionaryRef (*fathom_ioreport_copy_all_fn)(uint64_t, uint64_t);
typedef CFStringRef (*fathom_ioreport_channel_string_fn)(CFDictionaryRef);
typedef CFDictionaryRef (*fathom_ioreport_copy_group_fn)(
    CFStringRef,
    CFStringRef,
    uint64_t,
    uint64_t,
    uint64_t
);
typedef void (*fathom_ioreport_merge_fn)(
    CFMutableDictionaryRef,
    CFDictionaryRef,
    CFTypeRef
);
typedef CFTypeRef (*fathom_ioreport_create_subscription_fn)(
    const void *,
    CFMutableDictionaryRef,
    CFMutableDictionaryRef *,
    uint64_t,
    CFTypeRef
);
typedef CFDictionaryRef (*fathom_ioreport_create_samples_fn)(
    CFTypeRef,
    CFMutableDictionaryRef,
    CFTypeRef
);
typedef CFDictionaryRef (*fathom_ioreport_create_delta_fn)(
    CFDictionaryRef,
    CFDictionaryRef,
    CFTypeRef
);
typedef int (*fathom_ioreport_get_format_fn)(CFDictionaryRef);
typedef int64_t (*fathom_ioreport_simple_value_fn)(CFDictionaryRef, int);
typedef int (*fathom_ioreport_state_count_fn)(CFDictionaryRef);
typedef CFStringRef (*fathom_ioreport_state_name_fn)(CFDictionaryRef, int);
typedef int64_t (*fathom_ioreport_state_residency_fn)(CFDictionaryRef, int);

typedef struct fathom_ioreport_sampler_state {
    void *library;
    CFTypeRef subscription;
    CFMutableDictionaryRef subscribed_channels;
    CFDictionaryRef previous_sample;
    fathom_ioreport_create_samples_fn create_samples;
    fathom_ioreport_create_delta_fn create_delta;
    fathom_ioreport_channel_string_fn get_group;
    fathom_ioreport_channel_string_fn get_subgroup;
    fathom_ioreport_channel_string_fn get_channel;
    fathom_ioreport_channel_string_fn get_unit;
    fathom_ioreport_get_format_fn get_format;
    fathom_ioreport_simple_value_fn simple_value;
    fathom_ioreport_state_count_fn state_count;
    fathom_ioreport_state_name_fn state_name;
    fathom_ioreport_state_residency_fn state_residency;
} fathom_ioreport_sampler_state;

static void *fathom_ioreport_symbol(void *library, const char *name) {
    return library == NULL ? NULL : dlsym(library, name);
}

static CFArrayRef fathom_ioreport_channel_array(CFDictionaryRef report) {
    if (report == NULL) {
        return NULL;
    }
    CFTypeRef value = CFDictionaryGetValue(
        report,
        CFSTR("IOReportChannels")
    );
    if (value == NULL || CFGetTypeID(value) != CFArrayGetTypeID()) {
        return NULL;
    }
    return (CFArrayRef)value;
}

int32_t fathom_ioreport_copy_channel_inventory(
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
) {
    if (bytes == NULL || length == NULL || error_code == NULL) {
        return -1;
    }
    *bytes = NULL;
    *length = 0;
    *error_code = 0;

    void *library = dlopen(
        "/usr/lib/libIOReport.dylib",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (library == NULL) {
        *error_code = 1;
        return -1;
    }
    fathom_ioreport_copy_all_fn copy_all =
        (fathom_ioreport_copy_all_fn)dlsym(
            library,
            "IOReportCopyAllChannels"
        );
    fathom_ioreport_channel_string_fn get_group =
        (fathom_ioreport_channel_string_fn)dlsym(
            library,
            "IOReportChannelGetGroup"
        );
    fathom_ioreport_channel_string_fn get_subgroup =
        (fathom_ioreport_channel_string_fn)dlsym(
            library,
            "IOReportChannelGetSubGroup"
        );
    fathom_ioreport_channel_string_fn get_channel =
        (fathom_ioreport_channel_string_fn)dlsym(
            library,
            "IOReportChannelGetChannelName"
        );
    fathom_ioreport_channel_string_fn get_unit =
        (fathom_ioreport_channel_string_fn)dlsym(
            library,
            "IOReportChannelGetUnitLabel"
        );
    if (copy_all == NULL || get_group == NULL || get_subgroup == NULL ||
        get_channel == NULL || get_unit == NULL) {
        dlclose(library);
        *error_code = 2;
        return -1;
    }

    CFDictionaryRef channels = copy_all(0, 0);
    if (channels == NULL) {
        dlclose(library);
        *error_code = 3;
        return -1;
    }
    CFArrayRef channel_array = fathom_ioreport_channel_array(channels);
    if (channel_array == NULL) {
        CFRelease(channels);
        dlclose(library);
        *error_code = 4;
        return -1;
    }

    CFIndex count = CFArrayGetCount(channel_array);
    CFMutableArrayRef inventory = CFArrayCreateMutable(
        kCFAllocatorDefault,
        count,
        &kCFTypeArrayCallBacks
    );
    if (inventory == NULL) {
        CFRelease(channels);
        dlclose(library);
        *error_code = 5;
        return -1;
    }
    const void *keys[] = {
        CFSTR("group"),
        CFSTR("subgroup"),
        CFSTR("channel"),
        CFSTR("unit")
    };
    for (CFIndex index = 0; index < count; index += 1) {
        CFTypeRef value = CFArrayGetValueAtIndex(channel_array, index);
        if (value == NULL ||
            CFGetTypeID(value) != CFDictionaryGetTypeID()) {
            continue;
        }
        CFDictionaryRef channel = (CFDictionaryRef)value;
        CFStringRef group = get_group(channel);
        CFStringRef subgroup = get_subgroup(channel);
        CFStringRef name = get_channel(channel);
        CFStringRef unit = get_unit(channel);
        const void *values[] = {
            group == NULL ? CFSTR("") : group,
            subgroup == NULL ? CFSTR("") : subgroup,
            name == NULL ? CFSTR("") : name,
            unit == NULL ? CFSTR("") : unit
        };
        CFDictionaryRef item = CFDictionaryCreate(
            kCFAllocatorDefault,
            keys,
            values,
            4,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        if (item != NULL) {
            CFArrayAppendValue(inventory, item);
            CFRelease(item);
        }
    }

    CFErrorRef serialization_error = NULL;
    CFDataRef data = CFPropertyListCreateData(
        kCFAllocatorDefault,
        inventory,
        kCFPropertyListBinaryFormat_v1_0,
        0,
        &serialization_error
    );
    CFRelease(inventory);
    CFRelease(channels);
    dlclose(library);
    if (serialization_error != NULL) {
        CFRelease(serialization_error);
    }
    if (data == NULL) {
        *error_code = 6;
        return -1;
    }
    CFIndex data_length = CFDataGetLength(data);
    uint8_t *buffer = malloc((size_t)data_length);
    if (buffer == NULL) {
        CFRelease(data);
        *error_code = 7;
        return -1;
    }
    memcpy(buffer, CFDataGetBytePtr(data), (size_t)data_length);
    CFRelease(data);
    *bytes = buffer;
    *length = (uint64_t)data_length;
    return 0;
}

int32_t fathom_ioreport_sampler_create(
    fathom_ioreport_sampler *sampler,
    int32_t *error_code
) {
    if (sampler == NULL || error_code == NULL) {
        return -1;
    }
    *sampler = NULL;
    *error_code = 0;
    void *library = dlopen(
        "/usr/lib/libIOReport.dylib",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (library == NULL) {
        *error_code = 1;
        return -1;
    }
    fathom_ioreport_copy_group_fn copy_group =
        (fathom_ioreport_copy_group_fn)fathom_ioreport_symbol(
            library,
            "IOReportCopyChannelsInGroup"
        );
    fathom_ioreport_merge_fn merge =
        (fathom_ioreport_merge_fn)fathom_ioreport_symbol(
            library,
            "IOReportMergeChannels"
        );
    fathom_ioreport_create_subscription_fn create_subscription =
        (fathom_ioreport_create_subscription_fn)fathom_ioreport_symbol(
            library,
            "IOReportCreateSubscription"
        );
    if (copy_group == NULL || merge == NULL || create_subscription == NULL) {
        dlclose(library);
        *error_code = 2;
        return -1;
    }

    CFStringRef groups[] = {
        CFSTR("Energy Model"),
        CFSTR("CPU Stats"),
        CFSTR("GPU Stats"),
        CFSTR("AMC Stats"),
        CFSTR("NVMe")
    };
    CFMutableDictionaryRef desired = NULL;
    for (size_t index = 0; index < sizeof(groups) / sizeof(groups[0]);
         index += 1) {
        CFDictionaryRef channels = copy_group(groups[index], NULL, 0, 0, 0);
        if (channels == NULL) {
            continue;
        }
        if (desired == NULL) {
            desired = CFDictionaryCreateMutableCopy(
                kCFAllocatorDefault,
                0,
                channels
            );
        } else {
            merge(desired, channels, NULL);
        }
        CFRelease(channels);
    }
    if (desired == NULL || CFDictionaryGetCount(desired) == 0) {
        if (desired != NULL) {
            CFRelease(desired);
        }
        dlclose(library);
        *error_code = 3;
        return -1;
    }

    CFMutableDictionaryRef subscribed = NULL;
    CFTypeRef subscription = create_subscription(
        NULL,
        desired,
        &subscribed,
        0,
        NULL
    );
    CFRelease(desired);
    if (subscription == NULL || subscribed == NULL) {
        if (subscription != NULL) {
            CFRelease(subscription);
        }
        if (subscribed != NULL) {
            CFRelease(subscribed);
        }
        dlclose(library);
        *error_code = 4;
        return -1;
    }

    fathom_ioreport_sampler_state *state = calloc(1, sizeof(*state));
    if (state == NULL) {
        CFRelease(subscription);
        CFRelease(subscribed);
        dlclose(library);
        *error_code = 5;
        return -1;
    }
    state->library = library;
    state->subscription = subscription;
    state->subscribed_channels = subscribed;
#define FATHOM_IOREPORT_LOAD(field, type, symbol) \
    state->field = (type)fathom_ioreport_symbol(library, symbol)
    FATHOM_IOREPORT_LOAD(
        create_samples,
        fathom_ioreport_create_samples_fn,
        "IOReportCreateSamples"
    );
    FATHOM_IOREPORT_LOAD(
        create_delta,
        fathom_ioreport_create_delta_fn,
        "IOReportCreateSamplesDelta"
    );
    FATHOM_IOREPORT_LOAD(get_group, fathom_ioreport_channel_string_fn,
        "IOReportChannelGetGroup");
    FATHOM_IOREPORT_LOAD(get_subgroup, fathom_ioreport_channel_string_fn,
        "IOReportChannelGetSubGroup");
    FATHOM_IOREPORT_LOAD(get_channel, fathom_ioreport_channel_string_fn,
        "IOReportChannelGetChannelName");
    FATHOM_IOREPORT_LOAD(get_unit, fathom_ioreport_channel_string_fn,
        "IOReportChannelGetUnitLabel");
    FATHOM_IOREPORT_LOAD(get_format, fathom_ioreport_get_format_fn,
        "IOReportChannelGetFormat");
    FATHOM_IOREPORT_LOAD(simple_value, fathom_ioreport_simple_value_fn,
        "IOReportSimpleGetIntegerValue");
    FATHOM_IOREPORT_LOAD(state_count, fathom_ioreport_state_count_fn,
        "IOReportStateGetCount");
    FATHOM_IOREPORT_LOAD(state_name, fathom_ioreport_state_name_fn,
        "IOReportStateGetNameForIndex");
    FATHOM_IOREPORT_LOAD(state_residency, fathom_ioreport_state_residency_fn,
        "IOReportStateGetResidency");
#undef FATHOM_IOREPORT_LOAD
    if (state->create_samples == NULL || state->create_delta == NULL ||
        state->get_group == NULL || state->get_subgroup == NULL ||
        state->get_channel == NULL || state->get_unit == NULL ||
        state->get_format == NULL || state->simple_value == NULL ||
        state->state_count == NULL || state->state_name == NULL ||
        state->state_residency == NULL) {
        fathom_ioreport_sampler_destroy(state);
        *error_code = 6;
        return -1;
    }
    *sampler = state;
    return 0;
}

int32_t fathom_ioreport_sampler_prime(
    fathom_ioreport_sampler sampler,
    int32_t *error_code
) {
    fathom_ioreport_sampler_state *state = sampler;
    if (state == NULL || error_code == NULL) {
        return -1;
    }
    if (state->previous_sample != NULL) {
        CFRelease(state->previous_sample);
    }
    state->previous_sample = state->create_samples(
        state->subscription,
        state->subscribed_channels,
        NULL
    );
    if (state->previous_sample == NULL) {
        *error_code = 7;
        return -1;
    }
    *error_code = 0;
    return 0;
}

static void fathom_dictionary_set_number(
    CFMutableDictionaryRef dictionary,
    CFStringRef key,
    int64_t value
) {
    CFNumberRef number = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt64Type,
        &value
    );
    if (number != NULL) {
        CFDictionarySetValue(dictionary, key, number);
        CFRelease(number);
    }
}

int32_t fathom_ioreport_sampler_copy_delta(
    fathom_ioreport_sampler sampler,
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
) {
    fathom_ioreport_sampler_state *state = sampler;
    if (state == NULL || bytes == NULL || length == NULL ||
        error_code == NULL || state->previous_sample == NULL) {
        return -1;
    }
    *bytes = NULL;
    *length = 0;
    CFDictionaryRef current = state->create_samples(
        state->subscription,
        state->subscribed_channels,
        NULL
    );
    if (current == NULL) {
        *error_code = 8;
        return -1;
    }
    CFDictionaryRef delta = state->create_delta(
        state->previous_sample,
        current,
        NULL
    );
    CFRelease(state->previous_sample);
    state->previous_sample = current;
    CFArrayRef channels = fathom_ioreport_channel_array(delta);
    if (delta == NULL || channels == NULL) {
        if (delta != NULL) {
            CFRelease(delta);
        }
        *error_code = 9;
        return -1;
    }

    CFMutableArrayRef output = CFArrayCreateMutable(
        kCFAllocatorDefault,
        CFArrayGetCount(channels),
        &kCFTypeArrayCallBacks
    );
    for (CFIndex index = 0; index < CFArrayGetCount(channels); index += 1) {
        CFDictionaryRef channel = (CFDictionaryRef)
            CFArrayGetValueAtIndex(channels, index);
        if (channel == NULL ||
            CFGetTypeID(channel) != CFDictionaryGetTypeID()) {
            continue;
        }
        CFMutableDictionaryRef item = CFDictionaryCreateMutable(
            kCFAllocatorDefault,
            0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        CFStringRef group = state->get_group(channel);
        CFStringRef subgroup = state->get_subgroup(channel);
        CFStringRef name = state->get_channel(channel);
        CFStringRef unit = state->get_unit(channel);
        CFDictionarySetValue(item, CFSTR("group"),
            group == NULL ? CFSTR("") : group);
        CFDictionarySetValue(item, CFSTR("subgroup"),
            subgroup == NULL ? CFSTR("") : subgroup);
        CFDictionarySetValue(item, CFSTR("channel"),
            name == NULL ? CFSTR("") : name);
        CFDictionarySetValue(item, CFSTR("unit"),
            unit == NULL ? CFSTR("") : unit);
        int format = state->get_format(channel);
        fathom_dictionary_set_number(item, CFSTR("format"), format);
        if (format == 1) {
            fathom_dictionary_set_number(
                item,
                CFSTR("integerValue"),
                state->simple_value(channel, 0)
            );
        }

        int state_count = state->state_count(channel);
        if (state_count > 0 && state_count < 4096) {
            CFMutableArrayRef states = CFArrayCreateMutable(
                kCFAllocatorDefault,
                state_count,
                &kCFTypeArrayCallBacks
            );
            for (int state_index = 0; state_index < state_count;
                 state_index += 1) {
                CFMutableDictionaryRef state_item = CFDictionaryCreateMutable(
                    kCFAllocatorDefault,
                    0,
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks
                );
                CFStringRef state_name = state->state_name(
                    channel,
                    state_index
                );
                CFDictionarySetValue(
                    state_item,
                    CFSTR("name"),
                    state_name == NULL ? CFSTR("") : state_name
                );
                fathom_dictionary_set_number(
                    state_item,
                    CFSTR("residency"),
                    state->state_residency(channel, state_index)
                );
                CFArrayAppendValue(states, state_item);
                CFRelease(state_item);
            }
            CFDictionarySetValue(item, CFSTR("states"), states);
            CFRelease(states);
        }
        CFArrayAppendValue(output, item);
        CFRelease(item);
    }
    CFRelease(delta);

    CFErrorRef serialization_error = NULL;
    CFDataRef data = CFPropertyListCreateData(
        kCFAllocatorDefault,
        output,
        kCFPropertyListBinaryFormat_v1_0,
        0,
        &serialization_error
    );
    CFRelease(output);
    if (serialization_error != NULL) {
        CFRelease(serialization_error);
    }
    if (data == NULL) {
        *error_code = 10;
        return -1;
    }
    CFIndex data_length = CFDataGetLength(data);
    uint8_t *buffer = malloc((size_t)data_length);
    if (buffer == NULL) {
        CFRelease(data);
        *error_code = 11;
        return -1;
    }
    memcpy(buffer, CFDataGetBytePtr(data), (size_t)data_length);
    CFRelease(data);
    *bytes = buffer;
    *length = (uint64_t)data_length;
    *error_code = 0;
    return 0;
}

void fathom_ioreport_sampler_destroy(fathom_ioreport_sampler sampler) {
    fathom_ioreport_sampler_state *state = sampler;
    if (state == NULL) {
        return;
    }
    if (state->previous_sample != NULL) {
        CFRelease(state->previous_sample);
    }
    if (state->subscription != NULL) {
        CFRelease(state->subscription);
    }
    if (state->subscribed_channels != NULL) {
        CFRelease(state->subscribed_channels);
    }
    if (state->library != NULL) {
        dlclose(state->library);
    }
    free(state);
}

typedef CFTypeRef (*fathom_hid_create_client_fn)(CFAllocatorRef);
typedef void (*fathom_hid_set_matching_fn)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*fathom_hid_copy_services_fn)(CFTypeRef);
typedef CFTypeRef (*fathom_hid_copy_event_fn)(
    CFTypeRef,
    int64_t,
    int32_t,
    int64_t
);
typedef double (*fathom_hid_get_float_fn)(CFTypeRef, uint32_t);
typedef CFTypeRef (*fathom_hid_copy_property_fn)(CFTypeRef, CFStringRef);

int32_t fathom_iohid_copy_temperature_sensors(
    uint8_t **bytes,
    uint64_t *length,
    int32_t *error_code
) {
    if (bytes == NULL || length == NULL || error_code == NULL) {
        return -1;
    }
    *bytes = NULL;
    *length = 0;
    *error_code = 0;
    void *library = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (library == NULL) {
        *error_code = 1;
        return -1;
    }
#define FATHOM_HID_SYMBOL(type, name) \
    (type)fathom_ioreport_symbol(library, name)
    fathom_hid_create_client_fn create_client = FATHOM_HID_SYMBOL(
        fathom_hid_create_client_fn,
        "IOHIDEventSystemClientCreate"
    );
    fathom_hid_set_matching_fn set_matching = FATHOM_HID_SYMBOL(
        fathom_hid_set_matching_fn,
        "IOHIDEventSystemClientSetMatching"
    );
    fathom_hid_copy_services_fn copy_services = FATHOM_HID_SYMBOL(
        fathom_hid_copy_services_fn,
        "IOHIDEventSystemClientCopyServices"
    );
    fathom_hid_copy_event_fn copy_event = FATHOM_HID_SYMBOL(
        fathom_hid_copy_event_fn,
        "IOHIDServiceClientCopyEvent"
    );
    fathom_hid_get_float_fn get_float = FATHOM_HID_SYMBOL(
        fathom_hid_get_float_fn,
        "IOHIDEventGetFloatValue"
    );
    fathom_hid_copy_property_fn copy_property = FATHOM_HID_SYMBOL(
        fathom_hid_copy_property_fn,
        "IOHIDServiceClientCopyProperty"
    );
#undef FATHOM_HID_SYMBOL
    if (create_client == NULL || set_matching == NULL ||
        copy_services == NULL || copy_event == NULL || get_float == NULL ||
        copy_property == NULL) {
        dlclose(library);
        *error_code = 2;
        return -1;
    }
    CFTypeRef client = create_client(kCFAllocatorDefault);
    if (client == NULL) {
        dlclose(library);
        *error_code = 3;
        return -1;
    }
    int64_t usage_page_value = 0xff00;
    int64_t usage_value = 5;
    CFNumberRef usage_page = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt64Type,
        &usage_page_value
    );
    CFNumberRef usage = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt64Type,
        &usage_value
    );
    const void *match_keys[] = {
        CFSTR("PrimaryUsagePage"),
        CFSTR("PrimaryUsage")
    };
    const void *match_values[] = { usage_page, usage };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        match_keys,
        match_values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(usage_page);
    CFRelease(usage);
    set_matching(client, matching);
    CFRelease(matching);
    CFArrayRef services = copy_services(client);
    if (services == NULL) {
        CFRelease(client);
        dlclose(library);
        *error_code = 4;
        return -1;
    }

    CFMutableArrayRef output = CFArrayCreateMutable(
        kCFAllocatorDefault,
        CFArrayGetCount(services),
        &kCFTypeArrayCallBacks
    );
    for (CFIndex index = 0; index < CFArrayGetCount(services); index += 1) {
        CFTypeRef service = CFArrayGetValueAtIndex(services, index);
        CFTypeRef event = copy_event(service, 15, 0, 0);
        if (event == NULL) {
            continue;
        }
        double temperature = get_float(event, 983040);
        CFRelease(event);
        if (!__builtin_isfinite(temperature)) {
            continue;
        }
        CFTypeRef product = copy_property(service, CFSTR("Product"));
        CFStringRef name = NULL;
        if (product != NULL &&
            CFGetTypeID(product) == CFStringGetTypeID()) {
            name = (CFStringRef)product;
        }
        CFTypeRef location = NULL;
        CFStringRef generated_name = NULL;
        if (name == NULL) {
            location = copy_property(service, CFSTR("LocationID"));
            if (location != NULL &&
                CFGetTypeID(location) == CFNumberGetTypeID()) {
                int64_t location_value = 0;
                CFNumberGetValue(
                    (CFNumberRef)location,
                    kCFNumberSInt64Type,
                    &location_value
                );
                generated_name = CFStringCreateWithFormat(
                    kCFAllocatorDefault,
                    NULL,
                    CFSTR("Unknown-FF00-5-%llX"),
                    location_value
                );
                name = generated_name;
            }
        }
        if (name == NULL) {
            name = CFSTR("not published");
        }
        CFNumberRef temperature_number = CFNumberCreate(
            kCFAllocatorDefault,
            kCFNumberDoubleType,
            &temperature
        );
        const void *item_keys[] = { CFSTR("name"), CFSTR("celsius") };
        const void *item_values[] = { name, temperature_number };
        CFDictionaryRef item = CFDictionaryCreate(
            kCFAllocatorDefault,
            item_keys,
            item_values,
            2,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks
        );
        CFArrayAppendValue(output, item);
        CFRelease(item);
        CFRelease(temperature_number);
        if (generated_name != NULL) {
            CFRelease(generated_name);
        }
        if (location != NULL) {
            CFRelease(location);
        }
        if (product != NULL) {
            CFRelease(product);
        }
    }
    CFRelease(services);
    CFRelease(client);
    dlclose(library);

    CFErrorRef serialization_error = NULL;
    CFDataRef data = CFPropertyListCreateData(
        kCFAllocatorDefault,
        output,
        kCFPropertyListBinaryFormat_v1_0,
        0,
        &serialization_error
    );
    CFRelease(output);
    if (serialization_error != NULL) {
        CFRelease(serialization_error);
    }
    if (data == NULL) {
        *error_code = 5;
        return -1;
    }
    CFIndex data_length = CFDataGetLength(data);
    uint8_t *buffer = malloc((size_t)data_length);
    if (buffer == NULL) {
        CFRelease(data);
        *error_code = 6;
        return -1;
    }
    memcpy(buffer, CFDataGetBytePtr(data), (size_t)data_length);
    CFRelease(data);
    *bytes = buffer;
    *length = (uint64_t)data_length;
    return 0;
}

int32_t fathom_cpu_read_ticks(
    fathom_cpu_ticks *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    natural_t processor_count = 0;
    processor_info_array_t info = NULL;
    mach_msg_type_number_t info_count = 0;
    kern_return_t result = host_processor_info(
        mach_host_self(),
        PROCESSOR_CPU_LOAD_INFO,
        &processor_count,
        &info,
        &info_count
    );
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }
    if (processor_count > FATHOM_MAX_CPU_CORES ||
        info_count < processor_count * CPU_STATE_MAX) {
        vm_deallocate(
            mach_task_self(),
            (vm_address_t)info,
            info_count * sizeof(integer_t)
        );
        *error_code = (int32_t)KERN_INVALID_ARGUMENT;
        return -1;
    }
    output->core_count = processor_count;
    for (natural_t index = 0; index < processor_count; index += 1) {
        integer_t *ticks = info + (CPU_STATE_MAX * index);
        output->user[index] = (uint32_t)ticks[CPU_STATE_USER];
        output->system[index] = (uint32_t)ticks[CPU_STATE_SYSTEM];
        output->idle[index] = (uint32_t)ticks[CPU_STATE_IDLE];
        output->nice[index] = (uint32_t)ticks[CPU_STATE_NICE];
    }
    vm_deallocate(
        mach_task_self(),
        (vm_address_t)info,
        info_count * sizeof(integer_t)
    );
    return 0;
}

int32_t fathom_memory_read_counters(
    fathom_memory_counters *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    vm_statistics64_data_t statistics;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t result = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&statistics,
        &count
    );
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }
    vm_size_t page_size = 0;
    result = host_page_size(mach_host_self(), &page_size);
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }
    output->page_size = page_size;
    output->free_pages = statistics.free_count;
    output->active_pages = statistics.active_count;
    output->inactive_pages = statistics.inactive_count;
    output->speculative_pages = statistics.speculative_count;
    output->wired_pages = statistics.wire_count;
    output->compressed_pages = statistics.compressor_page_count;
    output->purgeable_pages = statistics.purgeable_count;

    struct xsw_usage swap;
    size_t swap_size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &swap_size, NULL, 0) == 0) {
        output->swap_used_bytes = swap.xsu_used;
        output->swap_total_bytes = swap.xsu_total;
    }
    return 0;
}

static int fathom_cfnumber_double(
    CFDictionaryRef dictionary,
    CFStringRef key,
    double *output
) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    return CFNumberGetValue(
        (CFNumberRef)value,
        kCFNumberDoubleType,
        output
    );
}

static int fathom_cfnumber_uint64(CFTypeRef value, uint64_t *output) {
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return 0;
    }
    int64_t signed_value = 0;
    if (!CFNumberGetValue(
            (CFNumberRef)value,
            kCFNumberSInt64Type,
            &signed_value
        ) || signed_value < 0) {
        return 0;
    }
    *output = (uint64_t)signed_value;
    return 1;
}

int32_t fathom_gpu_read_counters(
    fathom_gpu_counters *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOAccelerator"),
        &iterator
    );
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }
    uint32_t services_seen = 0;
    io_registry_entry_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        services_seen += 1;
        CFTypeRef statistics = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("PerformanceStatistics"),
            kCFAllocatorDefault,
            0
        );
        if (statistics != NULL &&
            CFGetTypeID(statistics) == CFDictionaryGetTypeID()) {
            CFDictionaryRef dictionary = (CFDictionaryRef)statistics;
            if (fathom_cfnumber_double(
                    dictionary,
                    CFSTR("Device Utilization %"),
                    &output->device_utilization_percent
                )) {
                output->published_fields |=
                    FATHOM_GPU_DEVICE_UTILIZATION;
            }
            if (fathom_cfnumber_double(
                    dictionary,
                    CFSTR("Renderer Utilization %"),
                    &output->renderer_utilization_percent
                )) {
                output->published_fields |=
                    FATHOM_GPU_RENDERER_UTILIZATION;
            }
            if (fathom_cfnumber_double(
                    dictionary,
                    CFSTR("Tiler Utilization %"),
                    &output->tiler_utilization_percent
                )) {
                output->published_fields |= FATHOM_GPU_TILER_UTILIZATION;
            }
        }
        if (statistics != NULL) {
            CFRelease(statistics);
        }
        CFTypeRef core_count = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            CFSTR("gpu-core-count"),
            kCFAllocatorDefault,
            kIORegistryIterateRecursively | kIORegistryIterateParents
        );
        if (fathom_cfnumber_uint64(core_count, &output->core_count)) {
            output->published_fields |= FATHOM_GPU_CORE_COUNT;
        }
        if (core_count != NULL) {
            CFRelease(core_count);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (services_seen == 0) {
        *error_code = (int32_t)kIOReturnNotFound;
        return -1;
    }
    return 0;
}

int32_t fathom_network_read_counters(
    fathom_network_counters *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0) {
        *error_code = errno;
        return -1;
    }
    uint8_t *buffer = malloc(length);
    if (buffer == NULL) {
        *error_code = ENOMEM;
        return -1;
    }
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) {
        *error_code = errno;
        free(buffer);
        return -1;
    }
    uint8_t *cursor = buffer;
    uint8_t *end = buffer + length;
    while (cursor + sizeof(struct if_msghdr) <= end) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (header->ifm_msglen == 0 || cursor + header->ifm_msglen > end) {
            break;
        }
        if (header->ifm_type == RTM_IFINFO2 &&
            header->ifm_msglen >= sizeof(struct if_msghdr2) &&
            output->interface_count < FATHOM_MAX_NETWORK_INTERFACES) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            fathom_network_interface *item =
                &output->interfaces[output->interface_count];
            if (if_indextoname(
                    info->ifm_index,
                    item->name
                ) != NULL) {
                item->received_bytes = info->ifm_data.ifi_ibytes;
                item->sent_bytes = info->ifm_data.ifi_obytes;
                item->flags = (uint32_t)info->ifm_flags;
                output->interface_count += 1;
            }
        }
        cursor += header->ifm_msglen;
    }
    free(buffer);
    return 0;
}

int32_t fathom_network_read_addresses(
    fathom_network_addresses *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) {
        *error_code = errno;
        return -1;
    }
    for (struct ifaddrs *item = interfaces;
         item != NULL &&
             output->address_count < FATHOM_MAX_NETWORK_ADDRESSES;
         item = item->ifa_next) {
        if (item->ifa_addr == NULL || item->ifa_name == NULL ||
            (item->ifa_flags & IFF_UP) == 0 ||
            (item->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }
        int family = item->ifa_addr->sa_family;
        if (family != AF_INET && family != AF_INET6) {
            continue;
        }
        socklen_t length = family == AF_INET
            ? sizeof(struct sockaddr_in)
            : sizeof(struct sockaddr_in6);
        fathom_network_address *address =
            &output->addresses[output->address_count];
        int result = getnameinfo(
            item->ifa_addr,
            length,
            address->address,
            sizeof(address->address),
            NULL,
            0,
            NI_NUMERICHOST
        );
        if (result != 0) {
            continue;
        }
        strlcpy(
            address->interface_name,
            item->ifa_name,
            sizeof(address->interface_name)
        );
        address->family = family == AF_INET ? 4 : 6;
        output->address_count += 1;
    }
    freeifaddrs(interfaces);
    return 0;
}

int32_t fathom_disk_read_counters(
    fathom_disk_counters *output,
    int32_t *error_code
) {
    if (output == NULL || error_code == NULL) {
        return -1;
    }
    memset(output, 0, sizeof(*output));
    *error_code = 0;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOBlockStorageDriver"),
        &iterator
    );
    if (result != KERN_SUCCESS) {
        *error_code = (int32_t)result;
        return -1;
    }
    io_registry_entry_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        output->drivers_seen += 1;
        CFTypeRef property = IORegistryEntryCreateCFProperty(
            service,
            CFSTR("Statistics"),
            kCFAllocatorDefault,
            0
        );
        if (property != NULL &&
            CFGetTypeID(property) == CFDictionaryGetTypeID()) {
            CFDictionaryRef statistics = (CFDictionaryRef)property;
            uint64_t read = 0;
            uint64_t written = 0;
            int has_read = fathom_cfnumber_uint64(
                CFDictionaryGetValue(statistics, CFSTR("Bytes (Read)")),
                &read
            );
            int has_written = fathom_cfnumber_uint64(
                CFDictionaryGetValue(statistics, CFSTR("Bytes (Write)")),
                &written
            );
            if (has_read && has_written &&
                UINT64_MAX - output->bytes_read >= read &&
                UINT64_MAX - output->bytes_written >= written) {
                output->bytes_read += read;
                output->bytes_written += written;
                output->drivers_publishing_statistics += 1;
            }
        }
        if (property != NULL) {
            CFRelease(property);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (output->drivers_seen == 0 ||
        output->drivers_publishing_statistics == 0) {
        *error_code = (int32_t)kIOReturnNotFound;
        return -1;
    }
    return 0;
}

typedef struct fathom_display_refresh_state {
    CVDisplayLinkRef link;
    _Atomic uint64_t count;
} fathom_display_refresh_state;

static CVReturn fathom_display_refresh_callback(
    CVDisplayLinkRef link,
    const CVTimeStamp *now,
    const CVTimeStamp *output,
    CVOptionFlags input_flags,
    CVOptionFlags *output_flags,
    void *context
) {
    (void)link;
    (void)now;
    (void)output;
    (void)input_flags;
    (void)output_flags;
    fathom_display_refresh_state *state = context;
    if (state != NULL) {
        atomic_fetch_add_explicit(&state->count, 1, memory_order_relaxed);
    }
    return kCVReturnSuccess;
}

int32_t fathom_display_refresh_sampler_create(
    fathom_display_refresh_sampler *sampler,
    int32_t *error_code
) {
    if (sampler == NULL || error_code == NULL) {
        return -1;
    }
    *sampler = NULL;
    *error_code = 0;
    fathom_display_refresh_state *state = calloc(1, sizeof(*state));
    if (state == NULL) {
        *error_code = ENOMEM;
        return -1;
    }
    CVReturn result = CVDisplayLinkCreateWithActiveCGDisplays(&state->link);
    if (result != kCVReturnSuccess || state->link == NULL) {
        free(state);
        *error_code = (int32_t)result;
        return -1;
    }
    result = CVDisplayLinkSetOutputCallback(
        state->link,
        fathom_display_refresh_callback,
        state
    );
    if (result == kCVReturnSuccess) {
        result = CVDisplayLinkStart(state->link);
    }
    if (result != kCVReturnSuccess) {
        CVDisplayLinkRelease(state->link);
        free(state);
        *error_code = (int32_t)result;
        return -1;
    }
    *sampler = state;
    return 0;
}

uint64_t fathom_display_refresh_sampler_count(
    fathom_display_refresh_sampler sampler
) {
    fathom_display_refresh_state *state = sampler;
    if (state == NULL) {
        return 0;
    }
    return atomic_load_explicit(&state->count, memory_order_relaxed);
}

void fathom_display_refresh_sampler_destroy(
    fathom_display_refresh_sampler sampler
) {
    fathom_display_refresh_state *state = sampler;
    if (state == NULL) {
        return;
    }
    if (state->link != NULL) {
        CVDisplayLinkStop(state->link);
        CVDisplayLinkRelease(state->link);
    }
    free(state);
}

int32_t fathom_smc_decode_numeric(
    const fathom_smc_value *value,
    double *output
) {
    if (value == NULL || output == NULL) {
        return -1;
    }
    uint32_t type = value->data_type;
    const uint8_t *bytes = value->bytes;
    if (type == fathom_fourcc('u', 'i', '8', ' ') &&
        value->data_size >= 1) {
        *output = (double)bytes[0];
        return 0;
    }
    if (type == fathom_fourcc('u', 'i', '1', '6') &&
        value->data_size >= 2) {
        *output = (double)(((uint16_t)bytes[0] << 8) | bytes[1]);
        return 0;
    }
    if (type == fathom_fourcc('u', 'i', '3', '2') &&
        value->data_size >= 4) {
        *output = (double)fathom_read_be32(bytes);
        return 0;
    }
    if (type == fathom_fourcc('s', 'i', '8', ' ') &&
        value->data_size >= 1) {
        *output = (double)(int8_t)bytes[0];
        return 0;
    }
    if (type == fathom_fourcc('s', 'i', '1', '6') &&
        value->data_size >= 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        *output = (double)raw;
        return 0;
    }
    if (type == fathom_fourcc('s', 'i', '3', '2') &&
        value->data_size >= 4) {
        *output = (double)(int32_t)fathom_read_be32(bytes);
        return 0;
    }
    if (type == fathom_fourcc('s', 'p', '7', '8') &&
        value->data_size >= 2) {
        int16_t raw = (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
        *output = (double)raw / 256.0;
        return 0;
    }
    if (type == fathom_fourcc('f', 'p', 'e', '2') &&
        value->data_size >= 2) {
        uint16_t raw = ((uint16_t)bytes[0] << 8) | bytes[1];
        *output = (double)raw / 4.0;
        return 0;
    }
    if (type == fathom_fourcc('f', 'l', 't', ' ') &&
        value->data_size >= 4) {
        float raw = 0;
        memcpy(&raw, bytes, sizeof(raw));
        if (!__builtin_isfinite(raw)) {
            return -1;
        }
        *output = (double)raw;
        return 0;
    }
    return -1;
}
