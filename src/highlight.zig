const std = @import("std");

const gtk = @import("gtk");

pub const Tag = enum {
    cursor,
    keyword,
    type,
    function,
    str_lit,

    fn prop(x: Tag) Prop {
        return switch (x) {
            .cursor => Prop{ .name = "background", .value = "#3a3d41" },
            .keyword => Prop{ .name = "foreground", .value = "#569CD6" },
            .type => Prop{ .name = "foreground", .value = "#4EC9B0" },
            .function => Prop{ .name = "foreground", .value = "#DCDCAA" },
            .str_lit => Prop{ .name = "foreground", .value = "#ce9178" },
        };
    }
};

const Prop = struct {
    name: [:0]const u8,
    value: [:0]const u8,
};

pub const Highlighter = std.EnumArray(Tag, *gtk.TextTag);

pub fn init(buf: *gtk.TextBuffer) Highlighter {
    const last_arg: ?*anyopaque = null;

    var h = Highlighter.initUndefined();

    var it = h.iterator();
    while (it.next()) |e| {
        const p = e.key.prop();

        e.value.* = buf.createTag(@tagName(e.key), p.name.ptr, p.value.ptr, last_arg);
    }

    return h;
}
