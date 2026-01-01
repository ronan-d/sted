const std = @import("std");

const Buffer = std.ArrayList(u8);

const cator = std.heap.c_allocator;

pub const Sink = struct {
    buf: Buffer,
    cursor: *anyopaque,
    cursor_start: usize,
    cursor_end: usize,
    code_point_counter: usize,

    const Self = @This();

    pub fn start_node(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            self.cursor_start = self.code_point_counter;
        }
    }

    pub fn end_node(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            self.cursor_end = self.code_point_counter;
        }
    }

    pub fn append(self: *Self, s: []const u8, n_code_points: usize) !void {
        try self.buf.appendSlice(cator, s);
        self.code_point_counter += n_code_points;
    }

    pub fn append_ascii(self: *Self, s: []const u8) !void {
        try self.append(s, s.len);
    }

    pub fn clear(self: *Self) void {
        self.buf.clearRetainingCapacity();
        self.code_point_counter = 0;
    }
};
