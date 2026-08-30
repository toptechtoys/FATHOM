#include "CFathomStorage.h"

#include <errno.h>
#include <fcntl.h>
#include <fts.h>
#include <limits.h>
#include <libproc.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/snapshot.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <unistd.h>

/* The SNAPSHOT_MNT_* names appeared in a later SDK than this project's macOS 14
 * deployment target, so building against an older SDK cannot find them even
 * though fs_snapshot_mount() itself has been available since macOS 10.12.
 * <sys/snapshot.h> documents each flag as "same as MNT_*", and the values in
 * <sys/mount.h> match exactly, so fall back to those long-standing constants
 * rather than to bare literals. The assertions below fail loudly if a future
 * SDK ever breaks that documented equivalence. */
#ifndef SNAPSHOT_MNT_NOEXEC
#define SNAPSHOT_MNT_NOEXEC MNT_NOEXEC
#endif
#ifndef SNAPSHOT_MNT_NOSUID
#define SNAPSHOT_MNT_NOSUID MNT_NOSUID
#endif
#ifndef SNAPSHOT_MNT_NODEV
#define SNAPSHOT_MNT_NODEV MNT_NODEV
#endif
#ifndef SNAPSHOT_MNT_DONTBROWSE
#define SNAPSHOT_MNT_DONTBROWSE MNT_DONTBROWSE
#endif
#ifndef SNAPSHOT_MNT_NOFOLLOW
#define SNAPSHOT_MNT_NOFOLLOW MNT_NOFOLLOW
#endif

_Static_assert(SNAPSHOT_MNT_NOEXEC == MNT_NOEXEC,
               "SNAPSHOT_MNT_NOEXEC no longer matches MNT_NOEXEC");
_Static_assert(SNAPSHOT_MNT_NOSUID == MNT_NOSUID,
               "SNAPSHOT_MNT_NOSUID no longer matches MNT_NOSUID");
_Static_assert(SNAPSHOT_MNT_NODEV == MNT_NODEV,
               "SNAPSHOT_MNT_NODEV no longer matches MNT_NODEV");
_Static_assert(SNAPSHOT_MNT_DONTBROWSE == MNT_DONTBROWSE,
               "SNAPSHOT_MNT_DONTBROWSE no longer matches MNT_DONTBROWSE");
_Static_assert(SNAPSHOT_MNT_NOFOLLOW == MNT_NOFOLLOW,
               "SNAPSHOT_MNT_NOFOLLOW no longer matches MNT_NOFOLLOW");

static uint64_t nonnegative_u64(int64_t value) {
    return value > 0 ? (uint64_t)value : 0;
}

static uint64_t allocated_bytes(const struct stat *metadata) {
    if (metadata->st_blocks <= 0) {
        return 0;
    }

    uint64_t blocks = (uint64_t)metadata->st_blocks;
    if (blocks > UINT64_MAX / 512) {
        return UINT64_MAX;
    }
    return blocks * 512;
}

static FathomFTSEntryKind entry_kind(mode_t mode) {
    if (S_ISREG(mode)) {
        return FATHOM_FTS_REGULAR;
    }
    if (S_ISDIR(mode)) {
        return FATHOM_FTS_DIRECTORY;
    }
    if (S_ISLNK(mode)) {
        return FATHOM_FTS_SYMBOLIC_LINK;
    }
    return FATHOM_FTS_OTHER;
}

/* Open addressing with linear probing. Keys are (device, inode); an inode of 0
 * is never a real file, so it marks an empty slot and needs no side table. */
struct FathomIdentitySet {
    uint64_t *devices;
    uint64_t *inodes;
    uint64_t capacity;
    uint64_t count;
};

static uint64_t identity_hash(uint64_t device, uint64_t inode) {
    /* splitmix64's finalizer. Inode numbers are dense and often sequential, and
     * a weak hash turns linear probing into a linear scan. */
    uint64_t value = inode ^ (device * 0x9E3779B97F4A7C15ULL);
    value ^= value >> 30;
    value *= 0xBF58476D1CE4E5B9ULL;
    value ^= value >> 27;
    value *= 0x94D049BB133111EBULL;
    value ^= value >> 31;
    return value;
}

