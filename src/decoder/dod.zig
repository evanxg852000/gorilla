const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("../types.zig");
const Bit = types.Bit;
const StreamError = types.StreamError;
const shift_left = types.shift_left;
const shift_right = types.shift_right;

const constants = @import("../constants.zig");
const StreamReader = @import("../reader.zig").StreamReader;

pub const DeltaOfDetaDecoder = struct {
    // start timestamp
    header: u64,
    // current time
    time: u64,
    // current time delta
    delta: u64,
    // reader
    reader: StreamReader,

    pub fn init(bytes: []const u8) StreamError!DeltaOfDetaDecoder {
        var decoder = DeltaOfDetaDecoder{
            .header = 0,
            .time = 0,
            .delta = 0,
            .reader = StreamReader.init(bytes),
        };
        decoder.header = try decoder.reader.read_bits(64);
        return decoder;
    }

    pub fn next(self: *DeltaOfDetaDecoder) StreamError!?u64{
        if(self.time == 0) { // reading first timestamp
            const delta = try self.reader.read_bits(constants.NUM_FIRST_DELTA_BITS);
            if(delta == constants.DELTA_NO_RECORDS_MARKER) {
                return null;
            }

            self.delta = delta;
            self.time = self.header + self.delta;
            return self.time;
        }

        return self.decodeSubsequentTimestamp();
    }

    fn decodeSubsequentTimestamp(self: *DeltaOfDetaDecoder) StreamError!?u64{
        var control_bits: u32 = 0;
        for (0..4)|_|{
            const bit = try self.reader.read_bit();
            if(bit == .one) {
                control_bits += 1;
            } else {
                break;
            }
        }
        
        const size: u32 = switch (control_bits) {
            0 => {
                self.time += self.delta;
                return self.time;
            },
            1 => 7,
            2 => 9,
            3 => 12,
            4 => 32,
            else => unreachable,
        };

        var delta_of_delta = try self.reader.read_bits(size);
        if (size == 32 and delta_of_delta == constants.DELTA_END_RECORDS_MARKER) {
            return null;
        }

        // we need to sign extend negative numbers
        if (delta_of_delta > shift_left(u64, 1, size - 1) ){
            const mask = shift_left(u64, std.math.maxInt(u64), size);
            delta_of_delta |= mask;
        }

        // by performing a wrapping_add we can ensure that 
        // negative numbers will be handled correctly
        self.delta +%= delta_of_delta;
        self.time +%= self.delta; 
        return self.time;
    }

};


test "test_create_decoder" {
    const testing = std.testing;
    const bytes = [_]u8{0, 0, 0, 0, 88, 89, 157, 151, 255, 252, 0, 0};
    var decoder = try DeltaOfDetaDecoder.init(&bytes);

    try testing.expectEqual(@as(?u64, null), (try decoder.next())); 
}

test "test_decode_timestamp" {
    const testing = std.testing;
    const bytes = [_]u8{
        0, 0, 0, 0, 88, 89, 157, 151, 0, 23, 255, 255, 255, 255, 192,
    };
    var decoder = try DeltaOfDetaDecoder.init(&bytes);

    try testing.expectEqual(@as(?u64, 1482268055 + 5), (try decoder.next())); 
    try testing.expectEqual(@as(?u64, null), (try decoder.next())); 
}

test "test_decode_multiple_timestamps" {
    const testing = std.testing;
    const bytes = [_]u8{ 
        0, 0, 0, 0, 88, 89, 157, 151, 0, 41, 2, 127, 255, 255, 255, 
        231, 255, 255, 255, 255, 128,
    };
    var decoder = try DeltaOfDetaDecoder.init(&bytes);

    const expected_ts = [_]u64{
        1482268055 + 10, // 1482268055 -> 2016-12-20T21:07:35+00:00
        1482268055 + 20,
        1482268055 + 32,
        1482268055 + 44,
        1482268055 + 52,
    };

    var actual_ts = [5]u64{0,0,0,0,0};
    for(&actual_ts) |*ts| {
        ts.* = (try decoder.next()).?;
    }

    try testing.expectEqual(@as(?u64, null), (try decoder.next())); 
    try testing.expectEqualSlices(u64, expected_ts[0..], actual_ts[0..]);    
}
