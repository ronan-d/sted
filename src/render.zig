const std = @import("std");

const Buffer = std.ArrayList(u8);

pub const Sink = struct {
    buf: Buffer,
    cursor: *anyopaque,
    cursor_start: usize,
    cursor_end: usize,

    const Self = @This();

    pub fn start_node(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            self.cursor_start = self.buf.items.len;
        }
    }

    pub fn end_node(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            self.cursor_end = self.buf.items.len;
        }
    }
};
