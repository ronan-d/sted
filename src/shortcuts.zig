const std = @import("std");
const Allocator = std.mem.Allocator;

const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const commands = @import("commands.zig");
const DynamicCommand = commands.DynamicCommand;
const Mask = commands.Mask;
const Core = @import("Core.zig");
const key_registry = @import("key_registry.zig");
const StedWindow = @import("stedwindow.zig").StedWindow;
const ui_layout = @import("ui_layout.zig");

pub fn makeRow(
    display_text: [:0]const u8,
    k: key_registry.Key,
    _: Allocator,
) !*gtk.Box {
    const r = gtk.Box.new(gtk.Orientation.horizontal, ui_layout.sep_size);
    r.as(gtk.Widget).addCssClass("shortcut");

    const display = gdk.Display.getDefault() orelse unreachable;
    const key_string = k.getLabel(display);
    defer std.c.free(key_string);

    const key_label = gtk.Label.new(key_string);
    key_label.as(gtk.Widget).addCssClass("keycap");
    key_label.as(gtk.Widget).setHalign(gtk.Align.center);
    key_label.as(gtk.Widget).setMarginStart(ui_layout.sep_size);

    r.append(key_label.as(gtk.Widget));

    const description_label = gtk.Label.new(display_text);
    description_label.as(gtk.Widget).setHalign(gtk.Align.end);
    description_label.as(gtk.Widget).setHexpand(0);
    description_label.as(gtk.Widget).setMarginEnd(0);

    r.append(description_label.as(gtk.Widget));

    return r;
}

pub const Pane = struct {
    vbox: *gtk.Box,
    global_rows: commands.Map(*gtk.Box),

    const Self = @This();

    pub fn init(gpa: Allocator) Allocator.Error!Pane {
        const global_rows = b: {
            var x: commands.Map(*gtk.Box) = undefined;

            inline for (commands.all_commands) |c| {
                const k = key_registry.keyForCommand(c);
                x.getPtr(c).* = try makeRow(c.displayText(), k, gpa);
            }
            break :b x;
        };

        const vbox = gtk.Box.new(gtk.Orientation.vertical, ui_layout.sep_size);
        vbox.as(gtk.Widget).setSizeRequest(ui_layout.unit_in_pixels, -1);
        vbox.as(gtk.Widget).setMarginTop(ui_layout.sep_size);

        for (commands.all_commands) |c| {
            vbox.append(global_rows.get(c).as(gtk.Widget));
        }

        return Pane{
            .vbox = vbox,
            .global_rows = global_rows,
        };
    }

    pub fn update(self: *Self, m: Mask) void {
        for (commands.all_commands) |c| {
            const b = self.global_rows.getPtr(c).*;
            const on = m.get(c);

            b.as(gtk.Widget).setSensitive(if (on) 1 else 0);
        }
    }
};
