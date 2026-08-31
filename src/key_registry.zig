const std = @import("std");
const Allocator = std.mem.Allocator;

const gdk = @import("gdk");
const glib = @import("glib");
const gtk = @import("gtk");
const gobject = @import("gobject");

const Callback = @import("Callback.zig");
const CommandIndicator = Core.CommandIndicator;
const commands = @import("commands.zig");
const Core = @import("Core.zig");

const xkb_keycode = c_uint;

pub const Key = enum(c_uint) {
    // Source for the values:
    // https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/input-event-codes.h
    f = 33,
    j = 36,
    d = 32,
    k = 37,
    s = 31,
    l = 38,
    a = 30,
    semicolon = 39,
    i = 23,
    r = 19,
    o = 24,

    pub fn xkbKeycode(k: Key) xkb_keycode {
        // Why "+ 8"? "Historical reasons". See:
        // https://xkbcommon.org/doc/current/keymap-text-format-v1-v2.html#the-xkb_keycodes-section
        return @intFromEnum(k) + 8;
    }

    pub fn fromXkbKeycode(keycode: xkb_keycode) Key {
        return @enumFromInt(keycode - 8);
    }

    pub fn getLabel(k: Key, display: *gdk.Display) [*:0]u8 {
        var keyvals: [*]c_uint = undefined;
        var n_entries: c_int = undefined;

        _ = display.mapKeycode(k.xkbKeycode(), null, &keyvals, &n_entries);

        std.debug.assert(0 < n_entries);

        const keyval = keyvals[0];

        const keyval_string = gtk.acceleratorGetLabel(keyval, gdk.ModifierType.flags_no_modifier_mask);

        return keyval_string;
    }
};

pub const GlobalCommand = struct {
    callback: Callback,
    enabled: bool,
};

pub const LocalCommand = struct {
    callback: Callback,
    // We need to keep references to rows so we can remove them when the cursor moves.
    pane_row: *gtk.Box,
};

const GlobalMap = std.AutoHashMap(xkb_keycode, *GlobalCommand);

const LocalMap = std.AutoHashMap(xkb_keycode, LocalCommand);

pub const Registry = struct {
    global_map: GlobalMap,
    local_map: LocalMap,

    const Self = @This();

    pub fn init(gpa: Allocator) !Self {
        return Self{
            .global_map = GlobalMap.init(gpa),
            .local_map = LocalMap.init(gpa),
        };
    }

    pub fn keyIsAvailable(self: *Self, k: Key) bool {
        return !self.global_map.contains(k.xkbKeycode()) and !self.local_map.contains(k.xkbKeycode());
    }

    pub fn acquireSpecific(self: *Self, k: Key, global_cmd: *GlobalCommand) !void {
        if (!self.keyIsAvailable(k)) {
            return Error.NotAvailable;
        }

        try self.global_map.put(k.xkbKeycode(), global_cmd);
    }

    pub fn bestKeyAvailable(self: *Self) ?Key {
        for (std.enums.values(Key)) |k| {
            if (self.keyIsAvailable(k)) {
                return k;
            }
        }

        return null;
    }

    pub fn acquireBestAvailable(self: *Self, callback: Callback) !?Key {
        for (std.enums.values(Key)) |k| {
            if (self.keyIsAvailable(k)) {
                try self.local_map.put(k.xkbKeycode(), callback);
                return k;
            }
        }

        return null;
    }
};

pub fn setUpController(core: *Core, widget: *gtk.Widget) void {
    const controller = initController(core);

    widget.addController(controller.as(gtk.EventController));
}

pub const Error = error{
    NotAvailable,
    NotAcquired,
};

fn onKeyPressed(keycode: xkb_keycode, core: *Core) !c_int {
    if (core.k_reg.global_map.get(keycode)) |global_command| {
        if (global_command.enabled) {
            try global_command.callback.call(core);
            return 1;
        } else {
            return 0;
        }
    } else if (core.k_reg.local_map.get(keycode)) |local_command| {
        try local_command.callback.call(core);
        return 1;
    } else {
        return 0;
    }
}

fn keyPressedCb(
    _: *gtk.EventControllerKey,
    _: c_uint,
    keycode: xkb_keycode,
    _: gdk.ModifierType,
    core: *Core,
) callconv(.c) c_int {
    return onKeyPressed(keycode, core) catch unreachable;
}

pub fn initController(core: *Core) *gtk.EventControllerKey {
    const controller = gtk.EventControllerKey.new();

    controller.as(gtk.EventController).setPropagationPhase(gtk.PropagationPhase.bubble);

    _ = gtk.EventControllerKey.signals.key_pressed.connect(controller, *Core, keyPressedCb, core, .{});

    return controller;
}

pub fn keyForCommand(command: commands.Command) Key {
    return switch (command) {
        .go_right => .semicolon,
        .go_up => .l,
        .go_left => .j,
        .go_down => .k,
        .insert_before => .s,
        .insert_after => .d,
        .insert_inside => .i,
        .remove => .r,
        .replace => .o,
    };
}
