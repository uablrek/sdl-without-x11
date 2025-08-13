# SDL without X11 (or Wayland)

Build SDL without X11 for a small VM, and ultimately for RPi4 and
Rock 4se. This means cross-compile from scratch with `musl` lib.

### This is a Work in Progress (WIP)

Works:

* Build with `libc` for `x86_64` (native)
* Build with `musl` for both `x86_64` and `aarch64`
* Many SDL tests works in qemu for both architectures
* `ScummVM` builds and starts
* `kmscube` works

Problems:

* Mouse SDL tests doesn't work
* Input (mouse, kbd) doesn't work for `ScummVM`
* Audio is not tested
* (much, much more...)

## Help scripts

```
. ./Envsettings      # For convenient aliases, e.g. for "admin" and "qemu"
admin                # Help printout
admin env            # Current environment
qemu                 # Help printout
qemu env             # Current environment
# all options are long and *must* have a '=' if they take a parameter
admin env --musl --arch=aarch64
# options can be specified as environment variables
export __musl=yes
export __arch=aarch64
admin env            # same as above
```

## Build and run

Download archives to $HOME/Downloads, or $ARCHIVE:
```
admin versions
qemu versions
```
Libs with version "master" are taken from the "Code" button on github
or gitlab.

```
admin rebuild    # (take ~140s on my i9/24-cores)
#stty intr ^D  # To stop `ctrl-C` from exiting qemu
qemu run
# In the VM (console terminal)
kmscube
ls /bin   # run some sdl tests
```
If you build the musl cross-compilers you can test aarch64:
```
musl          # (an alias, check Envsettings)
aarch64
admin rebuild
qemu run
```
### Dependencies

Dependencies can be very hard in cross-compilation
environments. Basically you must build all dependent libs yourself.

Built libs and includes are installed in a "system directory"
(`--sysd`). Later builds uses the sysd, usually via `pkgconfig`.

```
eval $(admin env | grep __sysd)
ls $__sysd
admin pkgconfig pkg-config --libs --cflags expat
```

### Musl cross-compilers

Build musl cross-compilers
```
eval $(./admin.sh env | grep musldir)
git clone --depth 1 https://github.com/richfelker/musl-cross-make.git $musldir
cd $musldir
./admin.sh musl-cross-make-build
```
This takes a long time and should only be done once.

### ScummVM

```
admin scummvm-build
admin mkimage ovl/scummvm
qemu run
# In the VM
/usr/local/bin/scummvm
```

## Graphics in qemu

Read the qemu documentation for [virtio-gpu](
https://www.qemu.org/docs/master/system/devices/virtio-gpu.html)
and [standard-vga](https://www.qemu.org/docs/master/specs/standard-vga.html).

I recommend reading some articles from [Gerd Hoffmann's blog](
https://www.kraxel.org/blog/). They are *very good*, even if they are old.

* [VGA emulation in qemu - where do we want to go?](
  https://www.kraxel.org/blog/2018/10/qemu-vga-emulation-and-bochs-display/)
* [VGA and other display devices in qemu](
  https://www.kraxel.org/blog/2019/09/display-devices-in-qemu/) (read this!)
* [virtio-gpu and qemu graphics in 2021](
  https://www.kraxel.org/blog/2021/05/virtio-gpu-qemu-graphics-update/)

```
qemu-system-x86_64 -device help | grep virtio | grep gpu
```

## Mesa

* https://gitlab.freedesktop.org/mesa

These packages are needed for a full local build:
```
apt install glslang-tools python3-mako llvm libwayland-egl-backend-dev \
 libxcb-glx0-dev libx11-xcb-dev libxcb-dri2-0-dev libxcb-dri3-dev \
 libxcb-present-dev libxshmfence-dev
```

## Libudev

Is now part of the systemd-monolith, so it can't be ported or
cross-compiled. However [libudev-zero](https://github.com/illiliti/libudev-zero)
provides a replacement.

```
./admin.sh libudev_build
# or
./admin.sh libudev_build --musl
./admin.sh pkgconfig pkg-config --libs --cflags libudev
```

## Framebuffer

The simplest graphic device is the [framebuffer](
https://www.kernel.org/doc/Documentation/fb/framebuffer.txt). It's
basically obsolete and of no use. There is no support for framebuffer
in SDL2+.

## More info

DRI = Direct Rendering Infrastructure

(in no particular order)

* https://wiki.libsdl.org/SDL2/Installation
* https://gist.github.com/miguelmartin75/6946310
* https://unix.stackexchange.com/questions/33596/no-framebuffer-device-how-to-enable-it
* https://wiki.libsdl.org/SDL2/FAQUsingSDL
* https://forums.raspberrypi.com/viewtopic.php?t=268356
* https://docs.mesa3d.org/download.html
* https://en.wikipedia.org/wiki/Direct_Rendering_Manager
* https://github.com/CuarzoSoftware/SRM

