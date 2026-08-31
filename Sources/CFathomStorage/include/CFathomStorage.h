#ifndef CFATHOMSTORAGE_H
#define CFATHOMSTORAGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum FathomFTSEntryKind {
    FATHOM_FTS_REGULAR = 1,
    FATHOM_FTS_DIRECTORY = 2,
    FATHOM_FTS_SYMBOLIC_LINK = 3,
    FATHOM_FTS_OTHER = 4
} FathomFTSEntryKind;

typedef struct FathomFTSEntry {
    const char *path;
    FathomFTSEntryKind kind;
    uint64_t device;
    uint64_t inode;
    uint64_t hard_link_count;
    uint64_t logical_size;
    uint64_t allocated_size;
    int64_t modification_time_seconds;
    int32_t modification_time_nanoseconds;
    int32_t is_dataless;
    int32_t error_number;
    const char *name;
    uint64_t name_length;
    uint64_t level;
    uint64_t parent_device;
    uint64_t parent_inode;
    int32_t has_parent;
} FathomFTSEntry;

typedef int32_t (*FathomFTSEntryCallback)(
    const FathomFTSEntry *entry,
    void *context
);

/// A set of `(device, inode)` pairs — the POSIX identity of a file.
///
/// The walk uses it to count each directory once. macOS presents a sealed
/// system volume and its data volume as one `st_dev`, and firmlinks expose the
/// data volume's directories at two paths, so `/Users` and
/// `/System/Volumes/Data/Users` are the same inode reached twice. Neither
/// `FTS_XDEV` nor `statfs` mount points separate them; identity does.
typedef struct FathomIdentitySet FathomIdentitySet;

FathomIdentitySet *fathom_identity_set_create(void);

void fathom_identity_set_destroy(FathomIdentitySet *set);

/// Returns 1 when the identity was newly inserted, 0 when it was already
/// present, and -1 when the set could not grow. Inode 0 is not a file, so it
/// is rejected as -1 rather than stored.
int32_t fathom_identity_set_insert(
    FathomIdentitySet *set,
    uint64_t device,
    uint64_t inode
);

uint64_t fathom_identity_set_count(const FathomIdentitySet *set);

/// Walks `root_path` using `fts(3)` without following symbolic links.
///
/// The callback's entry and path are valid only for the duration of the call.
/// Returning non-zero stops the walk without treating it as a filesystem error.
///
/// A directory whose `(device, inode)` has already been walked is pruned and
/// not reported: it is the same directory reached by a second path, and
/// counting it twice would double the volume. `aliased_directories_skipped`
/// receives how many were pruned, because a walk that silently halves itself
/// is as hard to trust as one that doubles. Files are never deduplicated —
/// hard links are a real thing the two-number engine accounts for.
///
/// The walk also stops at the edge of the root's APFS container, and
/// `other_container_mounts_skipped` counts the mounts it declined. Several
/// volumes share one container and its free space — `/`, the data volume,
/// Preboot, VM and Update are all the same disk — so `st_dev` alone is the
/// wrong boundary. An attached drive is a different disk and its bytes are not
/// on the one being measured.
int32_t fathom_fts_walk(
    const char *root_path,
    FathomFTSEntryCallback callback,
    void *context,
    uint64_t *aliased_directories_skipped,
    uint64_t *other_container_mounts_skipped,
    int32_t *error_number
);

typedef enum FathomExtentKind {
    FATHOM_EXTENT_DATA = 1,
    FATHOM_EXTENT_PHYSICAL = 2
} FathomExtentKind;

typedef struct FathomExtent {
    FathomExtentKind kind;
    uint64_t logical_offset;
    uint64_t length;
    uint64_t device_offset;
} FathomExtent;

typedef int32_t (*FathomExtentCallback)(
    const FathomExtent *extent,
    void *context
);

/// Enumerates resident data ranges with `SEEK_DATA` / `SEEK_HOLE` and maps
/// those ranges to device offsets with `F_LOG2PHYS_EXT`.
///
/// The path is rejected if its device/inode no longer match the identity
/// recorded by the FTS walk. Dataless files are reported without being opened.
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
);

typedef int32_t (*FathomSnapshotCallback)(
    const char *name,
    uint32_t name_length,
    void *context
);

/// Lists snapshot names through `fs_snapshot_list(2)`. This is read-only.
int32_t fathom_snapshot_list(
    const char *volume_path,
    FathomSnapshotCallback callback,
    void *context,
    int32_t *error_number
);

/// Mounts one APFS snapshot read-only at an existing mount point.
int32_t fathom_snapshot_mount(
    const char *volume_path,
    const char *mount_path,
    const char *snapshot_name,
    int32_t *error_number
);

/// Unmounts a snapshot previously mounted by fathom_snapshot_mount.
int32_t fathom_snapshot_unmount(
    const char *mount_path,
    int32_t *error_number
);

typedef int32_t (*FathomOpenFileCallback)(
    uint64_t device,
    uint64_t inode,
    void *context
);

/// Enumerates vnode identities held by open process file descriptors.
int32_t fathom_open_file_identities(
    FathomOpenFileCallback callback,
    void *context,
    uint32_t *inaccessible_process_count,
    int32_t *error_number
);

#ifdef __cplusplus
}
#endif

#endif
