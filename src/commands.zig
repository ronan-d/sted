// A finite and even small set of commands.
//
// 1. Represent subsets conveniently.
// 2. Functions that take in an element from the set and return:
//    a. A human-readable string.
//    b. A shortcut key (with the right GDK type).
// 3. Elements can be either a ThreadCursor instruction or an arbitrary StedWindow method.

pub const Command = enum {
    go_right,
    go_up,
    go_left,
    go_down,
    insert_before,
    insert_after,
    insert_inside,
    remove,
    replace,

    pub fn displayText(c: Command) [:0]const u8 {
        return switch (c) {
            .go_right => "Go right",
            .go_up => "Go up",
            .go_left => "Go left",
            .go_down => "Go down",
            .insert_before => "Insert before",
            .insert_after => "Insert after",
            .insert_inside => "Insert inside",
            .remove => "Remove",
            .replace => "Replace",
        };
    }

    pub fn keycode(c: Command) c_uint {
        const gdk = @import("gdk");

        return switch (c) {
            .go_right => gdk.KEY_l,
            .go_up => gdk.KEY_k,
            .go_left => gdk.KEY_h,
            .go_down => gdk.KEY_j,
            .insert_before => gdk.KEY_s,
            .insert_after => gdk.KEY_d,
            .insert_inside => gdk.KEY_i,
            .remove => gdk.KEY_r,
            .replace => gdk.KEY_o,
        };
    }
};

const command_count = switch (@typeInfo(Command)) {
    .@"enum" => |e| e.fields.len,
    else => unreachable,
};

pub const all_commands = blk: {
    var x: [command_count]Command = undefined;

    for (&x, 0..) |*p, i| {
        p.* = @enumFromInt(i);
    }

    break :blk x;
};

pub fn Map(T: type) type {
    return extern struct {
        array: [command_count]T,

        pub fn at(self: @This(), c: Command) T {
            return self.array[@intFromEnum(c)];
        }

        pub fn at_mut(self: *@This(), c: Command) *T {
            return &self.array[@intFromEnum(c)];
        }
    };
}
