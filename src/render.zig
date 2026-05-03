const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = std.mem.Allocator.Error;

const gtk = @import("gtk");

pub const Sink = struct {
    buf: *gtk.TextBuffer,
    cursor: *anyopaque,
    cursor_start: *gtk.TextMark,
    indentation_level: usize,
    cursor_tag: *gtk.TextTag,

    const indentation_unit = 2;

    const Self = @This();

    pub fn init(buf: *gtk.TextBuffer) Self {
        const last_arg: ?*anyopaque = null;

        const cursor_tag = buf.createTag(
            "cursor-tag",
            "background",
            // This is from Helix's "dark_plus" theme, which probably comes from VS Code.
            "#3a3d41",
            last_arg,
        );

        return Self{
            .buf = buf,
            .cursor = undefined,
            .cursor_start = gtk.TextMark.new("cursor-start", 1),
            .indentation_level = 0,
            .cursor_tag = cursor_tag,
        };
    }

    pub fn startNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            var end: gtk.TextIter = undefined;
            self.buf.getEndIter(&end);

            if (self.cursor_start.getDeleted() == 0) {
                self.buf.deleteMark(self.cursor_start);
            }
            self.buf.addMark(self.cursor_start, &end);
        }
    }

    pub fn endNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            var start: gtk.TextIter = undefined;
            self.buf.getIterAtMark(&start, self.cursor_start);

            var end: gtk.TextIter = undefined;
            self.buf.getEndIter(&end);

            self.buf.applyTag(self.cursor_tag, &start, &end);
        }
    }

    pub fn append(self: *Self, s: []const u8) Error!void {
        var end: gtk.TextIter = undefined;
        self.buf.getEndIter(&end);
        self.buf.insert(&end, @ptrCast(s.ptr), @intCast(s.len));
    }

    pub fn clear(self: *Self) void {
        self.buf.setText("", 0);
    }

    pub fn increaseIndentation(self: *Self) void {
        self.indentation_level += 1;
    }

    pub fn decreaseIndentation(self: *Self) void {
        self.indentation_level -= 1;
    }

    pub fn breakLine(self: *Self) !void {
        const n = self.indentation_level * indentation_unit;

        try self.append("\n");

        for (0..n) |_| {
            try self.append(" ");
        }
    }

    pub fn appendHole(self: *Self) !void {
        try self.append("◆");
    }

    pub fn deinit(_: *Self) void {}
};
