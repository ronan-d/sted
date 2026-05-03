const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = std.mem.Allocator.Error;

const Tree = @import("Tree.zig");

const Sink = @import("render.zig").Sink;

pub fn List(
    ElementType: type,
    comptime open: []const u8,
    comptime close: []const u8,
    comptime sep: union(enum) {
        break_lines,
        symbol: []const u8,
    },
) type {
    return struct {
        elements: std.ArrayList(ElementType),

        const Self = @This();

        pub fn drop(self: *Self, gpa: Allocator) void {
            for (self.elements.items) |*x| {
                x.drop(gpa);
            }

            self.elements.deinit(gpa);
        }

        pub fn render(self: *Self, gpa: Allocator, sink: *Sink) Error!void {
            try sink.append(open);

            switch (sep) {
                .break_lines => {
                    if (self.elements.items.len > 0) {
                        sink.increaseIndentation();

                        for (self.elements.items) |*x| {
                            try sink.breakLine();
                            try x.render(gpa, sink, null);
                        }

                        sink.decreaseIndentation();
                        try sink.breakLine();
                    }
                },
                .symbol => |s| {
                    for (self.elements.items, 0..) |*x, i| {
                        try x.render(gpa, sink, null);

                        if (i + 1 < self.elements.items.len) {
                            try sink.append(s);
                        }
                    }
                },
            }

            try sink.append(close);
        }

        pub fn initialValue() Self {
            return Self{ .elements = std.ArrayList(ElementType).empty };
        }

        fn childCount(ptr: *anyopaque) usize {
            const self: *Self = @ptrCast(@alignCast(ptr));

            return self.elements.items.len;
        }

        fn insertAt(ptr: *anyopaque, gpa: Allocator, i: usize) Error!bool {
            const self: *Self = @ptrCast(@alignCast(ptr));

            try self.elements.insert(gpa, i, try ElementType.initialValue());

            return true;
        }

        fn removeAt(ptr: *anyopaque, i: usize) Tree.RemovalOutcome {
            const self: *Self = @ptrCast(@alignCast(ptr));

            var x = self.elements.orderedRemove(i);
            x.drop();

            return .done;
        }

        fn raw_render(ptr: *anyopaque, sink: *Sink) Error!void {
            const self: *Self = @ptrCast(@alignCast(ptr));

            try self.render(sink);
        }
    };
}
