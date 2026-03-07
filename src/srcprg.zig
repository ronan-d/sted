const std = @import("std");

const cator = std.heap.c_allocator;

const Tree = @import("Tree.zig");

const Sink = @import("render.zig").Sink;

const Frame = @import("Frame.zig");

pub const Srcprg = struct {
    tree: Tree,
    cursor: *ThreadCursor,
    sink: Sink,

    const Self = @This();

    pub fn render(self: *Self) !Frame {
        self.sink.clear();

        self.sink.cursor = self.cursor.cursor_pos.ptr;
        try self.tree.render(&self.sink);

        try self.sink.buf.append(cator, 0);

        return Frame{
            .text = self.sink.buf.items,
            .start_offset = self.sink.cursor_start,
            .end_offset = self.sink.cursor_end,
        };
    }

    pub fn new() !Self {
        const x = try @import("zig.zig").get_sample();

        return Self{
            .tree = x,
            .cursor = blk: {
                const p = cator.create(ThreadCursor) catch std.process.exit(1);
                p.* = ThreadCursor.init(x);

                p.start();

                p.perform(.go_down);
                p.perform(.go_down);
                p.perform(.go_right);
                p.perform(.go_down);
                p.perform(.go_right);

                break :blk p;
            },
            .sink = Sink{
                .buf = .{},
                .cursor_start = undefined,
                .cursor_end = undefined,
                .cursor = x.ptr,
                .code_point_counter = 0,
                .indentation_level = 0,
            },
        };
    }
};

const ThreadCursor = @import("ThreadCursor.zig");
