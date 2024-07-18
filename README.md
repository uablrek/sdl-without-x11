# SDL without X11 (or Wayland)

Build SDL without X11 for a small VM, and ultimately for RPi4 and
Rock 4 se. This means cross-compile from scratch with `musl` lib.

### This is a Work in Progress (WIP)

Local build (libc) and `musl` build for x86_64 works. SDL tests (not
all), and `kcmcube` works in a x86_64 VM. Build "mesa" for `aarch64`
fails. The `ScummVM` builds and starts, but input (mouse, kbd) doesn't
work.


## Build

Download if needed to $HOME/Downloads, or $ARCHIVE:
```
./sdl.sh versions
```
Libs with version "master" are taken from the "Code" button on github
or gitlab.

```
#stty intr ^D  # To stop `ctrl-C` from exiting qemu
#kvm -device help | grep virtio | grep gpu
#eval $(./sdl.sh env | grep -E 'sysd|SDL_WORKSPACE')
./sdl.sh rebuild    # (take ~3m on my i9. may take a long time on slower pc's)
TESTS=yes ./sdl.sh mkimage ovl/rootfs0 ovl/sdl
./sdl.sh qemu

# In the VM (console terminal)
testdisplayinfo
kmscube
testdraw2
testsprite2
testmouse
testwm2
```

Built libs and includes are installed in a "system directory"
(`--sysd`). Later builds uses the sysd, usually via `pkgconfig`.

```
eval $(./sdl.sh env | grep -E '.*sysd|SDL_WORKSPACE')
ls $__sysd
./sdl.sh pkgconfig pkg-config --libs --cflags egl
```

### Musl

Build musl cross-compilers
```
eval $(./sdl.sh env | grep musldir)
git clone --depth 1 https://github.com/richfelker/musl-cross-make.git $musldir
cd $musldir
make -j$(nproc) TARGET=aarch64-linux-musl
make -j$(nproc) TARGET=aarch64-linux-musl install OUTPUT=$PWD/aarch64
make -j$(nproc) TARGET=x86_64-linux-musl
make -j$(nproc) TARGET=x86_64-linux-musl install OUTPUT=$PWD/x86_64
```

Build with musl for x86_64:
```
export __musl=yes
./sdl.sh rebuild
TESTS=yes ./sdl.sh mkimage ovl/rootfs0 ovl/sdl
./sdl.sh qemu
```

Build with musl for aarch64:
```
export __arch=aarch64
./sdl.sh rebuild
# fails for mesa
```

### ScummVM

```
./sdl.sh scummvm_build
./sdl.sh mkimage ovl/rootfs0 ovl/sdl ovl/scummvm
./sdl.sh qemu
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
./sdl.sh libudev_build
# or
./sdl.sh libudev_build --musl
./sdl.sh pkgconfig pkg-config --libs --cflags libudev
```

## Framebuffer

The simplest graphic device is the [framebuffer](
https://www.kernel.org/doc/Documentation/fb/framebuffer.txt). It's
basically obsolete and of no use. There is no support for framebuffer
in SDL2+.

Build the kernel with:

```
> Device Drivers > Graphics support
  [*] Direct Rendering Manager (XFree86 ...
  [*] Enable legacy fbdev support
  [*] DRM Support for bochs dispi vga interface (qemu stdvga)
  [*] Bootup logo
```

and start qemu with `-vga std` or `-device virtio-gpu-pci`.


Test:
```
fbset
dd if=/dev/random of=/dev/fb0
```

### DirectFB

Is an abandoned cludge, don't use it!

The main branch doesn't build
([issue](https://github.com/deniskropp/DirectFB/issues/24)), but v1.7
does.

```
./sdl.sh directfb_build
```

## References

DRI = Direct Rendering Infrastructure

(in no particular order)

* https://wiki.libsdl.org/SDL2/Installation
* https://gist.github.com/miguelmartin75/6946310
* https://unix.stackexchange.com/questions/33596/no-framebuffer-device-how-to-enable-it
* https://wiki.libsdl.org/SDL2/FAQUsingSDL
* https://github.com/deniskropp/DirectFB
* https://forums.raspberrypi.com/viewtopic.php?t=268356
* https://dri.freedesktop.org/libdrm/libdrm-2.4.120.tar.xz
* https://docs.mesa3d.org/download.html
* https://gitlab.com/ricardoquesada/odroid-misc/-/blob/master/kmsdrm.md
* https://en.wikipedia.org/wiki/Direct_Rendering_Manager
* https://github.com/CuarzoSoftware/SRM

