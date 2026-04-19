const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Tree = @import("Tree.zig");

const Sink = @import("render.zig").Sink;

const Frame = @import("Frame.zig");

pub const Srcprg = struct {
    tree: Tree,
    cursor: *ThreadCursor,
    sink: Sink,

    const Self = @This();

    pub fn render(self: *Self, gpa: Allocator) !Frame {
        self.sink.clear();

        self.sink.cursor = self.cursor.cursor_pos.ptr;
        try self.tree.render(gpa, &self.sink);

        try self.sink.buf.append(gpa, 0);

        return Frame{
            .text = self.sink.buf.items,
            .start_offset = self.sink.cursor_start,
            .end_offset = self.sink.cursor_end,
        };
    }

    pub fn new(io: Io, gpa: Allocator) !Self {
        const x = try @import("zig.zig").get_sample(gpa);

        return Self{
            .tree = x,
            .cursor = blk: {
                const p = try gpa.create(ThreadCursor);
                p.* = ThreadCursor.init(x);

                try p.start(io, gpa);

                break :blk p;
            },
            .sink = Sink{
                .buf = .empty,
                .cursor_start = undefined,
                .cursor_end = undefined,
                .cursor = x.ptr,
                .code_point_counter = 0,
                .indentation_level = 0,
            },
        };
    }

    pub fn deinit(self: *Self, io: Io, gpa: Allocator) !void {
        self.tree.deinit(gpa);
        self.sink.deinit(gpa);
        try self.cursor.stop(io);
        gpa.destroy(self.cursor);
    }
};

const ThreadCursor = @import("ThreadCursor.zig");
