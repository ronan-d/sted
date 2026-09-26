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

    const Self = @This();

    pub fn render(self: *Self, buf: *gtk.TextBuffer, gpa: Allocator) !void {
        const sink = Sink.init(buf, self.cursor.cursor_pos.ptr);

        try self.tree.render(gpa, &sink);

        sink.deinit();
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
