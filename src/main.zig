const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const gtk = @import("gtk");

const StedApp = @import("stedapp.zig").StedApp;

pub fn main() void {
    var app = StedApp.new();
    defer app.unref();
    const status = gio.Application.run(
        app.as(gio.Application),
        @intCast(std.os.argv.len),
        std.os.argv.ptr,
    );
    std.process.exit(@intCast(status));
}
