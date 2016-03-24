#!/bin/bash

DEBUG=y

if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" ./prepare_build_root.sh
else
    ./prepare_build_root.sh
fi

if getopt -T ; test $? -ne 4 ; then
    printf 'Incompatible getopt\n' >&2
    exit 1
fi

# We need OPTIONS as the `eval set --' would nuke the return value of getopt.
options=$(getopt -o lo:c:v:b:sS --long list-configs,output-dir:,config:,version:,build-number:skip-config,skip-make \
     -n 'create_image.sh' -- "$@")

if [ $? != 0 ] ; then 
    printf 'Terminating...\n' >&2
    exit 1
fi

eval set -- "$options"

br_config_file="$PWD/buildroot/.config"
build_ver=00
build_number=00000
output_dir="output"


declare -a makeopts
makeopts+=("BR2_EXTERNAL=../br_external")
while true ; do
	case "$1" in
		-l|--list-configs) 
            printf 'Supported board configs:\n'
            find br_external/configs -type f -printf '%f\n' | sed 's;brbox_\(.*\)_defconfig;\1;'
            exit
            ;;
		-o|--output-dir) 
            output_dir="$2"
            br_config_file="$output_dir/.config"
            test -n "$DEBUG" && printf 'Using output-dir "%s"\n' "$output_dir"
            makeopts+=("O=$output_dir")
            shift 2 
            ;;
		-c|--config)
			br_config="$2"
            shift 2
            ;;
		-v|--version)
			build_ver="$2"
            shift 2
            ;;
		-b|--build-number)
			build_number="$2"
            shift 2
            ;;
        -s|--skip-config)
            skip_config="true"
            shift
            ;;
        -S|--skip-make)
            skip_config="true"
            skip_make="true"
            shift
            ;;
		--) 
            shift
            break 
            ;;
		*) 
            printf 'Error: could not parse arguments!\n' >&2
            exit 1
            ;;
	esac
done


if [ $UID -gt 0 ]; then
    printf 'Error: Please run this command using "sudo %s"\n' "$0" >&2
    exit 1
fi

cd buildroot || { printf 'Error: buildroot folder not found\n' >&2 ; exit 1; }

git checkout --force

if [ -n "$br_config" ] && [ "$skip_config" != "true" ] ;then
    sudo -u "$SUDO_USER" make "${makeopts[@]}" "brbox_${br_config}_defconfig"
    test $? -eq 0 || { printf 'Error: Could not configure %s\n' "$br_config" ; exit 1; }
fi

cfg_from_file=$(grep BR2_DEFCONFIG "$br_config_file" | sed 's;.*/configs/brbox_\(.*\)_defconfig";\1;')

if [ -n "$br_config" ] ;then
    if [ "$cfg_from_file" != "$br_config" ];then
        printf 'Error: Something went wrong during configuration\n' >&2
        printf 'Error: BR2_DEFCONFIG is not pointing to the right configuration\n' >&2
        exit 1
    fi
fi

if [ "$skip_make" != "true" ] ;then
    sudo -u "$SUDO_USER" make "${makeopts[@]}"
    test $? -eq 0 || { printf 'Error: Could not build %s\n' "$cfg_from_file" ; exit 1; }
fi

disk_size=$(grep BR2_BRBOX_DISKSIZE "$br_config_file" | sed 's;BR2_BRBOX_DISKSIZE="\(.*\)";\1;')
partition_size=$(grep BR2_BRBOX_PARTITIONSIZE "$br_config_file" | sed 's;BR2_BRBOX_PARTITIONSIZE="\(.*\)";\1;')

if [ -n "$DEBUG" ]; then
    printf 'Disk size: %s\n' "$disk_size"
    printf 'Partition size: %s\n' "$partition_size"
fi

image_filename="$output_dir/images/bootable-usb-disk.img"

fallocate -l "$disk_size" "$image_filename"
test $? -eq 0 || { printf 'Could not create %s\n' "$image_filename" >&2 ; exit 1; }

BOOTSIZE=1M
STTNGSIZE=16M
ROOT1_LABEL=ROOT1   #linux-1
ROOT2_LABEL=ROOT2   #linux-2
STTNG_LABEL=STTNG   #settings
USRDAT_LABEL=USRDAT #userdata
# IMAGE_VERSION=01.00.12345
GRUB_MENU_ENTRY1='brbox1'
GRUB_MENU_ENTRY2='brbox2'
GRUB2_TIMEOUT=1
ROOTDELAY=5

# Formatting disk
sgdisk -Z "$image_filename" >/dev/null
sgdisk -n 1::+"$BOOTSIZE"   -t 1:ef02 -c 1:boot  "$image_filename" >/dev/null
sgdisk -n 2::+"$partition_size"  -c 2:$ROOT1_LABEL    "$image_filename" >/dev/null
sgdisk -n 3::+"$partition_size"  -c 3:$ROOT2_LABEL    "$image_filename" >/dev/null
sgdisk -n 4::+"$STTNGSIZE"  -c 4:$STTNG_LABEL    "$image_filename" >/dev/null
sgdisk -n 5:: -c 5:$USRDAT_LABEL   "$image_filename" >/dev/null
test $? -eq 0 || { printf 'Could not partition %s\n' "$image_filename" >&2 ; exit 1; }

echo "Creating disk image"
loopdevice=$(losetup -f --show "$image_filename")
test $? -eq 0 || { printf 'Could not setup loop device %s\n' "$image_filename" >&2 ; exit 1; }

partx -a "$loopdevice"
test $? -eq 0 || { printf 'Could not find partitions\n' >&2 ; exit 1; }

