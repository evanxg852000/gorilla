const std = @import("std");
const Allocator = std.mem.Allocator;

const constants = @import("../constants.zig");
const StreamWriter = @import("../writer.zig").StreamWriter;

pub const DeltaOfDetaEncoder = struct {
    // start timestamp
    header: u64,
    // current time
    time: u64,
    // current time delta
    delta: u64,
    // writer
    writer: StreamWriter,

    pub fn init(allocator: Allocator, start: u64) Allocator.Error!DeltaOfDetaEncoder {
        var encoder = DeltaOfDetaEncoder{
            .header = start,
            .time = 0,
            .delta = 0,
            .writer = StreamWriter.init(allocator),
        };
        try encoder.writer.write_bits(start, 64);
        return encoder;
    }

    pub fn with_capacity(allocator: Allocator, capacity: usize, start: u64) Allocator.Error!DeltaOfDetaEncoder {
        var encoder = DeltaOfDetaEncoder{
            .header = start,
            .time = 0,
            .delta = 0,
            .is_first = true,
            .writer = StreamWriter.with_capacity(allocator, capacity),
        };
        try encoder.writer.write_bits(start, 64);
        return encoder;
    }

    pub fn deinit(self: DeltaOfDetaEncoder) void {
        self.writer.deinit();
    }

    pub fn encode(self: *DeltaOfDetaEncoder, time: u64) Allocator.Error!void{
        if(self.time == 0) { // registering first timestamp
            // assert(time >= self.header)
            self.delta = time - self.header;
            self.time = time;
            try self.writer.write_bits(self.delta, constants.NUM_FIRST_DELTA_BITS);
            return;
        }
        return self.encodeSubsequentTimestamp(time);
    }

    pub fn finish(self: *DeltaOfDetaEncoder) Allocator.Error![] const u8 {
        if(self.time == 0) { // closing without a registered item
            // Add finish marker with delta = constants.DELTA_NO_RECORDS_MARKER (firstDeltaBits = 14 bits)
            try self.writer.write_bits(constants.DELTA_NO_RECORDS_MARKER, constants.NUM_FIRST_DELTA_BITS);
            return self.writer.as_slice();
        }

        // Add finish marker with deltaOfDelta = constants.DELTA_END_RECORDS_MARKER
        try self.writer.write_bits(constants.DELTA_END_RECORDS_CONTROL_BITS, constants.DELTA_END_RECORDS_CONTROL_BITS_SIZE);
        try self.writer.write_bits(constants.DELTA_END_RECORDS_MARKER, constants.DELTA_END_RECORDS_MARKER_SIZE);
        return self.writer.as_slice();
    }

    fn encodeSubsequentTimestamp(self: * DeltaOfDetaEncoder, time: u64) Allocator.Error!void{
        const delta = time - self.time;
        const delta_of_delta: u64 = @intCast(delta -% self.delta);
        self.time = time;
        self.delta = delta;

        if (delta_of_delta == 0) {
            try self.writer.write_bit(.zero);
        } else if (-63 <= delta_of_delta and delta_of_delta <= 64) {
            try self.writer.write_bits(0b10, 2);
            try self.writer.write_bits(delta_of_delta, 7);
        } else if (-255 <= delta_of_delta and delta_of_delta <= 256) {
            try self.writer.write_bits(0b110, 3);
            try self.writer.write_bits(delta_of_delta, 9);
        } else if (-2047 <= delta_of_delta and delta_of_delta <= 2048) {
            try self.writer.write_bits(0b1110, 4);
            try self.writer.write_bits(delta_of_delta, 12);
        } else {
            try self.writer.write_bits(0b1111, 4);
            try self.writer.write_bits(delta_of_delta, 32);
        }
    }

};


test "test_create_encoder" {
    const testing = std.testing;
    const start_time = 1482268055; // 2016-12-20T21:07:35+00:00
    var encoder = try DeltaOfDetaEncoder.init(testing.allocator, start_time);
    defer encoder.deinit();

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{0, 0, 0, 0, 88, 89, 157, 151, 255, 252};
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}

test "test_encode_timestamp" {
    const testing = std.testing;
    const start_time = 1482268055; // 2016-12-20T21:07:35+00:00
    var encoder = try DeltaOfDetaEncoder.init(testing.allocator, start_time);
    defer encoder.deinit();

    try encoder.encode(1482268055 + 5);

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{
        0, 0, 0, 0, 88, 89, 157, 151, 0, 23, 255, 255, 255, 255, 192,
    };
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}

test "test_encode_multiple_timestamps" {
    const testing = std.testing;
    const start_time = 1482268055; // 2016-12-20T21:07:35+00:00
    var encoder = try DeltaOfDetaEncoder.init(testing.allocator, start_time);
    defer encoder.deinit();

    try encoder.encode(1482268055 + 10);
    try encoder.encode(1482268055 + 20);
    try encoder.encode(1482268055 + 32);
    try encoder.encode(1482268055 + 44);
    try encoder.encode(1482268055 + 52);

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{
        0, 0, 0, 0, 88, 89, 157, 151, 0, 41, 2, 127, 255, 255, 255, 
        231, 255, 255, 255, 255, 128,
    };
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}
