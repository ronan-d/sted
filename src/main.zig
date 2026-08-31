const std = @import("std");

const gio = @import("gio");

const StedApp = @import("stedapp.zig").StedApp;

pub fn main(init: std.process.Init) void {
    var app = StedApp.new(&init);
    defer app.unref();
    const status = gio.Application.run(
        app.as(gio.Application),
        @intCast(init.minimal.args.vector.len),
        @ptrCast(@constCast(init.minimal.args.vector.ptr)),
    );
    std.process.exit(@intCast(status));
}
