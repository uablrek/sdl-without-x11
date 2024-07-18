#! /bin/sh
##
## sdl.sh --
##   SDL for local host
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/${prg}_$$

die() {
    echo "ERROR: $*" >&2
    rm -rf $tmp
    exit 1
}
help() {
    grep '^##' $0 | cut -c3-
    rm -rf $tmp
    exit 0
}
test -n "$1" || help
echo "$1" | grep -qi "^help\|-h" && help

log() {
	echo "$*" >&2
}
findf() {
	f=$HOME/Downloads/$1
	test -r $f && return 0
	test -n "$ARCHIVE" && f=$ARCHIVE/$1
	test -r $f
}
findar() {
	findf $1.tar.bz2 || findf $1.tar.gz || findf $1.tar.xz || findf $1.zip
}

##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes
	cmd_versions
	unset opts
	eset \
		SDL_WORKSPACE=/tmp/tmp/$USER/SDL \
		KERNELDIR=$HOME/tmp/linux \
		__kver=linux-6.9.3 \
		__arch=x86_64 \
		__lver='' \
		__musl=''
	test "$__arch" != "x86_64" && __musl=yes
	WS=$SDL_WORKSPACE/$__arch
	eset \
		__kdir=$KERNELDIR/$__kver \
		__kcfg=$dir/config/$__kver$__lver \
		__kobj=$WS/obj/$__kver$__lver \
		__bbcfg=$dir/config/$ver_busybox \
		__sysd=$WS/sys \
		__kvm=kvm \
		musldir=$GOPATH/src/github.com/richfelker/musl-cross-make
	eset \
		__kbin=$__kobj/arch/$__arch/boot/bzImage \
		__initrd=$__kobj/initrd.cpio.gz \
		__image=$__kobj/hd.img
	sysd=$__sysd/usr/local
	mkdir -p $sysd

	if test "$cmd" = "env"; then
		set | grep -E "^($opts|sysd)="
		exit 0
	fi
	test -n "$long_opts" && export $long_opts
	mkdir -p $WS
	if test "$__musl" = "yes"; then
		test -x $musldir/$__arch/bin/$__arch-linux-musl-gcc || \
			die "No musl cross-compiler built for [$__arch]"
		export PATH=$musldir/$__arch/bin:$PATH
		musl_cc="CC=$__arch-linux-musl-cc AR=$__arch-linux-musl-ar"
		musl_at="--host=$__arch-linux-musl"
		musl_meson="--cross-file $dir/config/meson-cross.$__arch"
	fi
}
##   versions [--brief]
##     Print used sw versions
cmd_versions() {
	test "$versions_shown" = "yes" && return 0
	versions_shown=yes
	unset opts
	eset \
		ver_busybox=busybox-1.36.1 \
		ver_mesa=mesa-24.1.4 \
		ver_sdl2=SDL2-2.30.1 \
		ver_libdrm=libdrm-2.4.120 \
		ver_libsamplerate=libsamplerate-0.2.2 \
		ver_libudev=libudev-zero-1.0.3 \
		ver_drminfo=drminfo-8-1 \
		ver_directfb=DirectFB-DIRECTFB_1_7_7 \
		ver_libpciaccess=libpciaccess-libpciaccess-0.18.1 \
		ver_expat=expat-2.6.2 \
		ver_zlib=zlib-1.3.1 \
		ver_scummvm=scummvm-2.8.1 \
		ver_flux=flux-master \
		ver_kmscube=kmscube-master \
		ver_diskim=diskim-1.0.0
	test "$cmd" != "versions" && return 0
	set | grep -E "^($opts)="
	test "$__brief" = "yes" && return 0
	cat <<EOF
URLs:
https://github.com/deniskropp/flux (obsolete/not needed)
https://github.com/deniskropp/DirectFB (obsolete/not needed)
https://git.kraxel.org/cgit/drminfo/ (obsolete/not needed)
https://dri.freedesktop.org/libdrm/$ver_libdrm.tar.xz
https://github.com/libsndfile/libsamplerate/releases
https://github.com/illiliti/libudev-zero
https://archive.mesa3d.org/$ver_mesa.tar.xz
https://gitlab.freedesktop.org/xorg/lib/libpciaccess
https://github.com/libexpat/libexpat
https://github.com/madler/zlib
https://github.com/scummvm/scummvm
https://gitlab.freedesktop.org/mesa/kmscube
https://github.com/lgekman/diskim
Local clones:
github.com/richfelker/musl-cross-make
Downloaded:
EOF
	local k v
	for k in $(echo $opts | tr '|' ' '); do
		v=$(eval echo \$$k)
		if findar $v; then
			echo $f
		else
			echo "Missing archive [$v]"
		fi
	done
}
# Set variables unless already defined
eset() {
	local e k
	for e in $@; do
		k=$(echo $e | cut -d= -f1)
		opts="$opts|$k"
		test -n "$(eval echo \$$k)" || eval $e
	done
}
# cdsrc <version>
# Cd to the source directory. Unpack the archive if necessary.
cdsrc() {
	test -n "$1" || die "cdsrc: no version"
	test "$__clean" = "yes" && rm -rf $WS/$1
	if ! test -d $WS/$1; then
		findar $1 || die "No archive for [$1]"
		if echo $f | grep -qF '.zip'; then
			unzip -d $WS -qq $f || die "Unzip [$f]"
		else
			tar -C $WS -xf $f || die "Unpack [$f]"
		fi
	fi
	cmd_pkgconfig
	cd $WS/$1
}
##   rebuild [--libs] [--musl] [--arch]
##     Clean and build
cmd_rebuild() {
	rm -rf $WS
	local c
	for c in zlib_build libudev_build expat_build libpciaccess_build \
		libsamplerate_build libdrm_build mesa_build build2; do
		$me $c || die $c
	done
	test "$__libs" = "yes" && return 0
	$me build2 --tests || die "build2 --tests"
	$me kmscube_build || die kmscube
	$me busybox_build || die busybox_build
	$me kernel_build || die kernel_build
}
##   pkgconfig <cmd>
##     Fixup pkgconfig files, and set $PKG_CONFIG_LIBDIR
##     Used internally for build setup. Cli use:
##     ./sdl.sh pkgconfig pkg-config --libs --cflags <lib>
cmd_pkgconfig() {
	local d
	mkdir -p $__sysd/pkgconfig
	#export PKG_CONFIG_PATH=$__sysd/pkgconfig
	unset PKG_CONFIG_PATH
	export PKG_CONFIG_LIBDIR=$__sysd/pkgconfig
	for d in $(find $sysd -type d -name pkgconfig); do
		cp $d/* $__sysd/pkgconfig
	done
	sed -i -e "s,prefix=/usr/local,prefix=$sysd," $__sysd/pkgconfig/*
	if test "$cmd" = "pkgconfig"; then
		test -n "$1" && $@
	fi
}
##   kernel_build --tinyconfig  # Init the kcfg
##   kernel_build [--kver=] [--kcfg=] [--kdir=] [--kobj=] [--menuconfig]
##     Build the kernel
cmd_kernel_build() {
	mkdir -p $__kobj
	local make="make -C $__kdir O=$__kobj"
	if test "$__tinyconfig" = "yes"; then
		rm -r $__kobj
		mkdir -p $__kobj $(dirname $__kcfg)
		$make -C $__kdir O=$__kobj tinyconfig
		cp $__kobj/.config $__kcfg
		__menuconfig=yes
	fi

	test -r $__kcfg || die "Not readable [$__kcfg]"
	cp $__kcfg $__kobj/.config
	if test "$__menuconfig" = "yes"; then
		$make menuconfig
		cp $__kobj/.config $__kcfg
	else
		$make oldconfig
	fi
	$make -j$(nproc)
}
##   busybox_build [--bbcfg=] [--menuconfig] [--musl]
##     Build BusyBox for target aarch64-linux-musl-
cmd_busybox_build() {
	cdsrc $ver_busybox
	if test "$__menuconfig" = "yes"; then
		test -r $__bbcfg && cp $__bbcfg .config
		make menuconfig
		cp .config $__bbcfg
	else
		test -r $__bbcfg || die "No config"
		cp $__bbcfg .config
	fi
	if test "$__musl" = "yes"; then
		sed -i -E "s,CONFIG_CROSS_COMPILER_PREFIX=\"\",CONFIG_CROSS_COMPILER_PREFIX=\"$__arch-linux-musl-\"," .config
	fi
	make -j$(nproc)
}
##   initrd_build [--initrd=] [ovls...]
##     Build a ramdisk (cpio archive) with busybox and the passed
##     ovls (a'la xcluster)
cmd_initrd_build() {
	local bb=$WS/$ver_busybox/busybox
	test -x $bb || die "Not executable [$bb]"
	touch $__initrd || die "Can't create [$__initrd]"

	cmd_gen_init_cpio
	gen_init_cpio=$WS/bin/gen_init_cpio
	mkdir -p $tmp
	cat > $tmp/cpio-list <<EOF
dir /dev 755 0 0
nod /dev/console 644 0 0 c 5 1
dir /bin 755 0 0
file /bin/busybox $bb 755 0 0
slink /bin/sh busybox 755 0 0
EOF
	if test -n "$1"; then
		cmd_collect_ovls $tmp/root $@
		cmd_emit_list $tmp/root >> $tmp/cpio-list
	else
		cat >> $tmp/cpio-list <<EOF
dir /etc 755 0 0
file /init $dir/config/init-tiny 755 0 0
EOF
	fi
	rm -f $__initrd
	local uncompressed=$(echo $__initrd | sed -E 's,.[a-z]+$,,')
	local compression=$(echo $__initrd | grep -oE '[a-z]+$')
	case $compression in
		xz)
			$gen_init_cpio $tmp/cpio-list > $uncompressed
			xz -T0 $uncompressed;;
		gz)
			$gen_init_cpio $tmp/cpio-list | gzip -c > $__initrd;;
		bz)
			$gen_init_cpio $tmp/cpio-list | bzip2 -c > $__initrd;;
		*)
			die "Unknown initrd compression [$compression]";;
	esac
}
##   mkimage [--from-scratch] [ovls...]
##     Build a hd image. BusyBox is included without --from-scratch
cmd_mkimage() {
	cdsrc $ver_diskim
	local diskim=$PWD/diskim.sh
	test -x $diskim || die "Not executable [$diskim]"
	cd $dir
	local bb
	test "$__from_scratch" != "yes" && bb=$dir/ovl/busybox
	export __image
	$diskim mkimage --size=8G $bb $@
}

#   gen_init_cpio
#     Build the kernel gen_init_cpio utility
cmd_gen_init_cpio() {
	local x=$WS/bin/gen_init_cpio
	test -x $x && return 0
	mkdir -p $(dirname $x)
	local src=$__kdir/usr/gen_init_cpio.c
	test -r $src || die "Not readable [$src]"
	gcc -o $x $src
}
#   collect_ovls <dst> [ovls...]
#     Collect ovls to the <dst> dir
cmd_collect_ovls() {
	test -n "$1" || die "No dest"
	test -e $1 -a ! -d "$1" && die "Not a directory [$1]"
	mkdir -p $1 || die "Failed mkdir [$1]"
	local ovl d=$1
	shift
	for ovl in $@; do
		test -x $ovl/tar || die "Not executable [$ovl/tar]"
		$ovl/tar - | tar -C $d -x || die "Unpack [$ovl]"
	done
}
#   emit_list <src>
#     Emit a gen_init_cpio list built from the passed <src> dir
cmd_emit_list() {
	test -n "$1" || die "No source"
	local x p d=$1
	test -d $d || die "Not a directory [$d]"
	cd $d
	for x in $(find . -mindepth 1 -type d | cut -c2-); do
		p=$(stat --printf='%a' $d$x)
		echo "dir $x $p 0 0"
	done
	for x in $(find . -mindepth 1 -type f | cut -c2-); do
		p=$(stat --printf='%a' $d$x)
		echo "file $x $d$x $p 0 0"
	done
}
##   musl_install <dest>
##     Install musl libs. This is a no-op if --musl is not specified
cmd_musl_install() {
	test "$__musl" = "yes" || return 0
	test -n "$1" || die "No dest"
	local libd=$musldir/$__arch/$__arch-linux-musl/lib
	test -d $libd || die "Not a directory [$libd]"
	mkdir -p "$1/lib" || die "Mkdir failed [$1/lib]"
	cp $libd/libc.so $1/lib/ld-musl-$__arch.so.1  # The loader
	cp -L $libd/lib*.so.[0-9] $1/lib
}
##   libs [...]
##     Emit dynamic libs for the passed objects (dirs or files)
cmd_libs() {
	test -n "$__musl" && die "Can't ldd musl libs"
	local o out=$tmp/out
	mkdir -p $tmp
	touch $out
	for o in $@; do
		test -r $o || continue
		emit_libs $(find $o -type f -o -type l -executable) >> $out
	done
	cat $out | sort | uniq
}
emit_libs() {
	local f lib x
	for f in $@; do
		x=$(readlink -f $f)
		file $x | grep -q 'dynamically linked' || continue
		for lib in $(ldd $f | grep -F ' => ' | sed -E 's,.*=> +([^ ]+).*,\1,'); do
			test -r $lib || continue
			x=$(readlink -f $lib)
			file $x | grep -q 'shared object' || continue
			echo $lib
		done
	done
}

##   qemu --vga    # VGA mode help
##   qemu [--vga="-vga virtio"]
##     Start a qemu VM
cmd_qemu() {
	local vga
	test -n "$__vga" || __vga="-vga virtio"
	if test "$__vga" = "yes"; then
		cat <<EOF
VGA modes:
  --vga="-vga std"
  --vga="-vga virtio"
  --vga="-device virtio-gpu-pci"
  --vga="-device virtio-gpu-gl-pci"
EOF
		return 0
	fi
	test -r $__kbin || die "Not readable [$__kbin]"
	if test "$__lver" = "-initrd"; then
		test -r "$__initrd" || die "Not readable [$__initrd]"
		rm -rf $tmp
		exec $__kvm -m 1G -M q35 -smp 4 $__vga \
			-kernel $__kbin -initrd $__initrd -monitor none \
			-append "console=ttyS0" -serial stdio # -nographic
	fi
	test -r "$__image" || die "Not readable [$__image]"
	test -r "$__initrd" || cmd_initrd_build $dir/ovl/initfs
	local hd=$__kobj/hd-ovl.img
	qemu-img create -f qcow2 -o backing_file="$__image" -F qcow2 $hd
	rm -rf $tmp
	exec $__kvm -m 1G -M q35 -smp 4 $__vga \
		-kernel $__kbin -initrd $__initrd -monitor none \
		-drive file=$hd,if=virtio -audio driver=pa,model=virtio \
		-append "console=ttyS0" -serial stdio
}

##   build3
##     Build SDL3
cmd_build3() {
	die "Unmaintained"
	test -r "$__sdl_src/README-SDL.txt" || die "Not SDL3 source [$__sdl_src]"
	mkdir -p $__sdl_out
	cmake -S $__sdl_src -B $__sdl_out --install-prefix $__sysd || die "cmake -S"
	local opt
	test "$__clean" = "yes" && opt="$opt --clean-first"
	cmake --build $__sdl_out $opt -j$(nproc) || die "cmake --build"
	cmake --install $__sdl_out || die "cmake --install"
}
##   build2 [--tests]
##     Build SDL2
cmd_build2() {
	cdsrc $ver_sdl2
	mkdir -p build
	cd build
	test -r Makefile || ../configure $musl_at \
		--disable-video-x11 --disable-video-wayland \
		--disable-video-dummy --disable-video-opengl \
		--enable-video-kmsdrm \
		--disable-dbus --enable-pthreads \
		--disable-pulseaudio --disable-sndio --disable-fusionsound \
		--enable-libudev \
		|| die configure
	make -j$(nproc) || die make
	make DESTDIR=$__sysd install || die "make install"

	if test "$__tests" = "yes"; then
		mkdir -p test
		cd test
		test -r Makefile || ../../test/configure $musl_at \
			--with-sdl-prefix=$__sysd/usr/local \
			|| die "configure test"
		make -j$(nproc) || die make
		make DESTDIR=$__sysd install
	fi
}
##   drminfo_build
cmd_drminfo_build() {
	# drminfo have indirect dependencies to the host libudev.
	# To build drminfo, skip ./sdl.sh libudev_build for now
	test "$__musl" = "yes" && die "Cross compile not supported"
	cdsrc $ver_drminfo
	unset PKG_CONFIG_LIBDIR
	test -d build || meson setup build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   scummvm_build [--install=dir]
cmd_scummvm_build() {
	cdsrc $ver_scummvm
	./configure $musl_at --with-sdl-prefix=$__sysd/usr/local \
		--disable-all-engines \
		|| die "configure"
	make -j$(nproc) || die make
	test -n "$__install" || __install=./sys
	make DESTDIR=$__install install
}
##   directfb_build [--tests]
cmd_directfb_build() {
	test "$__musl" = "yes" && die "Cross compile not supported"
	# Flux
	if ! test -x $WS/bin/fluxcomp; then
		cdsrc $ver_flux
		test -x ./configure || ./autogen.sh || die "flux autogen"
		./configure || die configure
		make -j $(nproc) || die "flux make"
		make install DESTDIR=$PWD/sys || die "flux make install"
		cp $PWD/sys/usr/local/bin/fluxcomp $WS/bin
	fi
	export PATH=$WS/bin:$PATH

	# DirectFB must be built in the source dir
	cdsrc $ver_directfb
	test -x ./configure || ./autogen.sh || die "Autogen directfb"
	unset PKG_CONFIG_LIBDIR
	if ! test -r ./Makefile; then
		./configure --disable-debug-support --disable-trace \
			--enable-static --disable-x11 --disable-network \
			--disable-multi --enable-fbdev --disable-sdl \
			--disable-mpeg2 || die "directfb configure"
	fi
	make -j$(nproc) || die "directfb make"
	make -j$(nproc) install DESTDIR=$__sysd
	if test "$__tests" = "yes"; then
		cd tests
		make -j$(nproc) || die "directfb make tests"
	fi
}
##   libdrm_build
cmd_libdrm_build() {
	cdsrc $ver_libdrm
	test -d build || meson setup $musl_meson build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   libsamplerate_build
cmd_libsamplerate_build() {
	cdsrc $ver_libsamplerate
	test -r Makefile || ./configure $musl_at || die "configure"
	make -j$(nproc) || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   libudev_build
cmd_libudev_build() {
	cdsrc $ver_libudev
	make clean && make -j$(nproc) $musl_cc || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   mesa_build
cmd_mesa_build() {
	cdsrc $ver_mesa
	if ! test -d build; then
		meson setup $musl_meson build -Dplatforms='' -Dllvm=disabled \
			-Degl-native-platform=drm -Dglx=disabled \
			-Dgallium-drivers='swrast,virgl,kmsro' -Dvideo-codecs='' \
			-Dxmlconfig=disabled -Dvulkan-drivers='' -Dfreedreno-kmds='virtio' \
			-Dzstd=disabled || die "meson setup"
	fi
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   libpciaccess_build
cmd_libpciaccess_build() {
	cdsrc $ver_libpciaccess
	test -d build || meson setup $musl_meson -Dzlib=enabled build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   expat_build
cmd_expat_build() {
	cdsrc $ver_expat
	test -r Makefile || ./configure $musl_at --without-docbook \
		--without-tests --without-examples || die "configure"
	make -j$(nproc) || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   kmscube_build
cmd_kmscube_build() {
	cdsrc $ver_kmscube
	test -d build || meson setup $musl_meson build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   zlib_build
cmd_zlib_build() {
	cdsrc $ver_zlib
	env $musl_cc ./configure
	make -j$(nproc) $musl_cc || die make
	make install prefix=$sysd
}

##
# Get the command
cmd=$1
shift
grep -q "^cmd_$cmd()" $0 $hook || die "Invalid command [$cmd]"

while echo "$1" | grep -q '^--'; do
	if echo $1 | grep -q =; then
		o=$(echo "$1" | cut -d= -f1 | sed -e 's,-,_,g')
		v=$(echo "$1" | cut -d= -f2-)
		eval "$o=\"$v\""
	else
		if test "$1" = "--"; then
			shift
			break
		fi
		o=$(echo "$1" | sed -e 's,-,_,g')
		eval "$o=yes"
	fi
	long_opts="$long_opts $o"
	shift
done
unset o v

# Execute command
trap "die Interrupted" INT TERM
cmd_env
cmd_$cmd "$@"
status=$?
rm -rf $tmp
exit $status
