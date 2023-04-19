const std = @import("std");
const tb = @import("../../tigerbeetle.zig");
const tb_client = @import("../c/tb_client.zig");

const output_file = "src/clients/rust/src/types/bindings.rs";

const type_mappings = .{
    .{ tb.AccountFlags, "AccountFlags" },
    .{ tb.TransferFlags, "TransferFlags" },
    .{ tb.Account, "Account" },
    .{ tb.Transfer, "Transfer" },
    .{ tb.CreateAccountResult, "CreateAccountResult" },
    .{ tb.CreateTransferResult, "CreateTransferResult" },
    .{ tb.CreateAccountsResult, "AccountEventResult" },
    .{ tb.CreateTransfersResult, "TransferEventResult" },
    .{ tb_client.tb_operation_t, "Operation" },
};

fn get_mapped_type_name(comptime Type: type) ?[]const u8 {
    inline for (type_mappings) |type_mapping| {
        if (Type == type_mapping[0]) {
            return type_mapping[1];
        }
    } else return null;
}

fn rust_type(comptime Type: type) []const u8 {
    switch (@typeInfo(Type)) {
        .Enum => return comptime get_mapped_type_name(Type) orelse @compileError("Type " ++ @typeName(Type) ++ " not mapped."),
        .Struct => |info| switch (info.layout) {
            .Packed => return comptime rust_type(std.meta.Int(.unsigned, @bitSizeOf(Type))),
            else => return comptime get_mapped_type_name(Type) orelse @compileError("Type " ++ @typeName(Type) ++ " not mapped."),
        },
        .Int => |info| {
            std.debug.assert(info.signedness == .unsigned);
            return switch (info.bits) {
                8 => "u8",
                16 => "u16",
                32 => "u32",
                64 => "u64",
                128 => "u128",
                else => @compileError("invalid int type"),
            };
        },
        else => @compileError("Unhandled type: " ++ @typeName(Type)),
    }
}

// TODO:
// fn emit_docs(buffer: anytype, comptime mapping: TypeMapping, comptime indent: comptime_int, comptime field: ?[]const u8) !void {
//     if (mapping.docs_link) |docs_link| {
//         try buffer.writer().print(
//             \\
//             \\{[indent]s}//! [name]
//             \\{[indent]s}//!
//             \\{[indent]s}//! See [{[name]s}](https://docs.tigerbeetle.com/{[docs_link]s}{[field]s})
//             \\
//         , .{
//             .indent = "  " ** indent,
//             .name = field orelse mapping.name,
//             .docs_link = docs_link,
//             .field = field orelse "",
//         });
//     }
// }

/// Emit new packed `struct` to `buffer` using `type_info`.
fn emit_packed_struct(buffer: *std.ArrayList(u8), comptime type_info: anytype, comptime name: []const u8, comptime int_type: []const u8) !void {
    _ = int_type;
    // TODO: emit docs
    try buffer.writer().print(
        \\
        \\ /// {name}
        \\#[repr(C, packed)]
        \\#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
        \\pub struct {name} {{
        \\
    , .{ .name = name });
    inline for (type_info.fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "padding")) continue;
        try buffer.writer().print(
            \\{indent}///
            \\{indent}pub {field_name}: {field_type},
            \\
        , .{ .indent = "    ", .field_name = field.name, .field_type = rust_type(field.field_type) });
    }
    try buffer.writer().print(
        \\
        \\{indent}}}
        \\
    , .{ .indent = "    " });
}

/// Emit new `struct` to `buffer` using `type_info`.
fn emit_struct(buffer: *std.ArrayList(u8), comptime type_info: anytype, comptime name: []const u8) !void {
    // TODO: emit docs
    try buffer.writer().print(
        \\
        \\ /// {name}
        \\#[repr(C)]
        \\#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
        \\pub struct {name} {{
        \\
    , .{ .name = name });
    var flags_field = false;
    inline for (type_info.fields) |field| {
        switch (@typeInfo(field.field_type)) {
            .Array => |array| {
                try buffer.writer().print(
                    \\{indent}/// 
                    \\{indent}pub {name}: [{field_type}; {len}],
                    \\
                , .{ .indent = "    ", .name = field.name, .field_type = rust_type(array.child), .len = array.len });
            },
            else => {
                if (comptime std.mem.eql(u8, field.name, "flags")) {
                    flags_field = true;
                }
                try buffer.writer().print(
                    \\{indent}///
                    \\{indent}pub {field_name}: {field_type},
                    \\
                , .{ .indent = "    ", .field_name = field.name, .field_type = rust_type(field.field_type) });
            },
        }
    }

    // TODO: add flags function
}

/// Emit new `enum` to `buffer` using `type_info`.
fn emit_enum(buffer: *std.ArrayList(u8), comptime type_info: anytype, comptime name: []const u8, comptime int_type: []const u8) !void {
    _ = type_info;
    try buffer.writer().print(
        \\
        \\ /// {name}
        \\#[repr({int_type})]
        \\#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
        \\pub enum {name} {{
        \\
    , .{ .name = name, .int_type = int_type });
}

pub fn generate_bindings(buffer: *std.ArrayList(u8)) !void {
    @setEvalBranchQuota(100_000);

    // TODO: emit header docs that depends on the client language
    try buffer.writer().print(
        \\///////////////////////////////////////////////////////
        \\// This file was auto-generated by rust_bindings.zig //
        \\//              Do not manually modify.              //
        \\///////////////////////////////////////////////////////
        \\
        \\ //! TigerBeetle Rust Client Type Bindings
        \\
        \\ use super::bindings::*;
    , .{});

    inline for (type_mappings) |type_mapping| {
        const ZigType = type_mapping[0];
        const name = type_mapping[1]; // TODO: this can generally be a struct that includes more than the name
        switch (@typeInfo(ZigType)) {
            .Struct => |info| switch (info.layout) {
                .Auto => @compileError("Only packed or extern structs are supported: " ++ @typeName(ZigType)),
                .Packed => try emit_packed_struct(buffer, info, name, comptime rust_type(std.meta.Int(.unsigned, @bitSizeOf(ZigType)))),
                .Extern => try emit_struct(buffer, info, name),
            },
            .Enum => |info| try emit_enum(buffer, info, name, comptime rust_type(std.meta.Int(.unsigned, @bitSizeOf(ZigType)))),
            else => @compileError("Type cannot be represented: " ++ @typeName(ZigType)),
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var buffer = std.ArrayList(u8).init(allocator);
    try generate_bindings(&buffer);
    try std.fs.cwd().writeFile(output_file, buffer.items);
}

const testing = std.testing;

test "bindings rust" {
    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();
    try generate_bindings(&buffer);
    const current = try std.fs.cwd().readFileAlloc(testing.allocator, output_file, std.math.maxInt(usize));
    defer testing.allocator.free(current);
    try testing.expectEqualStrings(current, buffer.items);
}
