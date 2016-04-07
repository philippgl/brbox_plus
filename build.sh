#!/bin/bash

# DEBUG=y
DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

if getopt -T ; test $? -ne 4 ; then
    printf 'Incompatible getopt\n' >&2
    exit 1
fi

# We need OPTIONS as the `eval set --' would nuke the return value of getopt.
options=$(getopt -o lo:c:v:b:s --long list-configs,output-dir:,config:,version:,build-number:,skip-make \
     -n 'create_image.sh' -- "$@")

if [ $? != 0 ] ; then 
    printf 'Terminating...\n' >&2
    exit 1
fi

eval set -- "$options"

br_config_file="$DIR/buildroot/.config"
output_dir="$DIR/buildroot/output"
build_ver=00
build_number=00000
# prefer an output_dir in the current directory
if [ -d "$PWD/output" ];then
    output_dir="$PWD/output"
    br_config_file="$output_dir/.config"
fi
if [ -f "$PWD/.output_dir" ] && [ -d "$(cat "$PWD/.output_dir")" ] ;then
    output_dir="$(cat "$PWD/.output_dir")"
    br_config_file="$output_dir/.config"
fi


declare -a makeopts
makeopts+=("BR2_EXTERNAL=../br_external") # relative to the buildroot directory
while true ; do
	case "$1" in
		-l|--list-configs) 
            printf 'Supported board configs:\n'
            find "$DIR/br_external/configs" -type f -printf '%f\n' | sed 's;brbox_\(.*\)_defconfig;\1;'
            exit
            ;;
		-o|--output-dir) 
            output_dir="$(realpath "$2")"
            br_config_file="$output_dir/.config"
            printf '%s' "$output_dir" >.output_dir
            test -n "$DEBUG" && printf 'Using output-dir "%s"\n' "$output_dir"
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
        -s|--skip-make)
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
makeopts+=("O=$output_dir")

"$DIR/prepare_buildroot.sh"

cd "$DIR/buildroot" || { printf 'Error: buildroot folder not found\n' >&2 ; exit 1; }

if [ -n "$br_config" ] ;then
    make "${makeopts[@]}" "brbox_${br_config}_defconfig"
    test $? -eq 0 || { printf 'Error: Could not configure %s\n' "$br_config" ; exit 1; }
fi

if [ ! -f "$br_config_file" ]; then
    printf 'Error: Config file not found: %s\n' "$br_config_file" >&2
    exit 1
fi

cfg_from_file=$(grep BR2_DEFCONFIG "$br_config_file" | sed 's;.*/configs/brbox_\(.*\)_defconfig";\1;')

if [ -n "$br_config" ] ;then
    if [ "$cfg_from_file" != "$br_config" ];then
        printf 'Error: Something went wrong during configuration\n' >&2
        printf 'Error: BR2_DEFCONFIG is not pointing to the right configuration\n' >&2
        exit 1
    fi
fi

if [ -e "$output_dir" ] && [ ! -d "$output_dir" ] ; then
    printf 'Error: %s exists and is not a directory\n' "$output_dir" >&2
    exit 1
fi

mkdir -p "$(readlink -m "$output_dir")"
if [ $? -gt 0 ]; then
    printf 'Error: Could not create or find output directory\n' >&2
    exit 1
fi

logfile="$(mktemp "$output_dir"/log-XXXX.txt)"
printf 'Stdout and stderr of the make process are logged in %s\n' "$logfile"
if [ "$skip_make" != "true" ] ;then
    make "${makeopts[@]}" &>"$logfile"
    return_state=$?

    if [ $return_state -gt 0 ]; then
        printf 'Error: Could not build %s\n' "$cfg_from_file" >&2
        exit 1
    fi
fi


cd .. || exit 1

test -n "$DEBUG" && printf 'pwd: "%s"\n' "$PWD"

build_version="${build_ver}.${build_number}"
rootfs_type=$(grep BR2_BRBOX_ROOTFS_TYPE "$br_config_file" | sed 's;.*="\(.*\)";\1;')
./scripts/brbox-mkuimg.sh -r "$output_dir/images/rootfs.tar.xz" -v "$build_version" -o "$output_dir/images/${cfg_from_file}.uimg" -m "$output_dir/host/usr/sbin/brbox-mkimage" -t "$rootfs_type"

