const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const config = @import("../config.zig");
const table_count_max = @import("tree.zig").table_count_max;
const snapshot_latest = @import("tree.zig").snapshot_latest;

const ManifestLevel = @import("manifest_level.zig").ManifestLevel;
const NodePool = @import("node_pool.zig").NodePool(config.lsm_manifest_node_size, 16);
const SegmentedArray = @import("segmented_array.zig").SegmentedArray;

pub fn ManifestType(comptime Table: type) type {
    const Key = Table.Key;
    const compare_keys = Table.compare_keys;

    return struct {
        const Manifest = @This();

        pub const TableInfo = extern struct {
            checksum: u128,
            address: u64,
            flags: u64 = 0,

            /// The minimum snapshot that can see this table (with exclusive bounds).
            /// This value is set to the current snapshot tick on table creation.
            snapshot_min: u64,

            /// The maximum snapshot that can see this table (with exclusive bounds).
            /// This value is set to the current snapshot tick on table deletion.
            snapshot_max: u64 = math.maxInt(u64),

            key_min: Key,
            key_max: Key,

            comptime {
                assert(@sizeOf(TableInfo) == 48 + Table.key_size * 2);
                assert(@alignOf(TableInfo) == 16);
            }

            pub fn visible(table: *const TableInfo, snapshot: u64) bool {
                assert(table.address != 0);
                assert(table.snapshot_min < table.snapshot_max);
                assert(snapshot <= snapshot_latest);

                assert(snapshot != table.snapshot_min);
                assert(snapshot != table.snapshot_max);

                return table.snapshot_min < snapshot and snapshot < table.snapshot_max;
            }

            pub fn invisible(table: *const TableInfo, snapshots: []const u64) bool {
                // Return early and do not iterate all snapshots if the table was never deleted:
                if (table.visible(snapshot_latest)) return false;
                for (snapshots) |snapshot| if (table.visible(snapshot)) return false;
                assert(table.snapshot_max < math.maxInt(u64));
                return true;
            }

            pub fn eql(table: *const TableInfo, other: *const TableInfo) bool {
                // TODO Since the layout of TableInfo is well defined, a direct memcmp may be faster
                // here. However, it's not clear if we can make the assumption that compare_keys()
                // will return .eq exactly when the memory of the keys are equal.
                // Consider defining the API to allow this.
                return table.checksum == other.checksum and
                    table.address == other.address and
                    table.flags == other.flags and
                    table.snapshot_min == other.snapshot_min and
                    table.snapshot_max == other.snapshot_max and
                    compare_keys(table.key_min, other.key_min) == .eq and
                    compare_keys(table.key_max, other.key_max) == .eq;
            }
        };

        /// Levels beyond level 0 have tables with disjoint key ranges.
        /// Here, we use a structure with indexes over the segmented array for performance.
        const Level = ManifestLevel(NodePool, Key, TableInfo, compare_keys, table_count_max);

        node_pool: *NodePool,

        levels: [config.lsm_levels]Level,

        // TODO Set this at startup when reading in the manifest.
        // This should be the greatest TableInfo.snapshot_min/snapshot_max (if deleted) or
        // registered snapshot seen so far.
        snapshot_max: u64 = 1,

        pub fn init(allocator: mem.Allocator, node_pool: *NodePool) !Manifest {
            var levels: [config.lsm_levels]Level = undefined;

            for (levels) |*level, i| {
                errdefer for (levels[0..i]) |*l| l.deinit(allocator, node_pool);
                level.* = try Level.init(allocator);
            }

            return Manifest{
                .node_pool = node_pool,
                .levels = levels,
            };
        }

        pub fn deinit(manifest: *Manifest, allocator: mem.Allocator) void {
            for (manifest.levels) |*l| l.deinit(allocator, manifest.node_pool);
        }

        pub const LookupIterator = struct {
            manifest: *Manifest,
            snapshot: u64,
            key: Key,
            level: u8 = 0,
            inner: ?Level.Iterator = null,
            precedence: ?u64 = null,

            pub fn next(it: *LookupIterator) ?*const TableInfo {
                while (it.level < config.lsm_levels) : (it.level += 1) {
                    const level = &it.manifest.levels[it.level];

                    var inner = level.iterator(it.snapshot, it.key, it.key, .ascending);
                    if (inner.next()) |table| {
                        if (it.precedence) |p| assert(p > table.snapshot_min);
                        it.precedence = table.snapshot_min;

                        assert(table.visible(it.snapshot));
                        assert(compare_keys(it.key, table.key_min) != .lt);
                        assert(compare_keys(it.key, table.key_max) != .gt);
                        assert(inner.next() == null);

                        it.level += 1;
                        return table;
                    }
                }

                assert(it.level == config.lsm_levels);
                return null;
            }
        };

        pub fn insert_tables(manifest: *Manifest, level: u8, tables: []const TableInfo) void {
            assert(tables.len > 0);

            const manifest_level = &manifest.levels[level];
            manifest_level.insert_tables(manifest.node_pool, tables);

            // TODO Verify that tables can be found exactly before returning.
        }

        pub fn lookup(manifest: *Manifest, snapshot: u64, key: Key) LookupIterator {
            return .{
                .manifest = manifest,
                .snapshot = snapshot,
                .key = key,
            };
        }

        pub const Range = struct {
            table_count: usize,
            key_min: Key,
            key_max: Key,
        };

        /// Returns the smallest visible range in a level that overlaps the candidate key range.
        /// Returns null if there are no visible overlapping tables in the level.
        /// For example, for a table in level 2, count how many tables overlap in level 3, and
        /// determine the span of their complete key range, which may be broader or narrower.
        pub fn overlap(manifest: *const Manifest, level: u8, key_min: Key, key_max: Key) ?Range {
            assert(level < config.lsm_levels);
            assert(compare_keys(key_min, key_max) != .gt);

            var range: Range = null;

            var it = manifest.levels[level].iterator(snapshot_latest, key_min, key_max, .ascending);
            if (it.next()) |table| {
                assert(table.visible(snapshot_latest));
                assert(compare_keys(table.key_min, table.key_max) != .gt);
                assert(compare_keys(table.key_max, key_min) != .lt);
                assert(compare_keys(table.key_min, key_max) != .gt);

                if (range) |*r| {
                    assert(compare_keys(table.key_min, r.key_max) == .gt);

                    r.table_count += 1;
                    r.key_max = table.key_max;
                } else {
                    range = .{
                        .table_count = 1,
                        .key_min = table.key_min,
                        .key_max = table.key_max,
                    };
                }
            }

            if (range) |r| {
                assert(r.table_count > 0);
                assert(compare_keys(r.key_min, r.key_max) != .gt);
                assert(compare_keys(r.key_max, key_min) != .lt);
                assert(compare_keys(r.key_min, key_max) != .gt);
            }
            return range;
        }

        /// Returns whether a level contains any visible table that overlaps the key range.
        /// For example, this is useful when determining whether to drop tombstones when compacting,
        /// because if no subsequent level has any overlap, then the tombstone may be dropped.
        pub fn overlap_any(manifest: *const Manifest, level: u8, key_min: Key, key_max: Key) bool {
            assert(level < config.lsm_levels);
            assert(compare_keys(key_min, key_max) != .gt);

            var it = manifest.levels[level].iterator(snapshot_latest, key_min, key_max, .ascending);
            return it.next() != null;
        }

        /// Returns a unique snapshot, incrementing the greatest snapshot value seen so far,
        /// whether this was for a TableInfo.snapshot_min/snapshot_max or registered snapshot.
        pub fn take_snapshot(manifest: *Manifest) u64 {
            // A snapshot cannot be 0 as this is a reserved value in the superblock.
            assert(manifest.snapshot_max > 0);
            // The constant snapshot_latest must compare greater than any issued snapshot.
            // This also ensures that we are not about to overflow the u64 counter.
            assert(manifest.snapshot_max < snapshot_latest - 1);

            manifest.snapshot_max += 1;

            return manifest.snapshot_max;
        }
    };
}
