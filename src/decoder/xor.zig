const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("../types.zig");
const Bit = types.Bit;
const StreamError = types.StreamError;
const shift_left = types.shift_left;
const shift_right = types.shift_right;
const float64ToBits = types.float64ToBits;
const float64FromBits = types.float64FromBits;

const constants = @import("../constants.zig");
const StreamReader = @import("../reader.zig").StreamReader;

pub const XorDecoder = struct {
    // current float value bits
    current: ?u64,
    // number of leading zeros
    leading_zeros: u32,
    // number of trailing zeros
    trailing_zeros: u32,
    // reader
    reader: StreamReader,

    pub fn init(bytes: []const u8) StreamError!XorDecoder {
        return XorDecoder{
            .current = null,
            .leading_zeros = 0,
            .trailing_zeros = 0,
            .reader = StreamReader.init(bytes),
        };
    }

    pub fn next(self: *XorDecoder) StreamError!?f64{
        if(self.current == null) { // reading first value
            self.current = self.reader.read_bits(constants.NUM_FIRST_VALUE_BITS) catch |err| {
                return if(err == StreamError.endOfStream) null else err;
            };
            return u64Tof64(self.current);
        }

        return self.decodeSubsequentValue();
    }

    fn decodeSubsequentValue(self: *XorDecoder) StreamError!?f64{
        if(try self.isEndOfRecord()) {
            return null;
        }

        const control_bit = try self.reader.read_bit();

        if(control_bit == .zero) {
            return u64Tof64(self.current);
        }

        const zeros_bit = try self.reader.read_bit();
        if (zeros_bit == .one) {
            self.leading_zeros = @intCast(try self.reader.read_bits(6));
            const significant_bits: u32 = @as(u32, @intCast(try self.reader.read_bits(6))) + 1;
            self.trailing_zeros = 64 - self.leading_zeros - significant_bits;
        }

        const size = 64 - self.leading_zeros - self.trailing_zeros;
        const value_bits = try self.reader.read_bits(size);
        self.current = self.current.? ^ shift_left(u64, value_bits, self.trailing_zeros);
        return u64Tof64(self.current);
    }

    fn isEndOfRecord(self: *XorDecoder) StreamError!bool {
        const end_records_control_bits = try self.reader.peek_bits(constants.END_RECORDS_CONTROL_BITS_SIZE, null);
        if(end_records_control_bits != constants.END_RECORDS_CONTROL_BITS){
            return false;
        }

        const end_records_marker = try self.reader.peek_bits(constants.END_RECORDS_MARKER_SIZE, constants.END_RECORDS_CONTROL_BITS_SIZE);
        if(end_records_marker != constants.END_RECORDS_MARKER){
            return false;
        }
        return true;
    }

    inline fn u64Tof64(v: ?u64) ?f64 {
        if(v) |payload| {
            return float64FromBits(payload);
        } else {
            return null;
        }
    }

};


test "test_create_decoder" {
    const testing = std.testing;
    const bytes = [_]u8{
        255, 255, 255, 255, 240
    };
    var decoder = try XorDecoder.init(&bytes);

    try testing.expectEqual(@as(?f64, null), (try decoder.next())); 
}

test "test_decode_value" {
    const testing = std.testing;
    const bytes = [_]u8{
        64, 4, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 240
    };
    var decoder = try XorDecoder.init(&bytes);

    try testing.expectEqual(@as(?f64, 2.5), (try decoder.next())); 
    try testing.expectEqual(@as(?f64, null), (try decoder.next())); 
}

test "test_decode_multiple_values" {
    const testing = std.testing;
    const bytes = [_]u8{ 
        63, 243, 215, 10, 61, 112, 163, 215, 204, 207, 30, 71, 145, 228, 121, 30, 112,
        123, 255, 250, 183, 173, 235, 122, 222, 188, 15, 160, 7, 213, 133, 97, 88, 86,
        20, 208, 8, 136, 122, 225, 71, 174, 20, 191, 255, 255, 255, 252
    };
    var decoder = try XorDecoder.init(&bytes);

    const expected_ts = [_]f64{
        1.24,
        1.98,
        2.37,
        -7.41,
        103.50,
    };

    var actual_ts = [5]f64{0,0,0,0,0};
    for(&actual_ts) |*ts| {
        ts.* = (try decoder.next()).?;
    }

    // for(0..14) |_|{
    //     _ = try decoder.next();
    // }
    
    try testing.expectEqual(@as(?f64, null), (try decoder.next())); 
    try testing.expectEqualSlices(f64, expected_ts[0..], actual_ts[0..]);    
}
