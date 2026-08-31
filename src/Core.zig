const std = @import("std");
const Allocator = std.mem.Allocator;
const Init = std.process.Init;

const gdk = @import("gdk");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const Callback = @import("Callback.zig");
const commands = @import("commands.zig");
const key_registry = @import("key_registry.zig");
const shortcuts = @import("shortcuts.zig");
const Srcprg = @import("srcprg.zig").Srcprg;
const ui_layout = @import("ui_layout.zig");

init: Init,
srcprg: Srcprg,
shortcut_pane: shortcuts.Pane,
k_reg: key_registry.Registry,
global_commands: commands.Map(GlobalCommand),

const Self = @This();

pub fn new(init: Init, text_buffer: *gtk.TextBuffer) !Self {
    const registry = try key_registry.Registry.init(init.gpa);

    return Self{
        .init = init,
        .shortcut_pane = try shortcuts.Pane.init(init.gpa),
        .srcprg = try Srcprg.new(
            init.io,
            init.gpa,
            text_buffer,
        ),
        .k_reg = registry,
        .global_commands = undefined,
    };
}

pub fn deinit(self: *Self) void {
    self.srcprg.deinit(self.init.io, self.init.gpa);
}

pub fn refresh(self: *Self) Allocator.Error!void {
    const c = self.srcprg.cursor;

    const m = c.getMask();

    for (commands.all_commands) |cmd| {
        self.global_commands.getPtr(cmd).enabled = m.get(cmd);
    }

    {
        var it = self.k_reg.local_map.valueIterator();
        while (it.next()) |local_cmd| {
            self.shortcut_pane.vbox.remove(local_cmd.pane_row.as(gtk.Widget));
        }
    }

    self.k_reg.local_map.clearRetainingCapacity();

    for (c.cmds) |*cmd| {
        try self.bindLocal(cmd);
    }

    self.shortcut_pane.update(m);

    try self.srcprg.render(self.init.gpa);
}

const LocalCommand = struct {
    callback: Callback,
    pane_row: *gtk.Box,
};

const LocalMap = std.AutoHashMap(key_registry.xkb.xkb_keycode_t, LocalCommand);

const GlobalCommand = key_registry.GlobalCommand;

fn instructionCallback(instruction: *const commands.Command) Callback {
    const local_module = struct {
        fn cb(c: *Self, cmd: *const commands.Command) !void {
            try c.srcprg.cursor.perform(c.init.io, cmd.*);
        }

        fn wrapper(c: *Self, cmd: *const commands.Command) void {
            cb(c, cmd) catch unreachable;
        }
    };

    return Callback.init(*const commands.Command, local_module.wrapper, instruction);
}

pub fn bindCommandToCallback(core: *Self, command: commands.Command, key: key_registry.Key, callback: Callback) !void {
    const global_command = core.global_commands.getPtr(command);

    global_command.* = GlobalCommand{
        .callback = callback,
        .enabled = undefined,
    };

    try core.k_reg.acquireSpecific(key, global_command);
}

pub fn bindInstruction(core: *Self, instruction: *const commands.Command, key: key_registry.Key) !void {
    try core.bindCommandToCallback(instruction.*, key, instructionCallback(instruction));
}

fn bindLocal(core: *Self, command: *const commands.DynamicCommand) !void {
    const local_module = struct {
        fn cb(c: *Self, cmd: *const commands.DynamicCommand) void {
            c.srcprg.cursor.cursor_pos.executeCommand(cmd.*);
        }
    };

    const callback = Callback.init(*const commands.DynamicCommand, local_module.cb, command);

    const k = core.k_reg.bestKeyAvailable() orelse unreachable;

    const pane_row = try shortcuts.makeRow(command.display_text, k, core.init.gpa);

    core.shortcut_pane.vbox.append(pane_row.as(gtk.Widget));

    const local_cmd = key_registry.LocalCommand{
        .callback = callback,
        .pane_row = pane_row,
    };

    try core.k_reg.local_map.put(k.xkbKeycode(), local_cmd);
}

fn refreshCb(device: *gdk.Device, _: *gobject.ParamSpec, core: *Self) callconv(.c) void {
    core.refreshLabels(device.getDisplay());
}

pub fn registerKeymapChangeCallbacks(core: *Self) void {
    const display = gdk.Display.getDefault() orelse unreachable;

    const seat = display.getDefaultSeat() orelse unreachable;

    const keyboard = seat.getKeyboard() orelse unreachable;

    _ = gobject.Object.signals.notify.connect(
        keyboard,
        *Self,
        refreshCb,
        core,
        .{ .detail = "active-layout-index" },
    );

    _ = gobject.Object.signals.notify.connect(
        keyboard,
        *Self,
        refreshCb,
        core,
        .{ .detail = "layout-names" },
    );
}

fn setRowText(row: *gtk.Box, k: key_registry.Key, display: *gdk.Display) void {
    const text = k.getLabel(display);
    defer glib.free(text);

    const label_widget = row.as(gtk.Widget).getFirstChild() orelse unreachable;

    const label = gobject.ext.cast(gtk.Label, label_widget) orelse unreachable;

    label.setText(text);
}

fn refreshLabels(self: *Self, display: *gdk.Display) void {
    for (commands.all_commands) |cmd| {
        const k = key_registry.keyForCommand(cmd);

        setRowText(self.shortcut_pane.global_rows.get(cmd), k, display);
    }

    {
        var it = self.k_reg.local_map.iterator();
        while (it.next()) |entry| {
            const k = key_registry.Key.fromXkbKeycode(entry.key_ptr.*);

            setRowText(entry.value_ptr.pane_row, k, display);
        }
    }
}
