const std = @import("std");
const Error = std.mem.Allocator.Error;

const gtk = @import("gtk");

const highlight = @import("highlight.zig");
const Highlighter = highlight.Highlighter;
const Tag = highlight.Tag;

pub const Sink = struct {
    buf: *gtk.TextBuffer,
    cursor: *anyopaque,
    cursor_start: *gtk.TextMark,
    indentation_level: usize,
    highlighter: Highlighter,
    active_tag: ?Tag,
    mode: Mode,
    skip: bool,

    const indentation_unit = 2;

    const Self = @This();

    pub fn init(buf: *gtk.TextBuffer) Self {
        return Self{
            .buf = buf,
            .cursor = undefined,
            .cursor_start = gtk.TextMark.new("cursor-start", 1),
            .indentation_level = 0,
            .highlighter = highlight.init(buf),
            .active_tag = null,
            .mode = Mode.normal,
        };
    }

    pub fn startNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            var end: gtk.TextIter = undefined;
            self.buf.getEndIter(&end);

            switch (self.mode) {
                .normal => {
                    if (self.cursor_start.getDeleted() == 0) {
                        self.buf.deleteMark(self.cursor_start);
                    }
                    self.buf.addMark(self.cursor_start, &end);
                },
                .edit => {
                    self.skip = true;
                    self.buf.placeCursor(end);
                },
            }
        }
    }

    pub fn endNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            switch (self.mode) {
                .normal => {
                    var start: gtk.TextIter = undefined;
                    self.buf.getIterAtMark(&start, self.cursor_start);

                    var end: gtk.TextIter = undefined;
                    self.buf.getEndIter(&end);

                    self.buf.applyTag(self.highlighter.get(.cursor), &start, &end);
                },
                .node => {
                    self.skip = false;
                },
            }
        }
    }

    pub fn append(self: *Self, s: []const u8) Error!void {
        self.innerAppend(s, null);
    }

    pub fn clear(self: *Self) void {
        self.buf.setText("", 0);
        self.skip = false;
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

    pub fn tagged(self: *Self, s: []const u8, tag: Tag) void {
        self.innerAppend(s, tag);
    }

    fn innerAppend(self: *Self, s: []const u8, tag: ?Tag) void {
        if (self.skip) {
            return;
        }

        const last_arg: ?*anyopaque = null;

        var end: gtk.TextIter = undefined;
        self.buf.getEndIter(&end);

        const merged_tag = tag orelse self.active_tag;

        if (merged_tag) |t| {
            self.buf.insertWithTags(
                &end,
                @ptrCast(s.ptr),
                @intCast(s.len),
                self.highlighter.get(t),
                last_arg,
            );
        } else {
            self.buf.insert(&end, @ptrCast(s.ptr), @intCast(s.len));
        }
    }

    pub fn deinit(_: *Self) void {}
};

const Mode = enum {
    normal,
    edit,
};
