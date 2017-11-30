#!/bin/sh
PREREQ=""
prereqs()
{
  echo "$PREREQ"
}

case $1 in
  prereqs)
    prereqs
    exit 0
    ;;
esac

. /usr/share/initramfs-tools/hook-functions

# nfp dependency must be available, else quit without error
have_module nfp || exit 0

# Add firmware images
for FILE in /lib/firmware/netronome/*.nffw; do
    TARGET=`readlink $FILE`
    copy_exec $TARGET /lib/firmware/netronome/
done

copy_exec /lib/udev/rules.d/79-agilio-nic.rules /lib/udev/rules.d/
copy_exec /lib/udev/agilio-nic-name-gen /lib/udev/

# Add NFP kernel module
manual_add_modules nfp

exit 0
