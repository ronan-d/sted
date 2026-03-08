const adw = @import("adw");
const gio = @import("gio");
const gobject = @import("gobject");
const gtk = @import("gtk");

const StedWindow = @import("stedwindow.zig").StedWindow;

pub const StedApp = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.Application;

    pub const getGObjectType = gobject.ext.defineClass(StedApp, .{
        .classInit = &Class.init,
    });

    pub fn new() *StedApp {
        return gobject.ext.newInstance(StedApp, .{
            .application_id = "org.ronan-d.sted",
            .flags = gio.ApplicationFlags{ .non_unique = true },
        });
    }

    pub fn as(app: *StedApp, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = StedApp;

        fn activateImpl(app: *StedApp) callconv(.c) void {
            const win = StedWindow.new(app);

            gtk.Window.present(win.as(gtk.Window));
        }

        fn init(class: *Class) callconv(.c) void {
            gio.Application.virtual_methods.activate.implement(class, &activateImpl);
        }
    };

    const Self = @This();
};