static bool identity_set_grow(FathomIdentitySet *set, uint64_t capacity) {
    uint64_t *devices = calloc((size_t)capacity, sizeof(uint64_t));
    uint64_t *inodes = calloc((size_t)capacity, sizeof(uint64_t));
    if (devices == NULL || inodes == NULL) {
        free(devices);
        free(inodes);
        return false;
    }
    const uint64_t mask = capacity - 1;
    for (uint64_t slot = 0; slot < set->capacity; slot++) {
        if (set->inodes[slot] == 0) {
            continue;
        }
        uint64_t probe = identity_hash(set->devices[slot], set->inodes[slot]) &
            mask;
        while (inodes[probe] != 0) {
            probe = (probe + 1) & mask;
        }
        devices[probe] = set->devices[slot];
        inodes[probe] = set->inodes[slot];
    }
    free(set->devices);
    free(set->inodes);
    set->devices = devices;
    set->inodes = inodes;
    set->capacity = capacity;
    return true;
}

FathomIdentitySet *fathom_identity_set_create(void) {
    FathomIdentitySet *set = calloc(1, sizeof(FathomIdentitySet));
    if (set == NULL) {
        return NULL;
    }
    if (!identity_set_grow(set, 1024)) {
        free(set);
        return NULL;
    }
    return set;
}

void fathom_identity_set_destroy(FathomIdentitySet *set) {
    if (set == NULL) {
        return;
    }
    free(set->devices);
    free(set->inodes);
    free(set);
}

int32_t fathom_identity_set_insert(
    FathomIdentitySet *set,
    uint64_t device,
    uint64_t inode
) {
    if (set == NULL || inode == 0) {
        return -1;
    }
    /* Grow at 70% so probe chains stay short. */
    if ((set->count + 1) * 10 >= set->capacity * 7) {
        if (set->capacity > UINT64_MAX / 2 ||
            !identity_set_grow(set, set->capacity * 2)) {
            return -1;
        }
    }
    const uint64_t mask = set->capacity - 1;
    uint64_t probe = identity_hash(device, inode) & mask;
    while (set->inodes[probe] != 0) {
        if (set->inodes[probe] == inode && set->devices[probe] == device) {
            return 0;
        }
        probe = (probe + 1) & mask;
    }
    set->devices[probe] = device;
    set->inodes[probe] = inode;
    set->count += 1;
    return 1;
}

uint64_t fathom_identity_set_count(const FathomIdentitySet *set) {
    return set == NULL ? 0 : set->count;
}

