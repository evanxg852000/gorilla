const std = @import("std");
const Allocator = std.mem.Allocator;

const DeletaOfDeltaDecoder = @import("./dod.zig").DeltaOfDetaDecoder;
const XorDecoder = @import("./xor.zig").XorDecoder;

const types = @import("../types.zig");
const DataPoint = types.DataPoint;
const StreamError = types.StreamError;

pub const GorillaDecoder = struct {
    timestamp_decoder: DeletaOfDeltaDecoder,
    value_decoder: XorDecoder,

    pub fn init(timestamps_bytes: []const u8, values_bytes: []const u8) StreamError!GorillaDecoder {
        return GorillaDecoder{
            .timestamp_decoder = try DeletaOfDeltaDecoder.init(timestamps_bytes),
            .value_decoder = try XorDecoder.init(values_bytes),
        };
    }

    pub fn next(self: *GorillaDecoder) StreamError!?DataPoint {
        const timestamp =  try self.timestamp_decoder.next() orelse return null;
        const value = try self.value_decoder.next() orelse return null;
        return DataPoint{
            .timestamp = timestamp,
            .value = value,
        };
    }

};

