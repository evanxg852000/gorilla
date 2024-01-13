const std = @import("std");
const Allocator = std.mem.Allocator;

const constants = @import("../constants.zig");
const StreamWriter = @import("../writer.zig").StreamWriter;

const types = @import("../types.zig");
const Bit = types.Bit;
const StreamError = types.StreamError;
const shift_left = types.shift_left;
const shift_right = types.shift_right;
const float64ToBits = types.float64ToBits;
const float64FromBits = types.float64FromBits;

pub const XorEncoder = struct {
    // current float value bits
    current: ?u64,
    // number of leading zeros
    leading_zeros: u32,
    // number of trailing zeros
    trailing_zeros: u32,
    // writer
    writer: StreamWriter,

    pub fn init(allocator: Allocator) XorEncoder {
        return XorEncoder{
            .current = null,
            .leading_zeros= 64, // initial sentinel value of 64
            .trailing_zeros= 64,
            .writer = StreamWriter.init(allocator),
        };
    }

    pub fn with_capacity(allocator: Allocator, capacity: usize) XorEncoder {
        return XorEncoder{
            .current = null,
            .leading_zeros= 64, // initial sentinel value of 64
            .trailing_zeros= 64,
            .writer = StreamWriter.with_capacity(allocator, capacity),
        };
    }

    pub fn deinit(self: XorEncoder) void {
        self.writer.deinit();
    }

    pub fn encode(self: *XorEncoder, value: f64) Allocator.Error!void{
        if(self.current == null) { // registering first value
            self.current = float64ToBits(value);
            return self.writer.write_bits(self.current.?, constants.NUM_FIRST_VALUE_BITS);
        }
        return self.encodeSubsequentValue(value);
    }

    pub fn finish(self: *XorEncoder) Allocator.Error![] const u8 {
        try self.writer.write_bits(constants.END_RECORDS_CONTROL_BITS, constants.END_RECORDS_CONTROL_BITS_SIZE);
        try self.writer.write_bits(constants.END_RECORDS_MARKER, constants.END_RECORDS_MARKER_SIZE);
        return self.writer.as_slice();
    }

    fn encodeSubsequentValue(self: * XorEncoder, value: f64) Allocator.Error!void{
        const value_bits = float64ToBits(value);
        const xor: u64 =  value_bits ^ self.current.?;
        self.current = value_bits;

        if(xor == 0) {
            return self.writer.write_bit(.zero);
        }

        try self.writer.write_bit(.one);
        const leading_zeros: u8 = @clz(xor);
        const trailing_zeros: u8 = @ctz(xor);

        // If the number of leading and trailing zeros in this xor are >= the leading and
        // trailing zeros in the previous xor then we only need to store a control bit and
        // the significant digits of this xor
        if (self.leading_zeros <= leading_zeros and self.trailing_zeros <= trailing_zeros) {
            try self.writer.write_bit(.zero);
            const significat_bits = 64 - self.leading_zeros - self.trailing_zeros;
            return self.writer.write_bits(shift_right(u64, xor, self.trailing_zeros), significat_bits);
        }
        

        // If the number of leading and trailing zeros in this xor are not less than the
        // leading and trailing zeros in the previous xor then we store a control bit and
        // use 6 bits to store the number of leading zeros and 6 bits to store the number
        // of significant digits before storing the significant digits themselves
        try self.writer.write_bit(.one);
        try self.writer.write_bits(@as(u64, leading_zeros), 6);

        // If significant_digits is 64 we cannot encode it using 6 bits, however since
        // significant_digits is guaranteed to be at least 1 we can subtract 1 to ensure
        // significant_digits can always be expressed with 6 bits or less
        const significat_bits = 64 - leading_zeros - trailing_zeros;
        try self.writer.write_bits(@as(u64, significat_bits-1), 6);
        try self.writer.write_bits(shift_right(u64, xor, trailing_zeros), significat_bits);

        self.leading_zeros = leading_zeros;
        self.trailing_zeros = trailing_zeros;
    }

};


test "test_create_encoder" {
    const testing = std.testing;
    var encoder = XorEncoder.init(testing.allocator);
    defer encoder.deinit();

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{
        255, 255, 255, 255, 240
    };
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}

test "test_encode_value" {
    const testing = std.testing;
    var encoder = XorEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(2.5);

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{
        64, 4, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 240
    };
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}

test "test_encode_multiple_values" {
    const testing = std.testing;
    var encoder = XorEncoder.init(testing.allocator);
    defer encoder.deinit();

    try encoder.encode(1.24);
    try encoder.encode(1.98);
    try encoder.encode(2.37);
    try encoder.encode(-7.41);
    try encoder.encode(103.50);

    const bytes = try encoder.finish();
    const expected_bytes = [_]u8{
        63, 243, 215, 10, 61, 112, 163, 215, 204, 207, 30, 71, 145, 228, 121, 30, 112,
        123, 255, 250, 183, 173, 235, 122, 222, 188, 15, 160, 7, 213, 133, 97, 88, 86,
        20, 208, 8, 136, 122, 225, 71, 174, 20, 191, 255, 255, 255, 252
    };
    try testing.expectEqualSlices(u8, expected_bytes[0..], bytes);
}
