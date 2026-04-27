# Sted

Sted is a [structure editor](https://en.wikipedia.org/wiki/Structure_editor) for computer programs.

# Installation

Flatpak bundles for x86_64 are available at the [GitHub release page](https://github.com/ronan-d/sted/releases). Install with

```
flatpak install sted.flatpak
```

## Building from source

Building Sted requires Zig 0.16.0. It also requires bindings for GTK and Adwaita generated with `zig-gobject`.

To set this up, first clone `zig-gobject` in a sibling directory:

```
git clone https://github.com/ianprime0509/zig-gobject.git ../zig-gobject
```

On Debian, install `libadwaita-1-dev` and `libgtk-4-dev`. On other operating systems, install the equivalent packages.

Generate the bindings with `zig-gobject`:

```
cd ../zig-gobject
zig build codegen -Dmodules=Gtk-4.0 -Dmodules=Adw-1 -Dgir-files-path=/usr/lib/x86_64-linux-gnu/gir-1.0 -Dgir-files-path=/usr/share/gir-1.0
cd ../sted
```

Finally, build Sted:

```
zig build
```

## Building a Flatpak bundle

```
flatpak-builder --user --install-deps-from=flathub --repo=repo --install --force-clean builddir io.github.ronan_d.sted.yml
flatpak build-bundle ./repo sted.flatpak io.github.ronan_d.sted --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
```
