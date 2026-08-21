const std = @import("std");
const Allocator = std.mem.Allocator;
const Init = std.process.Init;

const gtk = @import("gtk");

const shortcuts = @import("shortcuts.zig");
const Srcprg = @import("srcprg.zig").Srcprg;

init: Init,
srcprg: Srcprg,
shortcut_pane: shortcuts.Pane,

const Self = @This();

pub fn new(init: Init, text_buffer: *gtk.TextBuffer) !Self {
    return Self{
        .init = init,
        .shortcut_pane = try shortcuts.Pane.init(init.gpa),
        .srcprg = try Srcprg.new(
            init.io,
            init.gpa,
            text_buffer,
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.srcprg.deinit(self.init.io, self.init.gpa);
}

pub fn refresh(self: *Self) Allocator.Error!void {
    const c = self.srcprg.cursor;

    try self.shortcut_pane.update(c.getMask(), c.cmds, self.init.gpa);

    try self.srcprg.render(self.init.gpa);
}
