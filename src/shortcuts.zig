const std = @import("std");
const Allocator = std.mem.Allocator;

const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");

const StedWindow = @import("stedwindow.zig").StedWindow;
const commands = @import("commands.zig");
const DynamicCommand = commands.DynamicCommand;
const Mask = commands.Mask;

const ui_layout = @import("ui_layout.zig");
fn bind_cb_to_key(
    T: type,
    data: T,
    cb: *const fn (*StedWindow, T) void,
    keycode: c_uint,
    gpa: Allocator,
) Allocator.Error!*gtk.Shortcut {
    // TODO perhaps adding some sort of name to the action will be needed for
    // display later.

    const trigger = gtk.KeyvalTrigger.new(keycode, .{});

    const cb_action = blk: {
        const Closure = struct {
            cb: *const fn (*StedWindow, T) void,
            data: T,
            gpa: Allocator,
        };

        const closure = try gpa.create(Closure);
        closure.* = Closure{ .cb = cb, .data = data, .gpa = gpa };

        const local_module = struct {
            fn gtk_cb(wid: *gtk.Widget, _: ?*glib.Variant, opaque_ptr: ?*anyopaque) callconv(.c) c_int {
                const window: *StedWindow = gobject.ext.cast(StedWindow, wid).?;

                const ptr: *Closure = @ptrCast(@alignCast(opaque_ptr));

                ptr.cb(window, ptr.data);

                return 1;
            }

            fn destroy(opaque_ptr: ?*anyopaque) callconv(.c) void {
                const ptr: *Closure = @ptrCast(@alignCast(opaque_ptr));

                ptr.gpa.destroy(ptr);
            }
        };

        const scf: gtk.ShortcutFunc = local_module.gtk_cb;

        const cba = gtk.CallbackAction.new(scf, closure, local_module.destroy);

        break :blk cba;
    };

    const shortcut = gtk.Shortcut.new(trigger.as(gtk.ShortcutTrigger), cb_action.as(gtk.ShortcutAction));

    return shortcut;
}

fn bind_command_to_key(
    command: commands.Command,
    keycode: c_uint,
    gpa: Allocator,
) Allocator.Error!*gtk.Shortcut {
    const local_module = struct {
        fn cb(self: *StedWindow, cmd: commands.Command) void {
            self.core.srcprg.cursor.perform(self.core.init.io, cmd) catch unreachable;

            self.refresh() catch unreachable;
        }
    };

    return try bind_cb_to_key(commands.Command, command, local_module.cb, keycode, gpa);
}

const Shortcut = struct {
    box: *gtk.Box,
    gtks: *gtk.Shortcut,

    pub fn fromGtkShortcut(gtks: *gtk.Shortcut, display_text: [:0]const u8, keycode: c_uint) Shortcut {
        const row = gtk.Box.new(gtk.Orientation.horizontal, ui_layout.sep_size);

        const key_string = gtk.acceleratorGetLabel(keycode, gdk.ModifierType.flags_no_modifier_mask);
        defer std.c.free(key_string);

        const sclabel = gtk.ShortcutLabel.new(key_string);
        sclabel.as(gtk.Widget).setHalign(gtk.Align.center);
        sclabel.as(gtk.Widget).setMarginStart(ui_layout.sep_size);

        row.append(sclabel.as(gtk.Widget));

        const label = gtk.Label.new(display_text);
        label.as(gtk.Widget).setHalign(gtk.Align.end);
        label.as(gtk.Widget).setHexpand(0);
        label.as(gtk.Widget).setMarginEnd(0);

        row.append(label.as(gtk.Widget));

        return Shortcut{
            .box = row,
            .gtks = gtks,
        };
    }
};

const StaticShortcut = struct {
    s: Shortcut,
    is_in_controller: bool,
};

