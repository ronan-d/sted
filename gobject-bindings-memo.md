At the time of writing, it's necessary to check out the `push-owqrwmxqntox` branch of the zig-gobject repo and to rebase it on top of the master branch.

# Invocation

Ubuntu:

```
zig build codegen -Dmodules=Gtk-4.0 -Dmodules=Adw-1 -Dgir-files-path=/usr/lib/x86_64-linux-gnu/gir-1.0 -Dgir-files-path=/usr/share/gir-1.0
```
