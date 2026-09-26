const std = @import("std");
const Error = std.mem.Allocator.Error;

const gtk = @import("gtk");

const Core = @import("Core.zig");
const highlight = @import("highlight.zig");
const Highlighter = highlight.Highlighter;
const Tag = highlight.Tag;

pub const Sink = struct {
    buf: *gtk.TextBuffer,
    cursor: *anyopaque,
    indentation_level: usize,
    highlighter: Highlighter,
    active_tag: ?Tag,
    mode_state: ModeState,
    skip: bool,

    const indentation_unit = 2;

    const Self = @This();

    pub fn init(buf: *gtk.TextBuffer) Self {
        return Self{
            .buf = buf,
            .cursor = undefined,
            .indentation_level = 0,
            .highlighter = highlight.init(buf),
            .active_tag = null,
            .mode_state = ModeState{
                .normal = .{ .cursor_start = null },
            },
            .skip = false,
        };
    }

    pub fn startNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            var end: gtk.TextIter = undefined;
            self.buf.getEndIter(&end);

            switch (self.mode_state) {
                .normal => |*x| {
                    std.debug.assert(x.cursor_start == null);

                    x.cursor_start = self.buf.createMark("cursor-start", &end, 1);
                },
                .edit => |*x| {
                    self.skip = true;

                    std.debug.assert(x.input_start == null);
                    std.debug.assert(x.input_end == null);

                    x.input_start = self.buf.createMark("input-start", &end, 1);
                    x.input_end = self.buf.createMark("input-end", &end, 0);
                },
            }
        }
    }

    pub fn endNode(self: *Self, node: *anyopaque) void {
        if (self.cursor == node) {
            switch (self.mode_state) {
                .normal => |x| {
                    var start: gtk.TextIter = undefined;
                    self.buf.getIterAtMark(&start, x.cursor_start.?);

                    var end: gtk.TextIter = undefined;
                    self.buf.getEndIter(&end);

                    self.buf.applyTag(self.highlighter.get(.cursor), &start, &end);
                },
                .edit => {
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

        switch (self.mode_state) {
            .normal => |*x| {
                if (x.cursor_start) |p| {
                    p.unref();
                }
                x.cursor_start = null;
            },
            .edit => |*x| {
                if (x.input_start) |p| {
                    p.unref();
                }
                x.input_start = null;
                if (x.input_end) |p| {
                    p.unref();
                }
                x.input_end = null;
            },
        }

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
            std.debug.print("Filtered out: {s}\n", .{s});
            return;
        } else {
            std.debug.print("Goes through: {s}\n", .{s});
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

const Mode = Core.modes.Mode;

fn ModeState(comptime mode: Mode) type {
    return switch (mode) {
        .normal => struct { cursor_start: ?*gtk.TextMark },
        .text_input => struct {
            input_start: ?*gtk.TextMark,
            input_end: ?*gtk.TextMark,
        },
    };
}
