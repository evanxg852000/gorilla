const std = @import("std");
const Allocator = std.mem.Allocator;
const ByteArray = std.ArrayList(u8);

const types = @import("./types.zig");
const Bit = types.Bit;
const StreamError = types.StreamError;
const shift_left = types.shift_left;
const shift_right = types.shift_right;

pub const StreamWriter = struct {
    // data buffer
    data: ByteArray,
    // position within the last byte in the buffer
    pos: u32,

    pub fn init(allocator: Allocator) StreamWriter {
        return StreamWriter{
            .data = ByteArray.init(allocator),
            .pos = 8,
        };
    }

    pub fn with_capacity(allocator: Allocator, capacity: usize) Allocator.Error!StreamWriter {
        return StreamWriter{
            .data = try ByteArray.initCapacity(allocator, capacity),
            .pos = 8,
        };
    }

    pub fn deinit(self: StreamWriter) void {
        self.data.deinit();
    }

    fn grow(self: *StreamWriter) Allocator.Error!void {
        try self.data.append(0);
    }

    fn last_index(self: StreamWriter) usize {
        return self.data.items.len - 1;
    }

    fn is_full(self: StreamWriter) bool {
        return self.pos == 8;
    }

    pub fn write_bit(self: *StreamWriter, bit: Bit) Allocator.Error!void {
        if(self.is_full()) {
            try self.grow();
            self.pos = 0;
        }

        const idx = self.last_index();

        switch (bit) {
            .zero => {},
            .one => self.data.items[idx] |= shift_left(u8, 1, 7 - self.pos)
        }
    
        self.pos += 1;
    }

    pub fn write_byte(self: *StreamWriter, byte: u8) Allocator.Error!void {
        if(self.is_full()) {
            try self.grow();
            const idx = self.last_index();
            self.data.items[idx] = byte;
            return;
        }

        const idx = self.last_index();
        self.data.items[idx] |= shift_right(u8, byte, self.pos);

        try self.grow();

        self.data.items[idx + 1] |= shift_left(u8, byte, 8 - self.pos);
    }

    pub fn write_bits(self: *StreamWriter, bits: u64, num: u32) Allocator.Error!void {
        // Never write more than 64 bits for a u64
        var num_bits_left = if (num > 64) 64 else num;
        var bits_left = bits;

        bits_left = shift_left(u64, bits, 64-num_bits_left);
        while(num_bits_left >= 8) {
            const byte = shift_right(u64, bits_left, 56);
            try self.write_byte(@intCast(byte));

            bits_left = shift_left(u64, bits_left, 8);
            num_bits_left -= 8;
        }

        while (num_bits_left > 0) {
            const byte = shift_right(u64, bits_left, 63);
            if (byte == 1) {
                try self.write_bit(.one);
            } else {
                try self.write_bit(.zero);
            }

            bits_left = shift_left(u64, bits_left, 1);
            num_bits_left -= 1;
        }
    }

    pub fn as_slice(self: StreamWriter) []u8 {
        return self.data.items;
    } 

};


test "test_write_bit" {
    const testing = std.testing;
    var b = StreamWriter.init(testing.allocator);
    defer b.deinit();

    // 170 = 0b10101010
    for (0..8) |i| {
        if (i % 2 == 0) {
            try b.write_bit(.one);
            continue;
        }

        try b.write_bit(.zero);
    }

    // 146 = 0b10010010
    for (0..8) |i| {
        if(i%3 == 0) {
            try b.write_bit(.one);
            continue;
        }

        try b.write_bit(.zero);
    } 

    // 136 = 010001000
    for (0..8) |i| {
        if(i%4 == 0) {
            try b.write_bit(.one);
            continue;
        }

        try b.write_bit(.zero);
    }

    const data = b.as_slice();
    try testing.expectEqual(@as(usize, 3), data.len);

    try testing.expectEqual(@as(u8, 170), data[0]);
    try testing.expectEqual(@as(u8, 146), data[1]);
    try testing.expectEqual(@as(u8, 136), data[2]);
}

test "test_write_byte" {
    const testing = std.testing;
    var b = StreamWriter.init(testing.allocator);
    defer b.deinit();

    try b.write_byte(234);
    try b.write_byte(188);
    try b.write_byte(77);

    var data = b.as_slice();
    try testing.expectEqual(@as(usize, 3), data.len);

    try testing.expectEqual(@as(u8, 234), data[0]);
    try testing.expectEqual(@as(u8, 188), data[1]);
    try testing.expectEqual(@as(u8, 77), data[2]);

    try b.write_bit(.one);
    try b.write_bit(.one);
    try b.write_bit(.one);
    try b.write_bit(.one);
    try b.write_byte(0b11110000); // 1111 1111 0000
    try b.write_byte(0b00001111); // 1111 1111 0000 0000 1111
    try b.write_byte(0b00001111); // 1111 1111 0000 0000 1111 0000 1111

    data = b.as_slice();
    try testing.expectEqual(@as(usize, 7), data.len);

    try testing.expectEqual(@as(u8, 255), data[3]); // 0b11111111 = 255
    try testing.expectEqual(@as(u8, 0), data[4]); // 0b00000000 = 0
    try testing.expectEqual(@as(u8, 240), data[5]); // 0b11110000 = 240
}

test "test_write_bits" {
    const testing = std.testing;
    var b = StreamWriter.init(testing.allocator);
    defer b.deinit();

    // 101011
    try b.write_bits(@as(u64, 43), 6);

    // 010
    try b.write_bits(@as(u64, 2), 3);

    // 1
    try b.write_bits(@as(u64, 1), 1);

    // 1010 1100 1110 0011 1101
    try b.write_bits(@as(u64, 708157), 20);

    // 11
    try b.write_bits(@as(u64, 3), 2);

    const data = b.as_slice();
    try testing.expectEqual(@as(usize, 4), data.len);

    try testing.expectEqual(@as(u8, 173), data[0]); // 0b10101101 = 173
    try testing.expectEqual(@as(u8, 107), data[1]); // 0b01101011 = 107
    try testing.expectEqual(@as(u8, 56), data[2]); // 0b00111000 = 56
    try testing.expectEqual(@as(u8, 247), data[3]); // 0b11110111 = 247
}

test "test_write_mixed" {
    const testing = std.testing;
    var b = StreamWriter.init(testing.allocator);
    defer b.deinit();

    // 1010 1010
    for (0..8) |i| {
        if (i % 2 == 0) {
            try b.write_bit(.one);
            continue;
        }

        try b.write_bit(.zero);
    }

    // 0000 1001
    try b.write_byte(@as(u8, 9));

    // 1001 1100 1100
    try b.write_bits(@as(u64, 2508), 12);

    // 1111
    for (0..4) |_| {
        try b.write_bit(.one);
    }

    const data = b.as_slice();
    try testing.expectEqual(@as(usize, 4), data.len);

    try testing.expectEqual(@as(u8, 170), data[0]); // 0b10101010 = 170
    try testing.expectEqual(@as(u8, 9), data[1]); // 0b00001001 = 9
    try testing.expectEqual(@as(u8, 156), data[2]); // 0b10011100 = 156
    try testing.expectEqual(@as(u8, 207), data[3]); // 0b11001111 = 207
}
