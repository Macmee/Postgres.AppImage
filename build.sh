#!/bin/bash

#set -x
# DOCKER_DEFAULT_PLATFORM=linux/amd64 docker run --rm -v $HOME/scrapyard/portable-postgres:$SCRIPT_DIR -it debian:buster /bin/bash


# export DEBIAN_FRONTEND=noninteractive
# apt -y install gnupg2 wget lsb-release apt-utils
# wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
# echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee  /etc/apt/sources.list.d/pgdg.list
# apt update
# apt -y install postgresql-12 postgresql-client-12 postgis postgresql-12-postgis-3 postgresql-12-postgis-3-scripts

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

apt update
$SCRIPT_DIR/package-install-scripts/postgresql-12.sh

DISPLAY_NAME="Postgres-12"
NAME="postgresql"
VERSION="12"

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

eval $(find /usr/lib/postgresql/12/bin/ -type f -perm /a+x -exec ldd {} \; \
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
#cp -r /var/run/postgresql $SCRIPT_DIR/$arch/root/var/run/postgresql

mkdir -p $SCRIPT_DIR/$arch/root/var/lib/postgresql/12
mkdir -p /var/run/postgresql

chmod -R 755 $SCRIPT_DIR/$arch/root/var/lib/postgresql
chmod -R 755 $SCRIPT_DIR/$arch/root/etc/postgresql

# now build the app image

appPath="$SCRIPT_DIR/out/$NAME-$VERSION-$arch.AppDir"
rm -rf $appPath
mkdir -p $appPath
cp $SCRIPT_DIR/logo.png $appPath/
cp $SCRIPT_DIR/run.sh $appPath/AppRun
cp -rf $SCRIPT_DIR/$arch/root $appPath/root
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
./appimagetool-$arch.AppImage --appimage-extract-and-run $appPath

mkdir -p $SCRIPT_DIR/dist
rm -rf $SCRIPT_DIR/dist/$DISPLAY_NAME-$arch.AppImage
cp $DISPLAY_NAME-$arch.AppImage $SCRIPT_DIR/dist/