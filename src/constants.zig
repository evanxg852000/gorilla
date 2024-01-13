// Store the first delta with 14 bits,enough to span over 4 hours. 
// Increase this value if a larger window is needed.
pub const NUM_FIRST_DELTA_BITS : u32 = 14;

pub const DELTA_NO_RECORDS_MARKER: u64 = 0x3FFF;

pub const DELTA_END_RECORDS_CONTROL_BITS: u64 = 0b1111;
pub const DELTA_END_RECORDS_CONTROL_BITS_SIZE: u32 = 4;

pub const DELTA_END_RECORDS_MARKER: u64 = 0xFFFFFFFF;
pub const DELTA_END_RECORDS_MARKER_SIZE: u32 = 32;

// Store the first float value entirely on 64 bits.
pub const NUM_FIRST_VALUE_BITS = 64;

// End record control bits
pub const END_RECORDS_CONTROL_BITS: u64 = 0x0F;
pub const END_RECORDS_CONTROL_BITS_SIZE: u32 = 4;

// End record marker
pub const END_RECORDS_MARKER: u64 = 0xFFFFFFFF;
pub const END_RECORDS_MARKER_SIZE: u32 = 32;
