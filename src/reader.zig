const std = @import("std");


const types = @import("./types.zig");
const Bit = types.Bit;
const StreamError = types.StreamError;
const shift_left = types.shift_left;
const shift_right = types.shift_right;

pub const StreamReader = struct {
    // data buffer
    data: []const u8,
    // index into data buffer
    index: usize,
    // position within the currently read byte
    pos: u32,

    pub fn init(bytes: []const u8) StreamReader {
        return StreamReader{
            .data = bytes,
            .index = 0,
            .pos = 0,
        };
    }

    fn get_byte(self: StreamReader) StreamError!u8 {
        if (self.index >= self.data.len) {
            return StreamError.endOfStream;
        }
        return self.data[self.index];
    }

    fn is_empty(self: StreamReader) bool {
        return self.data.len == 0 or self.pos == 8;
    }

    pub fn read_bit(self: *StreamReader) StreamError!Bit {
        if (self.is_empty()) {
            self.index += 1;
            self.pos = 0;
        }

        const byte = try self.get_byte();
        const bit = if (byte & shift_left(u8, 1, 7 - self.pos) == 0) Bit.zero else Bit.one;

        self.pos += 1;

        return bit;
    }

    pub fn read_byte(self: *StreamReader) StreamError!u8 {
        if (self.pos == 0) {
            self.pos += 8;
            return self.get_byte();
        }

        if (self.is_empty()) {
            self.index += 1;
            return self.get_byte();
        }

        var byte: u8 = 0;
        var b = try self.get_byte();

        byte |= shift_left(u8, b, self.pos);

        self.index += 1;
        b = try self.get_byte();

        byte |= shift_right(u8, b, 8 - self.pos);

        return byte;
    }

    pub fn read_bits(self: *StreamReader, num: u32) StreamError!u64 {
        // Never read more than 64 bits into a u64
        var num_bits_left = if (num > 64) 64 else num;

        var bits: u64 = 0;
        while (num_bits_left >= 8) {
            const byte: u64 = @as(u64, try self.read_byte());
            bits = (bits << 8) | byte;
            num_bits_left -= 8;
        }

        while (num_bits_left > 0) {
            const bit = try self.read_bit();
            bits = bits << 1 | bit.to_u64();
            num_bits_left -= 1;
        }

        return bits;
    }

    pub fn peek_bits(self: *StreamReader, num: u32, skip: ?u32,) StreamError!u64 {
        // store the current index and pos, so we can reset later.
        const index = self.index;
        const pos = self.pos;

        if(skip) |skip_value| {
            _ = try self.read_bits(skip_value);
        }
        const bits = try self.read_bits(num);

        self.index = index;
        self.pos = pos;

        return bits;
    }
};

test "test_read_bit" {
    const testing = std.testing;
    const bytes = [_]u8{ 0b01101100, 0b11101001 };
    var b = StreamReader.init(&bytes);

    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());

    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
}

test "test_read_byte" {
    const testing = std.testing;
    const bytes = [_]u8{ 100, 25, 0, 240, 240 };
    var b = StreamReader.init(&bytes);

    try testing.expectEqual(@as(u8, 100), try b.read_byte());
    try testing.expectEqual(@as(u8, 25), try b.read_byte());
    try testing.expectEqual(@as(u8, 0), try b.read_byte());

    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());
    try testing.expectEqual(Bit.one, try b.read_bit());

    try testing.expectEqual(@as(u8, 15), try b.read_byte());
    try testing.expectError(StreamError.endOfStream, b.read_byte());
}

test "test_read_bits" {
    const testing = std.testing;
    const bytes = [_]u8{ 0b01010111, 0b00011101, 0b11110101, 0b00010100 };
    var b = StreamReader.init(&bytes);

    try testing.expectEqual(@as(u64, 0b010), try b.read_bits(3));
    try testing.expectEqual(@as(u64, 0b1), try b.read_bits(1));
    try testing.expectEqual(@as(u64, 0b01110001110111110101), try b.read_bits(20));
    try testing.expectEqual(@as(u64, 0b00010100), try b.read_bits(8));
    try testing.expectError(StreamError.endOfStream, b.read_bits(4));
}

test "test_read_mixed" {
    const testing = std.testing;
    const bytes = [_]u8{ 0b01101101, 0b01101101 };
    var b = StreamReader.init(&bytes);

    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(@as(u64, 0b110), try b.read_bits(3));
    try testing.expectEqual(@as(u8, 0b11010110), try b.read_byte());
    try testing.expectEqual(@as(u64, 0b11), try b.read_bits(2));
    try testing.expectEqual(Bit.zero, try b.read_bit());
    try testing.expectEqual(@as(u64, 0b1), try b.read_bits(1));
    try testing.expectError(StreamError.endOfStream, b.read_bit());
}

test "test_peek_bits" {
    const testing = std.testing;
    const bytes = [_]u8{ 0b01010111, 0b00011101, 0b11110101, 0b00010100 };
    var b = StreamReader.init(&bytes);

    try testing.expectEqual(@as(u64, 0b0), try b.peek_bits(1, null));
    try testing.expectEqual(@as(u64, 0b0101), try b.peek_bits(4, null));
    try testing.expectEqual(@as(u64, 0b01010111), try b.peek_bits(8, null));
    try testing.expectEqual(@as(u64, 0b01010111000111011111), try b.peek_bits(20, null));

    try testing.expectEqual(@as(u64, 0b010101110001), try b.read_bits(12));

    try testing.expectEqual(@as(u64, 0b1), try b.peek_bits(1, null));
    try testing.expectEqual(@as(u64, 0b1101), try b.peek_bits(4, null));
    try testing.expectEqual(@as(u64, 0b11011111), try b.peek_bits(8, null));
    try testing.expectEqual(@as(u64, 0b11011111010100010100), try b.peek_bits(20, null));

    try testing.expectError(StreamError.endOfStream, b.peek_bits(22, null));
}
