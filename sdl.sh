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
	local d
	for d in $(echo $FSEARCH_PATH | tr : ' '); do
		f=$d/$1
		test -r $f && return 0
	done
	unset f
	return 1
}
findar() {
	findf $1.tar.bz2 || findf $1.tar.gz || findf $1.tar.xz || findf $1.zip
}

##   env
##     Print environment.
cmd_env() {
	test "$envread" = "yes" && return 0
	envread=yes
	versions
	unset opts
	eset ARCHIVE=$HOME/archive
	eset FSEARCH_PATH=$HOME/Downloads:$ARCHIVE

	eset \
		SDL_WORKSPACE=/tmp/tmp/$USER/SDL \
		KERNELDIR=$HOME/tmp/linux \
		__kver=linux-6.16 \
		__arch=x86_64 \
		__musl='' \
		qemu=$dir/qemu.sh
	WS=$SDL_WORKSPACE/$__arch
	test "$__musl" = "yes" && WS="$WS-musl"
	eset \
		WS='' \
		__sysd=$WS/sys \
		__kvm=kvm \
		__patchd=$dir/patches \
		musldir=$HOME/tmp/musl-cross-make
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
		xcompile_cc="CC=$__arch-linux-musl-cc AR=$__arch-linux-musl-ar"
		xcompile_at="--host=$__arch-linux-musl"
		xcompile_meson="--cross-file $dir/config/meson-cross.$__arch"
	elif test "$__arch" = "aarch64"; then
		which aarch64-linux-gnu-gcc > /dev/null || \
			die "No cross-compiler installed for [$__arch]"
		xcompile_cc="CC=$__arch-linux-gnu-gcc AR=$__arch-linux-gnu-ar"
		xcompile_at="--host=$__arch-linux-gnu"
		xcompile_meson="--cross-file $dir/config/meson-cross-gnu.$__arch"		
	fi
}
versions() {
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
		ver_diskim=diskim-1.0.0 \
		ver_strace=strace-6.10
}
##   versions [--brief]
##     Print used sw versions
cmd_versions() {
	unset opts
	versions
	if test "$__brief" = "yes"; then
		set | grep -E "^($opts)="
		return 0
	fi
	cat <<EOF
URLs:
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

EOF
	local k v
	for k in $(echo $opts | tr '|' ' '); do
		v=$(eval echo \$$k)
		if findar $v; then
			printf "%-20s (%s)\n" $v $f
		else
			printf "%-20s (archive missing!)\n" $v
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
		if test -r "$__patchd/$1.patch"; then
			log "Apply patch [$1.patch]"
			patch -d $WS/$1 -b -p1 < $__patchd/$1.patch
		fi
	fi
	cmd_pkgconfig
	cd $WS/$1
}
##   rebuild [--libs-only]
##     Clean and build
cmd_rebuild() {
	rm -rf $WS
	local c
	for c in zlib_build libudev_build expat_build libpciaccess_build \
		libsamplerate_build libdrm_build mesa_build build2; do
		$me $c || die $c
	done
	test "$__libs_only" = "yes" && return 0
	$me build2 --tests || die "build2 --tests"
	$me kmscube_build || die kmscube
	cmd_kernel_build
	cmd_busybox_build
	cmd_initrd_build
}
##   strip <dir>
##     Recursive architecture and lib sensitive strip
cmd_strip() {
	test -n "$1" || die "No dir"
	test -d "$1" || die "Not a directory [$1]"
	local strip=strip
	test "$__musl" = "yes" && \
		strip=$musldir/$__arch/bin/$__arch-linux-musl-strip
	local f
	cd $1
	for f in $(find . -type f -executable); do
		file $f | grep -q ELF && $strip $f
	done
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
	local found=no
	for d in $(find $sysd -type d -name pkgconfig); do
		cp $d/* $__sysd/pkgconfig
		found=yes
	done
	test "$found" = "yes" && \
		sed -i -e "s,prefix=/usr/local,prefix=$sysd," $__sysd/pkgconfig/*
	if test "$cmd" = "pkgconfig"; then
		test -n "$1" && $@
	fi
}
##   kernel-build [--menuconfig]
##     Build the kernel
cmd_kernel_build() {
	admin=$me $qemu kernel-build || die kernel-build
}
##   busybox-build [--menuconfig]
##     Build BusyBox
cmd_busybox_build() {
	admin=$me $qemu busybox-build || die busybox-build
}
##   mkimage [ovls...]
##     Build an image with the application, and an initrd that
##     unpack the application to a ramdisk
cmd_mkimage() {
	admin=$me $qemu initrd-build ovl/ramdisk || die initrd-build
	admin=$me $qemu mkimage --size=400MiB ovl/rootfs ovl/admin-install $@
}
##   install [--dest=] [--force] [--base-libs-only]
##     Install base libs (including the loader) and built items
##     from $__sysd. If --dest is omitted installed files are printed.
##     The dest must NOT exist unless --force is specified
cmd_install() {
	if test -z "$__dest"; then
		install $tmp
		cd $tmp
		ls -FR
		cd $dir
	else
		if test -e $__dest; then
			test "$__force" = "yes" || die "Already exist [$__dest]"
		fi
		install $__dest
	fi
}
install() {
	local lib=gnu
	test "$__musl" = "yes" && lib=musl
	install_${__arch}_$lib $1
	test "$__base_libs_only" = "yes" || install_sys $1
}
install_sys() {
	# Libs goes to /lib, except for native install, which uses
	# /lib/x86_64-linux-gnu
	local d=$1/lib
	test "$__musl" != "yes" -a "$__arch" = "x86_64" && \
		d=$1/lib/x86_64-linux-gnu
	mkdir -p $d
	# We assume (for now) that all libs are installed in /usr/local
	local sys=$__sysd/usr/local
	test -d $sys/lib || die "Nothing built?"
	cd $sys/lib
	cp $(find . | grep -E '^./lib.*\.so\.[0-9]+$') $d
	# Copy the "dri" sub-dir
	d=$1/usr/local/lib
	mkdir -p $d/dri
	cp dri/virtio_gpu_dri.so dri/kms_swrast_dri.so dri/swrast_dri.so $d/dri
	# Copy programs
	test -d $sys/bin || return 0
	mkdir -p $1/bin
	cd $sys/bin
	cp * $1/bin
	# Copy the sdl2 tests if they are built
	local testd=$sys/libexec/installed-tests/SDL2
	if test -x $testd/testdraw2; then
		cp $testd/* $1/bin
	fi
	return 0
}
install_musl() {
	local libd=$musldir/$__arch/$__arch-linux-musl/lib
	test -d $libd || die "Not a directory [$libd]"
	local d=$1/lib
	mkdir -p "$d" || die "Mkdir failed [$d]"
	cd $libd
	cp libc.so $d/ld-musl-$__arch.so.1
	cp -L $(find . | grep -E '^./lib.*\.so\.[0-9]+$') $d
}
install_aarch64_musl() {
	install_musl $1
}
install_x86_64_musl() {
	install_musl $1
}
install_aarch64_gnu() {
	local libd=/usr/aarch64-linux-gnu
	test -x $libd/ld-linux-aarch64.so.1 || "Not installed [aarch64-linux-gnu]"
	local d=$1/lib
	mkdir -p $d
	cd $libd
	cp -L $(find . | grep -E '.*\.so\.[0-9]+$') $d
}
install_x86_64_gnu() {
	# Native install
	mkdir -p $1/lib64
	cp -L /lib64/ld-linux-x86-64.so.2 $1/lib64 || die "loader"
	local d=$1/lib/x86_64-linux-gnu
	mkdir -p $d
	local lib
	for lib in libc.so.6 libm.so.6; do
		cp -L /lib/x86_64-linux-gnu/$lib $d || die $lib
	done
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
#   build3
#     Build SDL3
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
	test -r Makefile || ../configure $xcompile_at \
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
		test -r Makefile || ../../test/configure $xcompile_at \
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
	./configure $xcompile_at --with-sdl-prefix=$__sysd/usr/local \
		--disable-all-engines \
		|| die "configure"
	make -j$(nproc) || die make
	test -n "$__install" || __install=./sys
	make DESTDIR=$__install install
}
##   libdrm_build
cmd_libdrm_build() {
	cdsrc $ver_libdrm
	test -d build || meson setup $xcompile_meson build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   libsamplerate_build
cmd_libsamplerate_build() {
	cdsrc $ver_libsamplerate
	test -r Makefile || ./configure $xcompile_at || die "configure"
	make -j$(nproc) || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   libudev_build
cmd_libudev_build() {
	cdsrc $ver_libudev
	make clean && make -j$(nproc) $xcompile_cc || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   mesa_build
cmd_mesa_build() {
	cdsrc $ver_mesa
	if ! test -d build; then
		meson setup $xcompile_meson build -Dplatforms='' -Dllvm=disabled \
			-Degl-native-platform=drm -Dglx=disabled \
			-Dgallium-drivers='swrast,virgl,kmsro,v3d' -Dvideo-codecs='' \
			-Dxmlconfig=disabled -Dvulkan-drivers='' -Dfreedreno-kmds='virtio' \
			-Dzstd=disabled || die "meson setup"
	fi
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   libpciaccess_build
cmd_libpciaccess_build() {
	cdsrc $ver_libpciaccess
	test -d build || meson setup $xcompile_meson -Dzlib=enabled build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   expat_build
cmd_expat_build() {
	cdsrc $ver_expat
	test -r Makefile || ./configure $xcompile_at --without-docbook \
		--without-tests --without-examples || die "configure"
	make -j$(nproc) || die make
	make install DESTDIR=$__sysd || die "make install"
}
##   kmscube_build
cmd_kmscube_build() {
	cdsrc $ver_kmscube
	test -d build || meson setup $xcompile_meson build
	meson compile -C build || die build
	meson install -C build --destdir $__sysd
}
##   zlib_build
cmd_zlib_build() {
	cdsrc $ver_zlib
	env $xcompile_cc ./configure
	make -j$(nproc) $xcompile_cc || die make
	make install prefix=$sysd
}
##   strace_build
cmd_strace_build() {
	cdsrc $ver_strace
	test -r Makefile || ./configure $xcompile_at --enable-mpers=no \
		|| die "configure"
	make -j$(nproc) || die make
	make install DESTDIR=$__sysd || die "make install"
}

##
# Get the command
cmd=$(echo $1 | tr -- - _)
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