echo "Formating disk image"
mkfs.ext3 -L $ROOT1_LABEL "${loopdevice}p2" 1>/dev/null 2>/dev/null
test $? -eq 0 || { printf 'Formatting %s failed\n' $ROOT1_LABEL >&2 ; exit 1; }
mkfs.ext3 -L $ROOT2_LABEL "${loopdevice}p3" 1>/dev/null 2>/dev/null
test $? -eq 0 || { printf 'Formatting %s failed\n' $ROOT2_LABEL >&2 ; exit 1; }
mkfs.ext3 -L $STTNG_LABEL "${loopdevice}p4" 1>/dev/null 2>/dev/null
test $? -eq 0 || { printf 'Formatting %s failed\n' $STTNG_LABEL >&2 ; exit 1; }
mkfs.ext3 -L $USRDAT_LABEL "${loopdevice}p4" 1>/dev/null 2>/dev/null
test $? -eq 0 || { printf 'Formatting %s failed\n' $USRDAT_LABEL >&2 ; exit 1; }

mountdir=$(mktemp -d)
mkdir "$mountdir/root1" "$mountdir/root2"
mount "${loopdevice}p2" "$mountdir/root1"
test $? -eq 0 || { printf 'Could not mount root1\n' >&2 ; exit 1; }
mount "${loopdevice}p3" "$mountdir/root2"
test $? -eq 0 || { printf 'Could not mount root2\n' >&2 ; exit 1; }

echo "Copying files"
rootfs="$output_dir/images/rootfs.tar.xz"
tar -C "$mountdir/root1" -Jxf "$rootfs"
test $? -eq 0 || { printf 'Could not extract files onto root1\n' >&2; exit 1; }
tar -C "$mountdir/root2" -Jxf "$rootfs"
test $? -eq 0 || { printf 'Could not extract files onto root2\n' >&2; exit 1; }

echo "Generating grub configs"
cat <<ENDOFGRUBCFG >"$output_dir/grub.cfg.in"
insmod part_gpt
insmod part_msdos
insmod ext2
search -l $ROOT1_LABEL -s root
if [ -e /boot/grub/grub.cfg ]; then
	configfile /boot/grub/grub.cfg
else
	search -l $ROOT2_LABEL -s root
	configfile /boot/grub/grub.cfg
fi
ENDOFGRUBCFG
test $? -eq 0 || { printf 'Could not create grub.cfg.in\n' >&2 ; exit 1; }

part1uuid=$(sgdisk -i=2 "$loopdevice" |grep 'Partition unique GUID' |cut -d\  -f4)
part2uuid=$(sgdisk -i=3 "$loopdevice" |grep 'Partition unique GUID' |cut -d\  -f4)

cat <<ENDOFGRUBCFG >"$output_dir/grub.cfg"
set timeout=$GRUB2_TIMEOUT
set default=0
insmod ext2
menuentry $GRUB_MENU_ENTRY1 {
    search -l $ROOT1_LABEL -s root
    linux /boot/bzImage rootdelay=$ROOTDELAY consoleblank=0 ro enable_mtrr_cleanup mtrr_spare_reg_nr=1 brboxsystem=$GRUB_MENU_ENTRY1 net.ifnames=0 root=PARTUUID=$part1uuid
}
menuentry $GRUB_MENU_ENTRY2 {
    search -l $ROOT2_LABEL -s root
    linux /boot/bzImage rootdelay=$ROOTDELAY consoleblank=0 ro enable_mtrr_cleanup mtrr_spare_reg_nr=1 brboxsystem=$GRUB_MENU_ENTRY2 net.ifnames=0 root=PARTUUID=$part2uuid
}
ENDOFGRUBCFG
test $? -eq 0 || { printf 'Could not create grub.cfg\n' >&2 ; exit 1; }

echo "Installing grub"
"$output_dir/host/usr/bin/grub-mkimage" -d "$output_dir/host/usr/lib/grub/i386-pc" \
    -O i386-pc -o "$output_dir/images/grub.img" -c "$output_dir/grub.cfg.in" \
    acpi cat boot linux ext2 fat part_msdos part_gpt normal biosdisk \
    search echo search_fs_uuid normal ls ata configfile halt help \
    hello read png vga lspci echo minicmd vga_text terminal
test $? -eq 0 || { printf 'Could not generate grub.img\n' >&2 ; exit 1; }

"$output_dir/host/usr/sbin/grub-bios-setup" \
    -b "$output_dir/host/usr/lib/grub/i386-pc/boot.img" \
    -c "$output_dir/images/grub.img" -d / "$loopdevice"
test $? -eq 0 || { printf 'Could setup grub\n' >&2 ; exit 1; }

cp "$output_dir/grub.cfg" "$mountdir/root1/boot/grub/grub.cfg"
cp "$output_dir/grub.cfg" "$mountdir/root2/boot/grub/grub.cfg"

umount "$mountdir/root1"
umount "$mountdir/root2"

echo "Cleaning up"
rm -rf "$mountdir"
partx -d "$loopdevice"
losetup -d "$loopdevice"
sync

chown "$SUDO_UID:$SUDO_GID" "$image_filename"

build_version="${build_ver}.${build_number}"

cd .. || exit 1

test -n "$DEBUG" && printf 'pwd: "%s"\n' "$PWD"

rootfs_type=$(grep BR2_BRBOX_ROOTFS_TYPE "$br_config_file" | sed 's;.*="\(.*\)";\1;')
sudo -u "$SUDO_USER" ./scripts/brbox-mkuimg.sh -r "$output_dir/images/rootfs.tar.xz" -v "$build_version" -o "$output_dir/images/${cfg_from_file}.uimg" -m "$output_dir/host/usr/sbin/brbox-mkimage" -t "$rootfs_type"