pub const Pane = struct {
    vbox: *gtk.Box,
    controller: *gtk.ShortcutController,
    static: commands.Map(StaticShortcut),
    dynamic: std.ArrayList(Shortcut),

    const Self = @This();

    pub fn init(gpa: Allocator) Allocator.Error!Pane {
        const static = b: {
            var x: commands.Map(StaticShortcut) = undefined;

            inline for (commands.all_commands) |c| {
                const k = c.keycode();
                const s = try if (local_method(c)) |m| blk: {
                    const local_module = struct {
                        fn cb(w: *StedWindow, _: void) void {
                            m(w);
                        }
                    };
                    break :blk bind_cb_to_key(void, {}, local_module.cb, k, gpa);
                } else bind_command_to_key(c, k, gpa);
                x.at_mut(c).* = StaticShortcut{
                    .s = Shortcut.fromGtkShortcut(s, c.displayText(), k),
                    .is_in_controller = false,
                };
            }
            break :b x;
        };

        const vbox = gtk.Box.new(gtk.Orientation.vertical, ui_layout.sep_size);
        vbox.as(gtk.Widget).setSizeRequest(ui_layout.unit_in_pixels, -1);

        vbox.as(gtk.Widget).setMarginTop(ui_layout.sep_size);

        for (commands.all_commands) |c| {
            vbox.append(static.at(c).s.box.as(gtk.Widget));
        }

        // This checks that my interpretation of Widget.get_last_child is correct.
        std.debug.assert(vbox.as(gtk.Widget).getLastChild() ==
            static.at(commands.all_commands[commands.all_commands.len - 1]).s.box.as(gtk.Widget));

        return Pane{
            .vbox = vbox,
            .controller = blk: {
                const controller = gtk.ShortcutController.new();
                controller.as(gtk.EventController).setPropagationPhase(gtk.PropagationPhase.bubble);
                break :blk controller;
            },
            .static = static,
            .dynamic = std.ArrayList(Shortcut).empty,
        };
    }

    fn removeDynamicShortcuts(self: *Self) void {
        for (self.dynamic.items) |s| {
            self.controller.removeShortcut(s.gtks);
            self.vbox.remove(s.box.as(gtk.Widget));
        }
        self.dynamic.clearRetainingCapacity();
    }

    fn apply_mask(self: *Self, m: Mask) void {
        for (commands.all_commands) |c| {
            const s = self.static.at_mut(c);
            const on = m.at(c);

            s.s.box.as(gtk.Widget).setSensitive(if (on) 1 else 0);

            if (s.is_in_controller and !on) {
                self.controller.removeShortcut(s.s.gtks);
                s.is_in_controller = false;
            }

            if (!s.is_in_controller and on) {
                // addShortcut takes ownership of its argument. We want to keep
                // the shortcut alive so we increment the reference count.
                s.s.gtks.ref();
                self.controller.addShortcut(s.s.gtks);
                s.is_in_controller = true;
            }
        }
    }

    pub fn update(self: *Self, m: Mask, cmds: []const DynamicCommand, gpa: Allocator) Allocator.Error!void {
        self.apply_mask(m);

        self.removeDynamicShortcuts();
        try self.dynamic.ensureUnusedCapacity(gpa, cmds.len);

        for (cmds) |cmd| {
            const local_module = struct {
                fn cb(w: *StedWindow, cmd0: DynamicCommand) void {
                    w.core.srcprg.cursor.cursor_pos.executeCommand(cmd0);

                    w.refresh() catch unreachable;
                }
            };

            const gtks = try bind_cb_to_key(DynamicCommand, cmd, local_module.cb, cmd.keycode, gpa);

            const shortcut = Shortcut.fromGtkShortcut(gtks, cmd.display_text, cmd.keycode);

            self.controller.addShortcut(shortcut.gtks);

            self.vbox.append(shortcut.box.as(gtk.Widget));

            self.dynamic.appendAssumeCapacity(shortcut);
        }
    }

    pub fn deinit(self: *Self) void {
        for (commands.all_commands) |c| {
            const s = self.static.at_mut(c);
            s.s.gtks.unref();
        }
    }
};

fn local_method(c: commands.Command) ?fn (*StedWindow) void {
    return switch (c) {
        .replace => StedWindow.replace,
        else => null,
    };
}
