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

# Add NFP kernel module
manual_add_modules nfp


# Add firmware images
for FILE in `find /lib/firmware/netronome -maxdepth 1 -name *.nffw`; do
    TARGET=`readlink $FILE`
    copy_exec $TARGET /lib/firmware/netronome/
done

exit 0
