const std = @import("std");
const Init = std.process.Init;

const adw = @import("adw");
const gio = @import("gio");
const gobject = @import("gobject");
const gtk = @import("gtk");

const StedWindow = @import("stedwindow.zig").StedWindow;

pub const StedApp = extern struct {
    parent_instance: Parent,
    init: *const Init,

    pub const Parent = adw.Application;

    pub const getGObjectType = gobject.ext.defineClass(StedApp, .{
        .classInit = &Class.init,
    });

    pub fn new(init: *const Init) *StedApp {
        const app = gobject.ext.newInstance(StedApp, .{
            .application_id = "org.ronan-d.sted",
            .flags = gio.ApplicationFlags{ .non_unique = true },
        });
        app.init = init;
        return app;
    }

    pub fn as(app: *StedApp, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = StedApp;

        fn activateImpl(app: *StedApp) callconv(.c) void {
            const win = StedWindow.new(app) catch unreachable;

            win.as(gtk.Window).present();
        }

        fn init(class: *Class) callconv(.c) void {
            gio.Application.virtual_methods.activate.implement(class, &activateImpl);
        }
    };

    const Self = @This();
};
