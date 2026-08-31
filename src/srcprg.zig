const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const gtk = @import("gtk");

const Frame = @import("Frame.zig");
const Sink = @import("render.zig").Sink;
const Tree = @import("Tree.zig");

pub const Srcprg = struct {
    tree: Tree,
    cursor: *ThreadCursor,
    sink: Sink,

    const Self = @This();

    pub fn render(self: *Self, gpa: Allocator) !void {
        self.sink.clear();

        self.sink.cursor = self.cursor.cursor_pos.ptr;
        try self.tree.render(gpa, &self.sink);
    }

    pub fn new(io: Io, gpa: Allocator, buf: *gtk.TextBuffer) !Self {
        const x = try @import("zig.zig").get_sample(gpa);

        return Self{
            .tree = x,
            .cursor = blk: {
                const p = try gpa.create(ThreadCursor);
                p.* = ThreadCursor.init(x);

                try p.start(io, gpa);

                break :blk p;
            },
            .sink = Sink.init(buf),
        };
    }

    pub fn deinit(self: *Self, io: Io, gpa: Allocator) !void {
        self.tree.deinit(gpa);
        self.sink.deinit();
        try self.cursor.stop(io);
        gpa.destroy(self.cursor);
    }
};

const ThreadCursor = @import("ThreadCursor.zig");
