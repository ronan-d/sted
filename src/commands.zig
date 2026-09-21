const std = @import("std");

const Core = @import("Core.zig");

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
    enter_text_input_mode,

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
            .enter_text_input_mode => "Input text",
        };
    }
};

pub const all_commands = std.enums.values(Command);

pub fn Map(T: type) type {
    return std.EnumArray(Command, T);
}

pub const DynamicCommand = struct {
    display_text: [:0]const u8,
    func: *const fn (*anyopaque) void,
};

const Func = union(enum) {
    parameterless: *const fn (*anyopaque) void,
    from_identifier: *const fn (*anyopaque, id: Core.Identifier) void,
};

pub const Mask = Map(bool);