int32_t fathom_fts_walk(
    const char *root_path,
    FathomFTSEntryCallback callback,
    void *context,
    uint64_t *aliased_directories_skipped,
    int32_t *error_number
) {
    if (root_path == NULL || callback == NULL ||
        aliased_directories_skipped == NULL || error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    *aliased_directories_skipped = 0;

    struct stat root_metadata;
    if (lstat(root_path, &root_metadata) != 0) {
        *error_number = errno;
        return -1;
    }

    FathomIdentitySet *visited = fathom_identity_set_create();
    if (visited == NULL) {
        *error_number = ENOMEM;
        return -1;
    }

    char *paths[] = { (char *)root_path, NULL };
    FTS *stream = fts_open(paths, FTS_PHYSICAL | FTS_NOCHDIR, NULL);
    if (stream == NULL) {
        *error_number = errno;
        fathom_identity_set_destroy(visited);
        return -1;
    }

    errno = 0;
    FTSENT *node = NULL;
    while ((node = fts_read(stream)) != NULL) {
        if (node->fts_info == FTS_DP) {
            continue;
        }

        /* Count each directory once, whatever path reached it. Only the
         * pre-order visit is tested, so the subtree can be pruned before it is
         * walked rather than filtered after. */
        if (node->fts_info == FTS_D && node->fts_statp != NULL) {
            const int32_t inserted = fathom_identity_set_insert(
                visited,
                (uint64_t)node->fts_statp->st_dev,
                (uint64_t)node->fts_statp->st_ino
            );
            if (inserted == 0) {
                *aliased_directories_skipped += 1;
                (void)fts_set(stream, node, FTS_SKIP);
                continue;
            }
            if (inserted < 0) {
                (void)fts_close(stream);
                fathom_identity_set_destroy(visited);
                *error_number = ENOMEM;
                return -1;
            }
        }

        FathomFTSEntry entry = {
            .path = node->fts_path,
            .kind = FATHOM_FTS_OTHER,
            .device = 0,
            .inode = 0,
            .hard_link_count = 0,
            .logical_size = 0,
            .allocated_size = 0,
            .modification_time_seconds = 0,
            .modification_time_nanoseconds = 0,
            .is_dataless = 0,
            .error_number = 0,
            .name = node->fts_name,
            .name_length = (uint64_t)node->fts_namelen,
            .level = node->fts_level >= 0
                ? (uint64_t)node->fts_level
                : 0,
            .parent_device = 0,
            .parent_inode = 0,
            .has_parent = 0
        };

        if (node->fts_level > 0 &&
            node->fts_parent != NULL &&
            node->fts_parent->fts_statp != NULL) {
            entry.parent_device =
                (uint64_t)node->fts_parent->fts_statp->st_dev;
            entry.parent_inode =
                (uint64_t)node->fts_parent->fts_statp->st_ino;
            entry.has_parent = 1;
        }

        if (node->fts_info == FTS_ERR ||
            node->fts_info == FTS_DNR ||
            node->fts_info == FTS_NS) {
            entry.error_number = node->fts_errno != 0 ? node->fts_errno : EIO;
        } else if (node->fts_statp != NULL) {
            const struct stat *metadata = node->fts_statp;
            entry.kind = entry_kind(metadata->st_mode);
            entry.device = (uint64_t)metadata->st_dev;
            entry.inode = (uint64_t)metadata->st_ino;
            entry.hard_link_count = (uint64_t)metadata->st_nlink;
            entry.logical_size = nonnegative_u64(metadata->st_size);
            entry.allocated_size = allocated_bytes(metadata);
            entry.modification_time_seconds =
                metadata->st_mtimespec.tv_sec;
            entry.modification_time_nanoseconds =
                (int32_t)metadata->st_mtimespec.tv_nsec;
#ifdef SF_DATALESS
            entry.is_dataless = (metadata->st_flags & SF_DATALESS) != 0;
#endif
        }

        if (callback(&entry, context) != 0) {
            (void)fts_close(stream);
            fathom_identity_set_destroy(visited);
            *error_number = 0;
            return 0;
        }
    }

    int read_error = errno;
    int close_result = fts_close(stream);
    fathom_identity_set_destroy(visited);
    if (read_error != 0) {
        *error_number = read_error;
        return -1;
    }
    if (close_result != 0) {
        *error_number = errno;
        return -1;
    }

    *error_number = 0;
    return 0;
}

static bool identity_matches(
    const struct stat *metadata,
    uint64_t expected_device,
    uint64_t expected_inode
) {
    return (uint64_t)metadata->st_dev == expected_device &&
        (uint64_t)metadata->st_ino == expected_inode;
}

static int32_t emit_extent(
    FathomExtentKind kind,
    off_t logical_offset,
    off_t length,
    off_t device_offset,
    FathomExtentCallback callback,
    void *context
) {
    FathomExtent extent = {
        .kind = kind,
        .logical_offset = nonnegative_u64(logical_offset),
        .length = nonnegative_u64(length),
        .device_offset = nonnegative_u64(device_offset)
    };
    return callback(&extent, context);
}

int32_t fathom_file_extents(
    const char *path,
    uint64_t expected_device,
    uint64_t expected_inode,
    FathomExtentCallback callback,
    void *context,
    int32_t *is_dataless,
    uint64_t *clone_id,
    uint32_t *clone_reference_count,
    int32_t *clone_metadata_error,
    uint64_t *allocation_block_size,
    int32_t *physical_mapping_error,
    int32_t *error_number
) {
    if (path == NULL ||
        callback == NULL ||
        is_dataless == NULL ||
        clone_id == NULL ||
        clone_reference_count == NULL ||
        clone_metadata_error == NULL ||
        allocation_block_size == NULL ||
        physical_mapping_error == NULL ||
        error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    *is_dataless = 0;
    *clone_id = 0;
    *clone_reference_count = 0;
    *clone_metadata_error = 0;
    *allocation_block_size = 0;
    *physical_mapping_error = 0;
    *error_number = 0;

    struct stat path_metadata;
    if (lstat(path, &path_metadata) != 0) {
        *error_number = errno;
        return -1;
    }
    if (!identity_matches(&path_metadata, expected_device, expected_inode)) {
        *error_number = ESTALE;
        return -1;
    }
    if (!S_ISREG(path_metadata.st_mode)) {
        *error_number = EINVAL;
        return -1;
    }
#ifdef SF_DATALESS
    if ((path_metadata.st_flags & SF_DATALESS) != 0) {
        *is_dataless = 1;
        return 0;
    }
#endif

    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        *error_number = errno;
        return -1;
    }

    struct stat opened_metadata;
    if (fstat(descriptor, &opened_metadata) != 0) {
        *error_number = errno;
        (void)close(descriptor);
        return -1;
    }
    if (!identity_matches(&opened_metadata, expected_device, expected_inode)) {
        *error_number = ESTALE;
        (void)close(descriptor);
        return -1;
    }
#ifdef SF_DATALESS
    if ((opened_metadata.st_flags & SF_DATALESS) != 0) {
        *is_dataless = 1;
        (void)close(descriptor);
        return 0;
    }
#endif

    struct statfs filesystem_metadata;
    if (fstatfs(descriptor, &filesystem_metadata) != 0) {
        *error_number = errno;
        (void)close(descriptor);
        return -1;
    }
    if (filesystem_metadata.f_bsize <= 0) {
        *error_number = EIO;
        (void)close(descriptor);
        return -1;
    }
    *allocation_block_size =
        (uint64_t)filesystem_metadata.f_bsize;

    struct attrlist clone_attributes = {
        .bitmapcount = ATTR_BIT_MAP_COUNT,
        .reserved = 0,
        .commonattr = 0,
        .volattr = 0,
        .dirattr = 0,
        .fileattr = 0,
        .forkattr = ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_CLONE_REFCNT
    };
#pragma pack(push, 4)
    struct {
        uint32_t length;
        uint64_t clone_id;
        uint32_t clone_reference_count;
    } clone_buffer;
#pragma pack(pop)
    memset(&clone_buffer, 0, sizeof(clone_buffer));
    if (fgetattrlist(
            descriptor,
            &clone_attributes,
            &clone_buffer,
            sizeof(clone_buffer),
            FSOPT_ATTR_CMN_EXTENDED
        ) == 0) {
        *clone_id = clone_buffer.clone_id;
        *clone_reference_count = clone_buffer.clone_reference_count;
    } else {
        *clone_metadata_error = errno;
    }

    off_t logical_size = opened_metadata.st_size;
    off_t cursor = 0;
    while (cursor < logical_size) {
        errno = 0;
        off_t data_offset = lseek(descriptor, cursor, SEEK_DATA);
        if (data_offset < 0) {
            if (errno == ENXIO) {
                break;
            }
            *error_number = errno;
            (void)close(descriptor);
            return -1;
        }

        errno = 0;
        off_t hole_offset = lseek(descriptor, data_offset, SEEK_HOLE);
        if (hole_offset < 0) {
            if (errno == ENXIO) {
                hole_offset = logical_size;
            } else {
                *error_number = errno;
                (void)close(descriptor);
                return -1;
            }
        }
        if (hole_offset > logical_size) {
            hole_offset = logical_size;
        }
        if (hole_offset <= data_offset) {
            *error_number = EIO;
            (void)close(descriptor);
            return -1;
        }

        if (emit_extent(
                FATHOM_EXTENT_DATA,
                data_offset,
                hole_offset - data_offset,
                0,
                callback,
                context
            ) != 0) {
            (void)close(descriptor);
            return 0;
        }

        if (*physical_mapping_error == 0) {
            off_t physical_cursor = data_offset;
            while (physical_cursor < hole_offset) {
                struct log2phys mapping = {
                    .l2p_flags = 0,
                    .l2p_contigbytes = hole_offset - physical_cursor,
                    .l2p_devoffset = physical_cursor
                };

                if (fcntl(descriptor, F_LOG2PHYS_EXT, &mapping) != 0) {
                    *physical_mapping_error = errno;
                    break;
                }

                off_t mapped_length = mapping.l2p_contigbytes;
                off_t remaining_length = hole_offset - physical_cursor;
                if (mapped_length <= 0 || mapping.l2p_devoffset < 0) {
                    *physical_mapping_error = EIO;
                    break;
                }
                if (mapped_length > remaining_length) {
                    mapped_length = remaining_length;
                }

                if (emit_extent(
                        FATHOM_EXTENT_PHYSICAL,
                        physical_cursor,
                        mapped_length,
                        mapping.l2p_devoffset,
                        callback,
                        context
                    ) != 0) {
                    (void)close(descriptor);
                    return 0;
                }
                physical_cursor += mapped_length;
            }
        }

        cursor = hole_offset;
    }

    if (close(descriptor) != 0) {
        *error_number = errno;
        return -1;
    }
    return 0;
}

int32_t fathom_snapshot_list(
    const char *volume_path,
    FathomSnapshotCallback callback,
    void *context,
    int32_t *error_number
) {
    if (volume_path == NULL || callback == NULL || error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    int descriptor = open(
        volume_path,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
    );
    if (descriptor < 0) {
        *error_number = errno;
        return -1;
    }

    struct attrlist attributes = {
        .bitmapcount = ATTR_BIT_MAP_COUNT,
        .reserved = 0,
        .commonattr = ATTR_BULK_REQUIRED,
        .volattr = 0,
        .dirattr = 0,
        .fileattr = 0,
        .forkattr = 0
    };
    const size_t buffer_size = 64 * 1024;
    uint8_t *buffer = malloc(buffer_size);
    if (buffer == NULL) {
        *error_number = ENOMEM;
        (void)close(descriptor);
        return -1;
    }

    while (true) {
        int count = fs_snapshot_list(
            descriptor,
            &attributes,
            buffer,
            buffer_size,
            0
        );
        if (count < 0) {
            *error_number = errno;
            free(buffer);
            (void)close(descriptor);
            return -1;
        }
        if (count == 0) {
            break;
        }

        uint8_t *cursor = buffer;
        uint8_t *buffer_end = buffer + buffer_size;
        for (int index = 0; index < count; index++) {
            if ((size_t)(buffer_end - cursor) < sizeof(uint32_t)) {
                *error_number = EIO;
                free(buffer);
                (void)close(descriptor);
                return -1;
            }

            uint32_t record_length = 0;
            memcpy(&record_length, cursor, sizeof(record_length));
            if (record_length <
                    sizeof(uint32_t) +
                    sizeof(attribute_set_t) +
                    sizeof(attrreference_t) ||
                record_length > (uint32_t)(buffer_end - cursor)) {
                *error_number = EIO;
                free(buffer);
                (void)close(descriptor);
                return -1;
            }

            attribute_set_t returned_attributes;
            uint8_t *field = cursor + sizeof(uint32_t);
            memcpy(
                &returned_attributes,
                field,
                sizeof(returned_attributes)
            );
            if ((returned_attributes.commonattr & ATTR_CMN_NAME) == 0) {
                *error_number = EIO;
                free(buffer);
                (void)close(descriptor);
                return -1;
            }

            attrreference_t name_reference;
            uint8_t *reference_address =
                field + sizeof(returned_attributes);
            memcpy(
                &name_reference,
                reference_address,
                sizeof(name_reference)
            );
            if (name_reference.attr_dataoffset < 0) {
                *error_number = EIO;
                free(buffer);
                (void)close(descriptor);
                return -1;
            }

            uint8_t *name = reference_address +
                name_reference.attr_dataoffset;
            uint8_t *record_end = cursor + record_length;
            if (name < cursor ||
                name > record_end ||
                name_reference.attr_length > (uint32_t)(record_end - name)) {
                *error_number = EIO;
                free(buffer);
                (void)close(descriptor);
                return -1;
            }

            uint32_t name_length = name_reference.attr_length;
            if (name_length > 0 && name[name_length - 1] == '\0') {
                name_length -= 1;
            }
            if (callback(
                    (const char *)name,
                    name_length,
                    context
                ) != 0) {
                free(buffer);
                (void)close(descriptor);
                *error_number = 0;
                return 0;
            }
            cursor = record_end;
        }
    }

    free(buffer);
    if (close(descriptor) != 0) {
        *error_number = errno;
        return -1;
    }
    *error_number = 0;
    return 0;
}

int32_t fathom_snapshot_mount(
    const char *volume_path,
    const char *mount_path,
    const char *snapshot_name,
    int32_t *error_number
) {
    if (volume_path == NULL ||
        mount_path == NULL ||
        snapshot_name == NULL ||
        error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    int descriptor = open(
        volume_path,
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
    );
    if (descriptor < 0) {
        *error_number = errno;
        return -1;
    }

    uint32_t flags =
        SNAPSHOT_MNT_NOEXEC |
        SNAPSHOT_MNT_NOSUID |
        SNAPSHOT_MNT_NODEV |
        SNAPSHOT_MNT_DONTBROWSE |
        SNAPSHOT_MNT_NOFOLLOW;
    int result = fs_snapshot_mount(
        descriptor,
        mount_path,
        snapshot_name,
        flags
    );
    int saved_error = result == 0 ? 0 : errno;
    (void)close(descriptor);
    *error_number = saved_error;
    return result;
}

int32_t fathom_snapshot_unmount(
    const char *mount_path,
    int32_t *error_number
) {
    if (mount_path == NULL || error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    int result = unmount(mount_path, 0);
    *error_number = result == 0 ? 0 : errno;
    return result;
}

int32_t fathom_open_file_identities(
    FathomOpenFileCallback callback,
    void *context,
    uint32_t *inaccessible_process_count,
    int32_t *error_number
) {
    if (callback == NULL ||
        inaccessible_process_count == NULL ||
        error_number == NULL) {
        if (error_number != NULL) {
            *error_number = EINVAL;
        }
        return -1;
    }

    *inaccessible_process_count = 0;
    *error_number = 0;
    int estimated_count = proc_listallpids(NULL, 0);
    if (estimated_count < 0) {
        *error_number = errno;
        return -1;
    }
    if (estimated_count == 0) {
        return 0;
    }

    size_t pid_capacity = (size_t)estimated_count + 64;
    if (pid_capacity > (size_t)INT_MAX / sizeof(pid_t)) {
        *error_number = EOVERFLOW;
        return -1;
    }
    pid_t *pids = calloc(pid_capacity, sizeof(pid_t));
    if (pids == NULL) {
        *error_number = ENOMEM;
        return -1;
    }

    int pid_count = proc_listallpids(
        pids,
        (int)(pid_capacity * sizeof(pid_t))
    );
    if (pid_count < 0) {
        *error_number = errno;
        free(pids);
        return -1;
    }

    for (int pid_index = 0; pid_index < pid_count; pid_index++) {
        pid_t pid = pids[pid_index];
        if (pid <= 0) {
            continue;
        }

        errno = 0;
        int required_bytes = proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            NULL,
            0
        );
        if (required_bytes <= 0) {
            if (errno == EPERM || errno == EACCES) {
                (*inaccessible_process_count)++;
            }
            continue;
        }

        struct proc_fdinfo *descriptors = malloc((size_t)required_bytes);
        if (descriptors == NULL) {
            *error_number = ENOMEM;
            free(pids);
            return -1;
        }
        errno = 0;
        int returned_bytes = proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            descriptors,
            required_bytes
        );
        if (returned_bytes <= 0) {
            if (errno == EPERM || errno == EACCES) {
                (*inaccessible_process_count)++;
            }
            free(descriptors);
            continue;
        }

        int descriptor_count =
            returned_bytes / (int)sizeof(struct proc_fdinfo);
        bool pid_became_inaccessible = false;
        for (int descriptor_index = 0;
            descriptor_index < descriptor_count;
            descriptor_index++) {
            struct proc_fdinfo descriptor = descriptors[descriptor_index];
            if (descriptor.proc_fdtype != PROX_FDTYPE_VNODE) {
                continue;
            }

            struct vnode_fdinfowithpath information;
            memset(&information, 0, sizeof(information));
            errno = 0;
            int information_bytes = proc_pidfdinfo(
                pid,
                descriptor.proc_fd,
                PROC_PIDFDVNODEPATHINFO,
                &information,
                (int)sizeof(information)
            );
            if (information_bytes != (int)sizeof(information)) {
                if (errno == EPERM || errno == EACCES) {
                    pid_became_inaccessible = true;
                }
                continue;
            }

            const struct vinfo_stat *metadata =
                &information.pvip.vip_vi.vi_stat;
            if (callback(
                    (uint64_t)metadata->vst_dev,
                    metadata->vst_ino,
                    context
                ) != 0) {
                free(descriptors);
                free(pids);
                return 0;
            }
        }
        if (pid_became_inaccessible) {
            (*inaccessible_process_count)++;
        }
        free(descriptors);
    }

    free(pids);
    return 0;
}
