#!/bin/bash

#set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

VERSION="$([ "$1" = "" ] && echo "12" || echo "$1")"
DISPLAY_NAME="Postgres-$VERSION"
NAME="postgresql"

apt update
$SCRIPT_DIR/package-install-scripts/postgresql-$VERSION.sh

arch=$(uname -m)
[ "$arch" = "arm64" ] && arch="aarch64"
[ "$arch" = "amd64" ] && arch="$arch"

rm -rf $SCRIPT_DIR/$arch/root
mkdir -p $SCRIPT_DIR/$arch/root/usr/lib
mkdir -p $SCRIPT_DIR/$arch/root/usr/share
mkdir -p $SCRIPT_DIR/$arch/root/etc
mkdir -p $SCRIPT_DIR/$arch/root/var/lib
mkdir -p $SCRIPT_DIR/$arch/root/var/run
mkdir -p $SCRIPT_DIR/$arch/root/usr/bin

eval $(find /usr/lib/postgresql/$VERSION/bin/ -type f -perm /a+x -exec ldd {} \; \
	| grep so \
	| sed -e '/^[^\t]/ d' \
	| sed -e 's/\t//' \
	| sed -e 's/.*=..//' \
	| sed -e 's/ (0.*)//' \
	| sort \
	| uniq -c \
	| sort -n \
  | sed -u -e 's/[^\/]*\(.*\)$/cp -rL \1 \'$SCRIPT_DIR'\/'$arch'\/root\/usr\/lib\/;/g')

rm $SCRIPT_DIR/$arch/root/usr/lib/libc.so.6
rm $SCRIPT_DIR/$arch/root/usr/lib/libpthread.so.0
rm $SCRIPT_DIR/$arch/root/usr/lib/librt.so.1

chmod 777 $SCRIPT_DIR/$arch/root/usr/lib/libm.so.6

cp -r /usr/lib/postgresql $SCRIPT_DIR/$arch/root/usr/lib/postgresql
cp -r /usr/share/postgresql $SCRIPT_DIR/$arch/root/usr/share/postgresql
cp -r /etc/postgresql $SCRIPT_DIR/$arch/root/etc/postgresql

mkdir -p $SCRIPT_DIR/$arch/root/var/lib/postgresql/$VERSION

chmod -R 775 $SCRIPT_DIR/$arch/root/var/lib/postgresql
chmod -R 775 $SCRIPT_DIR/$arch/root/usr/lib/postgresql
chmod -R 775 $SCRIPT_DIR/$arch/root/etc/postgresql

# now build the app image

appPath="$SCRIPT_DIR/out/$NAME-$VERSION-$arch.AppDir"
rm -rf $appPath
mkdir -p $appPath
cp $SCRIPT_DIR/logo.png $appPath/
cp $SCRIPT_DIR/run.sh $appPath/AppRun
cp -rf $SCRIPT_DIR/$arch/root $appPath/root
echo $VERSION > $appPath/VERSION
echo "[Desktop Entry]
Name=$DISPLAY_NAME
Exec=AppRun
Icon=logo
Type=Application
Terminal=true
Categories=Utility;" > $appPath/$NAME-$VERSION-$arch.desktop

apt-get -y install libglib2.0-0 file wget
wget https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-$arch.AppImage
chmod u+x appimagetool-$arch.AppImage
ARCH=$arch ./appimagetool-$arch.AppImage --appimage-extract-and-run $appPath

mkdir -p $SCRIPT_DIR/dist
rm -rf $SCRIPT_DIR/dist/$DISPLAY_NAME-$arch.AppImage
cp $DISPLAY_NAME-$arch.AppImage $SCRIPT_DIR/dist/