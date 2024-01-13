# Gorilla 🦍

A command line parser for Zig ⚡

ℹ️ Info: This was done as part of my time at [Recurse Center]().
⚠️ Warning: please, do not rely on this library for production work. 
It still needs to be thoroughly tested. You are welcome to help.

## How to use?

```zig
const std = @import("std");
const gorilla = @import("gorilla");

const GorillaEncoder  = gorilla.GorillaEncoder;
const GorillaDecoder  = gorilla.GorillaDecoder;
const DataPoint = gorilla.DataPoint;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dataset = [_]DataPoint{
        .{ .timestamp = 1482892270, .value = 1.76},
        .{ .timestamp = 1482892280, .value = 7.78},
        .{ .timestamp = 1482892288, .value = 7.95},
        .{ .timestamp = 1482892292, .value = 5.53},
        .{ .timestamp = 1482892310, .value = 4.41},
        .{ .timestamp = 1482892323, .value = 5.30},
        .{ .timestamp = 1482892334, .value = 5.30},
        .{ .timestamp = 1482892341, .value = 2.92},
        .{ .timestamp = 1482892350, .value = 0.73},
        .{ .timestamp = 1482892360, .value = -1.33},
        .{ .timestamp = 1482892390, .value = -12.45},
        .{ .timestamp = 1482892390, .value = -12.45},
        .{ .timestamp = 1482892401, .value = -34.76},
        .{ .timestamp = 1482892490, .value = 78.9},
        .{ .timestamp = 1482892500, .value = 335.67},
        .{ .timestamp = 1482892800, .value = 12908.12},
    };
    
    var encoder = try GorillaEncoder.init(allocator, 1482892270);
    defer encoder.deinit();
    for(dataset)|point| {
        try encoder.encode(point);
    }
    const data = try encoder.finish();

    var decoder = try GorillaDecoder.init(data[0], data[1]);
    var actual_points = [_]DataPoint{ DataPoint{ .timestamp = 0, .value = 0 } } ** 16;
    for(&actual_points) |*dp| {
        dp.* = (try decoder.next()).?;
    }

    const testing = @import("std").testing;
    try testing.expectEqual(@as(?DataPoint, null), (try decoder.next())); 
    try testing.expectEqualSlices(DataPoint, dataset[0..], actual_points[0..]); 
}
```

