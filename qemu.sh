#! /bin/sh
##
## qemu.sh --
##
##   Help script for running kvm/qemu. This script is intended to
##   be managed by a parent "admin.sh" script.
##
##   Even though this script is named "qemu.sh", actually all
##   functions except "run", like build-kernel, build-initrd, etc. are
##   generic.
##
## Commands;
##

prg=$(basename $0)
dir=$(dirname $0); dir=$(readlink -f $dir)
me=$dir/$prg
tmp=/tmp/tmp/$USER/${prg}_$$

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
# Set variables unless already defined. Vars are collected into $opts
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
	cd $WS/$1
}
##   env
##     Print environment.
cmd_env() {
	test "$envset" = "yes" && return 0
	envset=yes
	eset \
		ver_kernel=linux-6.16 \
		ver_busybox=busybox-1.36.1
	unset opts

	test -n "$long_opts" && export $long_opts # (before admin env)
	eset admin=$dir/admin.sh
	if test -x $admin; then
		eval $($admin env | grep -E '(__musl|__arch|WS)=')
		test -n "$WS" || log "WARNING: admin has no WS"
	fi
	eset ARCHIVE=$HOME/archive
	eset FSEARCH_PATH=$HOME/Downloads:$ARCHIVE
	eset KERNELDIR=$HOME/tmp/linux
	eset WS=/tmp/tmp/$USER/qemu
	eset __arch='x86_64'
	eset \
		__musl='no' \
		musldir=$HOME/tmp/musl-cross-make \
		__kcfg=$dir/config/$__arch/$ver_kernel \
		__kdir=$KERNELDIR/$ver_kernel \
		__kobj=$WS/obj/$ver_kernel \
		__bbcfg=$dir/config/$ver_busybox \
		__initrd=$WS/initrd.bz2 \
		__mem=1G \
		disk=$dir/disk.sh \
		__image=$WS/hd.img

	if test "$__arch" = "aarch64"; then
		eset kernel=$__kobj/arch/arm64/boot/Image.gz
	else
		eset kernel=$__kobj/arch/x86/boot/bzImage
	fi

	if test "$cmd" = "env"; then
		set | grep -E "^($opts)="
		exit 0
	fi

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
	cd $dir
}
##   versions [--brief]
##     Print used sw versions
cmd_versions() {
	unset opts
	set | grep -E "^ver_.*="
	test "$__brief" = "yes" && return 0
	local k v
	for k in $(set | grep -E "^ver_.*=" | cut -d= -f1); do
		v=$(eval echo \$$k)
		if findar $v; then
			printf "%-20s (%s)\n" $v $f
		else
			printf "%-20s (archive missing!)\n" $v
		fi
	done
}
##   rebuild [--arch=] [--musl]
##     Clear and rebuild the kernel and busybox. Default is native build
cmd_rebuild() {
	rm -rf $WS
	$me kernel_build || die kernel_build
	$me busybox_build || die busybox_build
	log "Everything built OK"
}
cmd_kernel_unpack() {
	test -d $__kdir && return 0	  # (already unpacked)
	log "Unpack kernel to [$__kdir]..."
	findar $ver_kernel || die "Kernel source not found [$ver_kernel]"
	mkdir -p $KERNELDIR
	tar -C $KERNELDIR -xf $f
}
##   kernel-build --initconfig=     # Init the kcfg
##   kernel-build [--clean] [--menuconfig]
##     Build the kernel
cmd_kernel_build() {
	cmd_kernel_unpack
	test "$__clean" = "yes" && rm -rf $__kobj
	mkdir -p $__kobj

	local CROSS_COMPILE make targets
	make="make -C $__kdir O=$__kobj"
	if test "$__native" != "yes"; then
		if test "$__arch" = "aarch64"; then
			make="$make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
			targets="Image.gz modules dtbs"
		else
			make="$make ARCH=x86_64 CROSS_COMPILE=x86_64-linux-gnu-"
		fi
	fi
	if test -n "$__initconfig"; then
		rm -r $__kobj
		mkdir -p $__kobj $(dirname $__kcfg)
		$make -C $__kdir O=$__kobj $__initconfig
		cp $__kobj/.config $__kcfg
		test "$__menuconfig" = "yes" || return 0
	fi

	test -r $__kcfg || die "Not readable [$__kcfg]"
	cp $__kcfg $__kobj/.config
	if test "$__menuconfig" = "yes"; then
		$make menuconfig
		cp $__kobj/.config $__kcfg
	else
		$make oldconfig
	fi
	$make -j$(nproc) $targets
}
##   kernel-config [--kcfg=] [--reset] [--kconfiglib] [config-files...]
##     Use the "scripts/config" script, or "kconfiglib", to alter the
##     kernel-config. With --reset the kernel config is initiated from
##     "tinyconfig"
cmd_kernel_config() {
	test "$__reset" = "yes" && \
		$me kernel_build --initconfig=tinyconfig --menuconfig=no
	test -r $__kcfg || die "Not readable [$__kcfg]"
	if test "$__kconfiglib" = "yes"; then
		kernel_config_kconfiglib $@
		return
	fi
	local config="$__kdir/scripts/config --file $__kcfg"
	local cfile k v line
	for cfile in $@; do
		test -r "$cfile" || die "Not readable [$cfile]"
		while read line; do
			echo $line | grep -qE '^[A-Z0-9]' || continue
			log $line
			k=$(echo $line | cut -d= -f1)
			v=$(echo $line | cut -d= -f2-)
			if echo $v | grep -qE '^(y|n|m)$'; then
				case $v in
					y) $config --enable $k;;
					n) $config --disable $k;;
					m) $config --module $k;;
				esac
			elif echo $v | grep -qF '"'; then
				$config --set-str $k "$(echo $v | tr -d '"')"
			else
				$config --set-val $k $v
			fi
		done < $cfile
	done
}
kernel_config_kconfiglib() {
	test -n "$kconfiglib" || die 'Not set [$kconfiglib]'
	test -r $kconfiglib/kconfiglib.py || \
		die "Not readable [$kconfiglib/kconfiglib.py]"
	export PYTHONPATH=$kconfiglib
	local opts cfile
	for cfile in $@; do
		opts=$(grep -E '^[A-Z0-9]' $cfile | tr -d '"')
		SRCARCH=x86 ARCH=x86 CC=gcc LD=ld srctree=$__kdir \
			KERNELVERSION=$ver_kernel KCONFIG_CONFIG=$__kcfg \
			$kconfiglib/setconfig.py $opts || die "kconfiglib"
	done
}
##   busybox_build [--bbcfg=] [--menuconfig]
##     Build BusyBox
cmd_busybox_build() {
	cdsrc $ver_busybox
	if test "$__menuconfig" = "yes"; then
		test -r $__bbcfg && cp $__bbcfg ./.config
		make menuconfig
		cp ./.config $__bbcfg
	else
		test -r $__bbcfg || die "No config"
		cp $__bbcfg ./.config
	fi
	if test "$__musl" = "yes" -o "$__arch" != "x86_64"; then
		local cfg="CONFIG_CROSS_COMPILER_PREFIX"
		local lib=gnu
		test "$__musl" = "yes" && lib=musl
		local prefix=$__arch-linux-$lib-
		sed -i -E "s,$cfg=\"\",$cfg=\"$prefix\"," .config
	fi
	make -j$(nproc) || die make
	return 0
}
##   initrd-build [--initrd=] [ovls...]
##     Build a ramdisk (cpio archive) containing busybox and
##     (optionally) overlays
cmd_initrd_build() {
	local bb=$WS/$ver_busybox/busybox
	test -x $bb || die "Not executable [$bb]"
	rm -f $__initrd

	cmd_gen_init_cpio
	gen_init_cpio=$WS/bin/gen_init_cpio
	mkdir -p $tmp
	cat > $tmp/cpio-list <<EOF
dir /dev 755 0 0
nod /dev/console 644 0 0 c 5 1
dir /bin 755 0 0
dir /etc 755 0 0
file /bin/busybox $bb 755 0 0
slink /bin/sh busybox 755 0 0
EOF
	mkdir -p $tmp/root
	__dest=$tmp/root
	test -n "$1" -o -n "$INITRD_OVL" && \
		cmd_unpack_ovls $INITRD_OVL $@
	test -x $tmp/root/init || \
		cp $dir/config/init-tiny $tmp/root/init
	cmd_emit_list $tmp/root >> $tmp/cpio-list

	local uncompressed=$(echo $__initrd | sed -E 's,\.[a-z]+$,,')
	$gen_init_cpio $tmp/cpio-list > $uncompressed
	local compression=$(echo $__initrd | grep -oE '\.[a-z]+$')
	case $compression in
		.xz)
			xz -T0 $uncompressed || die xz;;
		.gz)
			gzip $uncompressed || die gzip;;
		.bz2)
			bzip2 $uncompressed || die bzip2;;
	esac
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
#   unpack_ovls --dest= [ovls...]
#     Unpack ovls
cmd_unpack_ovls() {
	test -n "$__dest" || die "No dest"
	test -e $__dest -a ! -d "$__dest" && die "Not a directory [$__dest]"
	mkdir -p $__dest || die "Failed mkdir [$__dest]"
	local ovl
	for ovl in $@; do
		test -x $ovl/tar || die "Not executable [$ovl/tar]"
		$ovl/tar - | tar -C $__dest -x || die "Unpack [$ovl]"
	done
}
##   lsovls <ovls...>
##     List contents of ovl's
cmd_lsovls() {
	test -n "$1" || return 0
	__dest=$tmp
	cmd_unpack_ovls $@
	cd $tmp
	find . ! -type d | sed -E 's,^\./,,'
	cd $dir
}
#   emit_list <src>
#     Emit a gen_init_cpio list built from the passed <src> dir
cmd_emit_list() {
	test -n "$1" || die "No source"
	local x p target d=$1
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
	for x in $(find . -mindepth 1 -type l | cut -c2-); do
		target=$(readlink $d$x)
		echo "slink $x $target 777 0 0"
	done
}
##   modules-install --dest=
##     Install kernel modules
cmd_modules_install() {
	test -n "$__dest" || die "No --dest"
	mkdir -p $__dest || die "Mkdir [$__dest]"
	test -r "$__kobj/Makefile" || die "Not readable [$__kobj/Makefile]"
    INSTALL_MOD_PATH=$__dest make -j$(nproc) -C $__kobj modules_install \
        1>&2 > /dev/null || die "Failed to install modules from [$__kobj]"
}
##   lsmod
##     List modules built (not loaded) in the kernel
cmd_lsmod() {
	__dest=$tmp
	cmd_modules_install
	find $tmp -name '*.ko' | grep -oE '[^/]+.ko$' | sed -e 's,\.ko,,'
}
##   install --dest=
##     Install the application using the parent admin script
cmd_install() {
	test -n "$__dest" || die "No --dest"
	test -x $admin || die "Not executable [$admin]"
	grep -qF "cmd_install()" $admin || die "No install function in [$admin]"
	$admin install $__dest		# ($__dest is already exported)
}
##   mkimage --clean
##   mkimage [--image=] [--size=128MiB] <ovls...>
##     Create a hard-disk image
cmd_mkimage() {
	if test "$__clean" = "yes"; then
		rm -f $__image
		return 0
	fi
	test -x $disk || die "Not executable [$disk]"
	rm -f $__image
	eset __size=128MiB
	export __image __size
	$disk mkimage --fat || die "$disk mkimage"
	$disk mkfat --p=1 || die "mkfat p1"
	$disk mkfat --p=2 -- -n qemu-data || die "mkfat p2"
	test -n "$1" || return 0	# (an empty disk)
	__dest=$tmp
	cmd_unpack_ovls $@
	__dev=$($disk loop-setup)
	echo $__dev | grep '/dev/loop' || die loop-setup
	export __dev
	local mnt=$($disk mount --p=2)
	log "Mount at [$mnt]"
	test -n "$mnt" -a -d "$mnt" || die mount
	cd $tmp
	tar -cf $mnt/rootfs.tar *
	$disk unmount --p=2
	$disk loop-delete
}
##   mktap [--bridge=|--adr=] <tap>
##     Create a network tun/tap device.  The tun/tap device can
##     optionally be attached to a bridge.
##     Requires "sudo"!
cmd_mktap() {
	test -n "$1" || die "Parameter missing"
	if ip link show dev $1 > /dev/null 2>&1; then
		log "Device exists [$1]"
		return 0
	fi
	if test -n "$__bridge"; then
		ip link show dev $__bridge > /dev/null 2>&1 \
			|| die "Bridge does not exist [$__bridge]"
	fi
	sudo ip tuntap add $1 mode tap user $USER || die "Create tap"
	sudo ip link set up $1
	if test -n "$__bridge"; then
		sudo ip link set dev $1 master $__bridge || die "Attach to bridge"
	elif test -n "$__adr"; then
		local opt
		echo "$__adr" | grep -q : && opt=-6
		sudo ip $opt addr add $__adr dev $1 || die "Set address [$__adr]"
	fi
}
##   run
##     Start a qemu VM. Optionally with files from --root
cmd_run() {
	test -r $kernel || die "Not readable [$kernel]"
	test -r $__initrd || die "Not readable [$__initrd]"
	rm -rf $tmp					# (since we 'exec')
	qemu_$__arch $@
}
qemu_x86_64() {
	local opt=-nographic
	if test "$__graphic" = "yes"; then
		# "-vga std"
		# "-vga virtio"
		# "-device virtio-gpu-pci"
		# "-device virtio-gpu-gl-pci"
		# -device qxl -display gtk,gl=on
		#opt="-device virtio-gpu-pci -display gtk,gl=on"
		opt="-device virtio-gpu-pci -display sdl"
	fi
	test -r "$__image" && \
		opt="$opt -drive file=$__image,index=0,media=disk,if=virtio,format=raw"
	exec qemu-system-x86_64 -enable-kvm -M q35 -m $__mem -smp 2 \
		$opt -append "init=/init $__append" \
		-monitor none -serial stdio -kernel $kernel  -initrd $__initrd $@
}
qemu_aarch64() {
	local opt=-nographic
	if test "$__graphic" = "yes"; then
		opt="-device virtio-gpu-pci -display sdl"
	fi
	if test -r "$__image"; then
		#https://forums.gentoo.org/viewtopic-t-1167745-start-0.html
		opt="$opt -drive if=none,file=$__image,format=raw,id=hd"
		opt="$opt -device virtio-blk-device,drive=hd"
	fi
	exec qemu-system-aarch64 -cpu cortex-a72 -m $__mem -smp 2 \
		-machine virt,virtualization=on,secure=off \
		$opt -append "init=/init $__append" \
		-monitor none -serial stdio -kernel $kernel -initrd $__initrd $@
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
