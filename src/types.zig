const std = @import("std");

pub const DataPoint = struct {
    timestamp: u64,
    value: f64,
};

pub const Bit = enum {
    zero,
    one,

    pub fn to_u64(self: Bit) u64 {
        return switch (self) {
            .zero => 0,
            .one => 1,
        };
    }
};

pub const StreamError = error{
    endOfStream,
} || std.mem.Allocator.Error;

pub inline fn shift_left(comptime T: type, lhs: T, rhs: u32) T {
    return @as(T, lhs) << @intCast(rhs);
}

pub inline fn shift_right(comptime T: type, lhs: T, rhs: u32) T {
    return @as(T, lhs) >> @intCast(rhs);
}

// Performs a reinterpret(transmute) from float to u64
pub fn float64ToBits(num: f64) u64 {
    const num_ptr: *u64 = @ptrCast(@constCast(&num));
    return num_ptr.*;
}

// Performs a reinterpret(transmute) from u64 to float
pub fn float64FromBits(num: u64) f64 {
    const num_ptr: *f64 = @ptrCast(@constCast(&num));
    return num_ptr.*;
}

test "test_bit" {
    const testing = std.testing;

    const zero = Bit.zero;
    try testing.expectEqual(zero.to_u64(), 0);

    const one = Bit.one;
    try testing.expectEqual(one.to_u64(), 1);
}

test "test_transmute_float_to_u64" {
    const testing = std.testing;
    const value = float64ToBits(std.math.pi);
    try testing.expectEqual(float64FromBits(value), std.math.pi);
}
