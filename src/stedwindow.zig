const std = @import("std");
const cator = std.heap.c_allocator;
const Allocator = std.mem.Allocator;

const adw = @import("adw");
const gdk = @import("gdk");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");
const pango = @import("pango");

const Frame = @import("Frame.zig");
const instruction = @import("ThreadCursor.zig").instruction;
const Srcprg = @import("srcprg.zig").Srcprg;
const StedApp = @import("stedapp.zig").StedApp;
const Tree = @import("Tree.zig");

const Renderer = extern struct {
    buffer: *gtk.TextBuffer,
    tag: *gtk.TextTag,

    const Self = @This();

    pub fn render_frame(self: Self, frame: Frame) void {
        const with_sentinel: [:0]const u8 = frame.text[0 .. frame.text.len - 1 :0];

        self.buffer.setText(with_sentinel, @intCast(with_sentinel.len));

        var start: gtk.TextIter = undefined;
        self.buffer.getIterAtOffset(&start, @intCast(frame.start_offset));

        var end: gtk.TextIter = undefined;
        self.buffer.getIterAtOffset(&end, @intCast(frame.end_offset));

        self.buffer.applyTag(self.tag, &start, &end);
    }
};

pub const StedWindow = extern struct {
    parent_instance: Parent,
    renderer: Renderer,
    srcprg: *Srcprg,
    controller: *gtk.ShortcutController,

    pub const Parent = adw.ApplicationWindow;

    fn init(self: *StedWindow, _: *Class) callconv(.c) void {
        self.as(gtk.Window).setTitle("hello");
        self.as(gtk.Window).setDefaultSize(800, 800);

        const text_view = gtk.TextView.new();
        text_view.setEditable(0);
        text_view.setCursorVisible(0);
        text_view.setMonospace(1);

        {
            const provider = gtk.CssProvider.new();
            defer provider.unref();

            provider.loadFromString("textview { font-family: \"Noto Mono\"; font-size: 12pt; }");
            text_view.as(gtk.Widget).getStyleContext().addProvider(provider.as(gtk.StyleProvider), gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }

        {
            const controller = gtk.ShortcutController.new();
            controller.as(gtk.EventController).setPropagationPhase(gtk.PropagationPhase.bubble);

            self.as(gtk.Widget).addController(controller.as(gtk.EventController));

            self.controller = controller;
        }

        self.bind_instruction_to_key(.go_right, gdk.KEY_l);
        self.bind_instruction_to_key(.go_up, gdk.KEY_k);
        self.bind_instruction_to_key(.go_left, gdk.KEY_h);
        self.bind_instruction_to_key(.go_down, gdk.KEY_j);

        self.bind_instruction_to_key(.insert_before, gdk.KEY_s);
        self.bind_instruction_to_key(.insert_after, gdk.KEY_d);

        self.bind_instruction_to_key(.remove_cursor_node, gdk.KEY_r);

        self.bind_cb_to_key(replace, gdk.KEY_o);

        const toolbar_view = adw.ToolbarView.new();

        toolbar_view.addTopBar(adw.HeaderBar.new().as(gtk.Widget));

        toolbar_view.setContent(text_view.as(gtk.Widget));

        self.as(adw.ApplicationWindow).setContent(toolbar_view.as(gtk.Widget));

        const last_arg: ?*anyopaque = null;

        const buffer = text_view.getBuffer();

        self.renderer = Renderer{
            .buffer = buffer,
            .tag = buffer.createTag(
                "cursor-tag",
                "underline",
                @intFromEnum(pango.Underline.single),
                last_arg,
            ),
        };

        self.srcprg = cator.create(Srcprg) catch unreachable;
        self.srcprg.* = Srcprg.new() catch unreachable;

        self.refresh() catch unreachable;
    }

    fn bind_cb_to_key(win: *StedWindow, cb: fn (*StedWindow) void, keycode: c_uint) void {
        // TODO perhaps adding some sort of name to the action will be needed for
        // display later.

        const trigger = gtk.KeyvalTrigger.new(keycode, .{});

        const cb_action = blk: {
            const local_module = struct {
                fn gtk_cb(wid: *gtk.Widget, _: ?*glib.Variant, _: ?*anyopaque) callconv(.c) c_int {
                    const self: *StedWindow = gobject.ext.cast(StedWindow, wid).?;

                    cb(self);

                    return 1;
                }
            };

            const scf: gtk.ShortcutFunc = local_module.gtk_cb;

            const cba = gtk.CallbackAction.new(scf, null, null);

            break :blk cba;
        };

        const shortcut = gtk.Shortcut.new(trigger.as(gtk.ShortcutTrigger), cb_action.as(gtk.ShortcutAction));

        win.controller.addShortcut(shortcut);
    }

    fn bind_instruction_to_key(win: *StedWindow, comptime instr: instruction, keycode: c_uint) void {
        const local_module = struct {
            fn cb(self: *StedWindow) void {
                self.srcprg.cursor.perform(instr);

                self.refresh() catch unreachable;
            }
        };

        win.bind_cb_to_key(local_module.cb, keycode);
    }

    fn dispose(self: *StedWindow) callconv(.c) void {
        cator.destroy(self.srcprg);

        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    pub fn as(app: *StedWindow, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    pub const getGObjectType = gobject.ext.defineClass(StedWindow, .{ .instanceInit = &init });

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = StedWindow;
    };

    pub fn new(app: *StedApp) *StedWindow {
        return gobject.ext.newInstance(StedWindow, .{
            .application = app,
        });
    }

    const Self = @This();

    fn create_input_dialog(self: *Self) !*adw.Dialog {
        const box = gtk.Box.new(gtk.Orientation.vertical, 0);

        const dialog = adw.Dialog.new();
        dialog.setChild(box.as(gtk.Widget));
        dialog.setFollowsContentSize(1);
        dialog.setPresentationMode(adw.DialogPresentationMode.floating);

        const offers = self.srcprg.cursor.cursor_pos.getOffers();

        for (offers) |offer| {
            const button = gtk.Button.newWithMnemonic(offer.name);
            box.append(button.as(gtk.Widget));

            switch (offer.rewriter) {
                .from_void => |f| {
                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb_void,
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
                .from_int => |f| {
                    const button_cb = button_cb_generic(u64, int_from_string);

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb,
                        // Note: it would be nice to be more type-safe here.
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
                .from_string => |f| {
                    const button_cb = button_cb_generic([]const u8, string_from_string);

                    _ = gtk.Button.signals.clicked.connect(
                        button,
                        *anyopaque,
                        button_cb,
                        // Note: it would be nice to be more type-safe here.
                        @ptrCast(@constCast(f)),
                        .{},
                    );
                },
            }
        }

        return dialog;
    }

    pub fn addAction(
        self: *Self,
        comptime cb: *const fn (*Self) void,
        name: [:0]const u8,
    ) void {
        const local_module = struct {
            pub fn cb_wrapper(
                _: *gio.SimpleAction,
                _: *glib.Variant,
                p_user_data: ?*anyopaque,
            ) callconv(.c) void {
                const p: *Self = @ptrCast(@alignCast(p_user_data));

                cb(p);
            }
        };

        const entry: gio.ActionEntry = .{
            .f_name = name,
            .f_activate = local_module.cb_wrapper,
            .f_parameter_type = null,
            .f_change_state = null,
            .f_state = null,
            .f_padding = undefined,
        };

        const intermediate_array = [_]gio.ActionEntry{entry};

        self.as(gio.ActionMap).addActionEntries(
            &intermediate_array,
            intermediate_array.len,
            @ptrCast(self),
        );
    }

    pub fn replace(self: *Self) void {
        const dialog = self.create_input_dialog() catch unreachable;

        dialog.present(self.as(gtk.Widget));
    }

    pub fn refresh(self: *Self) !void {
        self.renderer.render_frame(try self.srcprg.render());
    }
};

fn button_cb_generic(
    param_type: type,
    from_string: fn ([*:0]const u8) param_type,
) fn (button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
    const local_module = struct {
        fn button_cb(button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
            const entry = gtk.Entry.new();

            const entry_cb = entry_cb_generic(param_type, from_string);

            _ = gtk.Entry.signals.activate.connect(
                entry,
                *anyopaque,
                entry_cb,
                user_data,
                .{},
            );

            const dialog_widget = button.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
            const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

            dialog.setChild(entry.as(gtk.Widget));
            _ = entry.as(gtk.Widget).grabFocus();
        }
    };

    return local_module.button_cb;
}

fn entry_cb_generic(
    param_type: type,
    from_string: fn ([*:0]const u8) param_type,
) fn (entry: *gtk.Entry, user_data: *anyopaque) callconv(.c) void {
    const local_module = struct {
        fn entry_cb(entry: *gtk.Entry, user_data: *anyopaque) callconv(.c) void {
            const f: *const fn (*anyopaque, param_type) Allocator.Error!void = @ptrCast(user_data);
            const text = entry.getBuffer().getText();

            const text_slice = std.mem.sliceTo(text, 0);

            const arg = from_string(text_slice);

            const dialog_widget = entry.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
            const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

            const win_widget = dialog_widget.getAncestor(StedWindow.getGObjectType()).?;
            const win = gobject.ext.cast(StedWindow, win_widget).?;

            const ptr = win.srcprg.cursor.cursor_pos.ptr;
            f(ptr, arg) catch unreachable;

            win.refresh() catch unreachable;

            close_dialog(dialog);
        }
    };

    return local_module.entry_cb;
}

fn int_from_string(text: [*:0]const u8) u64 {
    const text_slice = std.mem.sliceTo(text, 0);

    const num = std.fmt.parseInt(u64, text_slice, 10) catch unreachable;

    return num;
}

fn string_from_string(text: [*:0]const u8) []const u8 {
    return std.mem.sliceTo(text, 0);
}

fn button_cb_void(button: *gtk.Button, user_data: *anyopaque) callconv(.c) void {
    const f: *const fn (*anyopaque) Allocator.Error!void = @ptrCast(user_data);

    const dialog_widget = button.as(gtk.Widget).getAncestor(adw.Dialog.getGObjectType()).?;
    const dialog = gobject.ext.cast(adw.Dialog, dialog_widget).?;

    const win_widget = dialog_widget.getAncestor(StedWindow.getGObjectType()).?;
    const win = gobject.ext.cast(StedWindow, win_widget).?;

    const ptr = win.srcprg.cursor.cursor_pos.ptr;
    f(ptr) catch unreachable;

    win.refresh() catch unreachable;

    close_dialog(dialog);
}

fn close_dialog(d: *adw.Dialog) void {
    const res = d.close();
    if (res != 1) {
        @panic("Failed to close dialog");
    }
}
