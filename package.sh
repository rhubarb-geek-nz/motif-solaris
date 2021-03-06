#!/bin/sh -e
#
#  Copyright 2021, Roger Brown
#
#  This file is part of rhubarb pi.
#
#  This program is free software: you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by the
#  Free Software Foundation, either version 3 of the License, or (at your
#  option) any later version.
# 
#  This program is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
#  more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>
#
# $Id: package.sh 103 2021-12-13 04:28:21Z rhubarb-geek-nz $
#

VERSION=2.3.8
EMAIL="$(git config user.email)"
VENDOR="The Open Group"

if test $(id -u) -eq 0
then
	echo Must not be root >&2
	false
fi

if test -e "/usr/dt"
then
	echo /usr/dt must not exist >&2
	false
fi

clean()
{
	rm -rf intdir dist dist2 lib64.tar
	rm -rf /usr/dt/*
	sudo rmdir /usr/dt
}

trap clean 0

sudo mkdir /usr/dt

sudo chown $(id -u):$(id -g) /usr/dt

rm -rf intdir dist dist2 lib64.tar

if test ! -f "motif-$VERSION.tar.gz"
then
	curl --fail --location --output motif-$VERSION.tar.gz "https://sourceforge.net/projects/motif/files/Motif%20$VERSION%20Source%20Code/motif-$VERSION.tar.gz"
fi

ACTUAL=$(sha256sum "motif-$VERSION.tar.gz" | while read A B; do echo $A; break; done)

if test "$ACTUAL" != "859b723666eeac7df018209d66045c9853b50b4218cecadb794e2359619ebce7"
then
	echo hash of gzip is wrong $ACTUAL
	rm "motif-$VERSION.tar.gz"
	false
fi

if test ! -d "motif-$VERSION"
then
	tar xfz "motif-$VERSION.tar.gz"

	(
		cd "motif-$VERSION"

		git init

		git add *

		git commit -m "$VERSION"

		git tag "$VERSION"

		git apply "../motif-$VERSION.patch"
	)
fi

rm -rf /usr/dt/*

(
	set -ex
	cd "motif-$VERSION"

	git reset --hard

	git apply "../motif-$VERSION.patch"

	if make clean
	then
		:
	fi

	./configure --prefix=/usr/dt CFLAGS="-m64"

	make

	make install
)

(
	set -ex

	cd /usr/dt/lib

	tar cf - lib*.so*
) > lib64.tar

rm -rf /usr/dt/*

(
	set -ex
	cd "motif-$VERSION"

	git reset --hard

	git apply "../motif-$VERSION.patch"

	if make clean
	then
		:
	fi

	./configure --prefix=/usr/dt CFLAGS="-m32"

	make

	make install
)

ls -ld /usr/dt/lib lib64.tar

if test -h /usr/dt/include
then
	echo include is already link
else
	if test -d /usr/dt/include
	then
		if test -e /usr/dt/share/include
		then
			ls -ld /usr/dt/share/include
			false
		fi
		mv /usr/dt/include /usr/dt/share/
		ln -s share/include /usr/dt/include
	fi
fi

if test -h /usr/dt/man
then
	echo man is already link
else
	if test -d /usr/dt/man
	then
		if test -e /usr/dt/share/man
		then
			ls -ld /usr/dt/share/man
			false
		fi
		mv /usr/dt/man /usr/dt/share/
	fi

	ln -s share/man /usr/dt/man
fi

rm -rf intdir dist

mkdir intdir dist

(
	find /usr/dt | while read N
	do
		ISDIR=false

		if test ! -h "$N"
		then
			if test -d "$N"
			then
				ISDIR=true
			fi
		fi

		if $ISDIR
		then
			echo dir "$N" 
		else
			case "$N" in
				/usr/dt/share/man/man3/* )
					echo SUNWmfman "$N" 
					;;
				/usr/dt/lib/lib* | /usr/dt/bin/xmbind | /usr/dt/lib/X11/bindings/* | /usr/dt/share/include/* | /usr/dt/share/man/man1/xmbind.1 | /usr/dt/include | /usr/dt/man )
					echo SUNWmfrun "$N"
					;;
				/usr/dt/bin/uil | /usr/dt/share/Xm/* | /usr/dt/share/man/manm/* | /usr/dt/share/man/man1/uil.1 | /usr/dt/share/man/man5/* | /usr/dt/share/man/man1/uil.1 )
					echo SUNWmfdev "$N" 
					;;
				 /usr/dt/bin/mwm  | /usr/dt/lib/X11/system.mwmrc | /usr/dt/share/man/man?/mwm* )
					echo SUNWmfwm "$N" 
					;;
				* )
					echo "+++++++++++++++++++++++++++++++++++++++++++" 1>&2
					echo "+ unknown package for $N" 1>&2
					echo "+++++++++++++++++++++++++++++++++++++++++++" 1>&2
					false
					;;
			esac
		fi
	done
) | while read PKG FILE
do
	echo processing $PKG $FILE

	ISDIR=false

	if test -h "$N"
	then
		echo $FILE is symbolic link - $(readlink "$N")
	else
		if test -d "$N"
		then
			ISDIR=true
		fi
	fi

	if $ISDIR
	then
		echo $FILE is a directory
	else
		mkdir -p "intdir/$PKG"

		(
			cd "/"
			tar cf - "./$FILE"
		) | (
			cd "intdir/$PKG"
			tar xf -
		)
	fi
done

mkdir -p intdir/SUNWdtcor/usr/dt

(
	set -ex

	cd intdir/SUNWmfrun/usr/dt/lib

	rm lib*.a lib*.la

	case "$(uname -p)" in
		i386 )
			mkdir amd64
			ln -s amd64 64
			cd amd64
			tar xvf -
			;;
		* )
			mkdir sparcv9
			ln -s sparcv9 64
			cd sparcv9
			tar xvf -
			;;
	esac
) < lib64.tar

(
	set -e

	for d in intdir/*/usr/dt/lib/lib*.so* \
			intdir/*/usr/dt/lib/sparcv9/lib*.so* \
			intdir/*/usr/dt/lib/amd64/lib*.so* 
	do
		if test ! -h "$d"
		then
			if test -f "$d"
			then
				echo stripping "$d"
				strip "$d"
			fi
		fi
	done

	for d in intdir/*/usr/dt/bin/*
	do
		if test -f "$d"
		then
			if test -x "$d"
			then
				if objdump -p "$d" > /dev/null
				then
					echo stripping "$d"
					strip "$d"
				fi
			fi
		fi
	done
)

cat > intdir/depend <<EOF
P SUNWcsr Core Solaris, (Root)
P SUNWcsu Core Solaris, (Usr)
P SUNWcsd Core Solaris Devices
EOF

./dir2pkg.sh intdir intdir/SUNWdtcor dist <<EOF
CATEGORY="system"
NAME="Solaris Desktop /usr/dt filesystem anchor"
PKG="SUNWdtcor"
ARCH="all"
VERSION="$VERSION"
VENDOR="$VENDOR"
EMAIL="$EMAIL"
BASEDIR="/"
EOF

cat > intdir/depend <<EOF
P SUNWdtcor Solaris Desktop /usr/dt filesystem anchor
P SUNWmfrun Motif RunTime Kit
EOF

./dir2pkg.sh intdir intdir/SUNWmfman dist <<EOF
CATEGORY="system"
NAME="CDE Motif Manuals"
PKG="SUNWmfman"
ARCH="all"
VERSION="$VERSION"
VENDOR="$VENDOR"
EMAIL="$EMAIL"
BASEDIR="/"
EOF

cat > intdir/depend <<EOF
P SUNWdtcor Solaris Desktop /usr/dt filesystem anchor
P SUNWmfrun Motif RunTime Kit
EOF

./dir2pkg.sh intdir intdir/SUNWmfdev dist <<EOF
CATEGORY="system"
NAME="Motif UIL compiler"
PKG="SUNWmfdev"
VERSION="$VERSION"
VENDOR="$VENDOR"
EMAIL="$EMAIL"
BASEDIR="/"
EOF

cat > intdir/depend <<EOF
P SUNWcsr Core Solaris, (Root)
P SUNWcsu Core Solaris, (Usr)
P SUNWcsd Core Solaris Devices
P SUNWdtcor Solaris Desktop /usr/dt filesystem anchor
EOF

./dir2pkg.sh intdir intdir/SUNWmfrun dist <<EOF
CATEGORY="system"
NAME="Motif $VERSION libraries, headers, xmbind and bindings"
PKG="SUNWmfrun"
VERSION="$VERSION"
VENDOR="$VENDOR"
EMAIL="$EMAIL"
BASEDIR="/"
EOF

cat > intdir/depend <<EOF
P SUNWdtcor Solaris Desktop /usr/dt filesystem anchor
P SUNWmfrun Motif RunTime Kit
EOF

./dir2pkg.sh intdir intdir/SUNWmfwm dist <<EOF
CATEGORY="system"
NAME="Motif Window Manager"
PKG="SUNWmfwm"
VERSION="$VERSION"
VENDOR="$VENDOR"
EMAIL="$EMAIL"
BASEDIR="/"
EOF

rm -rf /usr/dt/*

rm lib64.tar

mkdir dist2

for d in dist/*.pkg
do
	pkginfo -d "$d"	| while read A B C
	do
		pkgtrans "$d" dist2 "$B"
	done
done

PKGFILE="$(pwd)/motif-$VERSION-$(uname -p).pkg"

cat </dev/null >"$PKGFILE"

echo Writing "$PKGFILE"

pkgtrans -s dist2 "$PKGFILE" all

pkginfo -d "$PKGFILE"
