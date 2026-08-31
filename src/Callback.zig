const Core = @import("Core.zig");

function: *const fn (*Core, *anyopaque) void,
data: *anyopaque,

const Self = @This();

pub fn call(self: Self, core: *Core) !void {
    self.function(core, self.data);
    try core.refresh();
}

pub fn init(T: type, function: fn (*Core, T) void, data: T) Self {
    const local_module = struct {
        fn wrapper(core: *Core, data2: *anyopaque) void {
            const x: T = @ptrCast(@alignCast(data2));

            function(core, x);
        }
    };

    return Self{ .function = local_module.wrapper, .data = @ptrCast(@constCast(data)) };
}
