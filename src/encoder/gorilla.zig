const std = @import("std");
const Allocator = std.mem.Allocator;

const DeletaOfDeltaEncoder = @import("./dod.zig").DeltaOfDetaEncoder;
const XorEncoder = @import("./xor.zig").XorEncoder;

const types = @import("../types.zig");
const DataPoint = types.DataPoint;
const StreamError = types.StreamError;

pub const GorillaEncoder = struct {
    timestamp_encoder: DeletaOfDeltaEncoder,
    value_encoder: XorEncoder,

    pub fn init(allocator: Allocator, start: u64) StreamError!GorillaEncoder {
        return GorillaEncoder{
            .timestamp_encoder = try DeletaOfDeltaEncoder.init(allocator, start), 
            .value_encoder = XorEncoder.init(allocator),
        };
    }

    pub fn with_capacity(allocator: Allocator, capacity: usize, start: u64) StreamError!GorillaEncoder {
        return XorEncoder{
            .timestamp_encoder = try DeletaOfDeltaEncoder.with_capacity(allocator, capacity, start), 
            .value_encoder = XorEncoder.init(allocator),
        };
    }

    pub fn deinit(self: GorillaEncoder) void {
        self.timestamp_encoder.deinit();
        self.value_encoder.deinit();
    }

    pub fn encode(self: *GorillaEncoder, data_point: DataPoint) Allocator.Error!void{
        try self.timestamp_encoder.encode(data_point.timestamp);
        try self.value_encoder.encode(data_point.value);
    }

    pub fn finish(self: *GorillaEncoder) Allocator.Error! [2][] const u8 {
        const timestamps_bytes = try self.timestamp_encoder.finish();
        const values_bytes = try self.value_encoder.finish();
        return .{ timestamps_bytes, values_bytes };
    }

};
