#!/bin/bash

#set -x

allArgs="$@" # cute little helper to read "--name value" arguments!
arg() { echo $allArgs | grep "\-\-$1 " | grep -Ev "\-\-$1 \-\-[a-z]" | sed -e "s/^.*\-\-$1 \([^ ^$]*\).*$/\1/" ; }

BASE="$APPDIR/root"

customEnv="PATH=$PATH:$BASE/usr/lib/postgresql/12/bin LD_LIBRARY_PATH=$BASE/usr/lib"

# some distros (fedora docker image) dont have su so we need to use sudo

suCmd="su"
! command -v su > /dev/null && suCmd="sudo -u"

# if the user specified a specific binary to run, lets do that and bail

if ! [ "$1" = "" ] && [ -f "$BASE/usr/lib/postgresql/12/bin/$1" ]; then
  args="${@:2}"
  eval $customEnv $1 $args
  exit $?
fi

# otherwise we want to start the database and/or init a new one... start by creating a postgres user

mkdir -p /home/postgres
useradd -d /home/postgres postgres
chown postgres /home/postgres

# we have to turn off a bunch of settings by default

function deleteFromConfigFile() {
  cat $BASE/etc/postgresql/12/main/postgresql.conf | grep -v "$1" > tmp_cfg
  cat tmp_cfg > $BASE/etc/postgresql/12/main/postgresql.conf
  rm -f tmp_cfg
}
deleteFromConfigFile data_directory
deleteFromConfigFile ssl_cert_file
deleteFromConfigFile ssl_key_file
deleteFromConfigFile "ssl = on"
deleteFromConfigFile listen_addresses
deleteFromConfigFile stats_temp_directory
deleteFromConfigFile hba_file

echo "listen_addresses = '*'" >> $BASE/etc/postgresql/12/main/postgresql.conf
echo "stats_temp_directory = 'stats'" >> $BASE/etc/postgresql/12/main/postgresql.conf

mkdir -p /var/run/postgresql
chown -R postgres /var/run/postgresql
chown -R postgres $BASE/var/lib/postgresql
chown -R postgres $BASE/var/run/postgresql
chown -R postgres $BASE/etc/postgresql

# respect given locale and fallback to en_US.utf8 if needed

useLocale=$([ "$(arg locale)" = "" ] && echo "C.UTF-8" || arg locale)
(! locale -a | sed -e 's/-//g' | grep -i C.UTF8) && useLocale="en_US.utf8"

deleteFromConfigFile lc_messages
deleteFromConfigFile lc_monetary
deleteFromConfigFile lc_numeric
deleteFromConfigFile lc_time
echo "lc_messages = '$useLocale'" >> $BASE/etc/postgresql/12/main/postgresql.conf
echo "lc_monetary = '$useLocale'" >> $BASE/etc/postgresql/12/main/postgresql.conf
echo "lc_numeric = '$useLocale'" >> $BASE/etc/postgresql/12/main/postgresql.conf
echo "lc_time = '$useLocale'" >> $BASE/etc/postgresql/12/main/postgresql.conf

# resolve the database path and init the db there if the folder is empty

dbPath=$([ "$(arg path)" = "" ] && echo "$BASE/var/lib/postgresql/12/main" || arg path)
chown -R postgres $dbPath
rm -f $dbPath/.DS_Store
shouldInitDb=$([ -z "$(ls -A $dbPath)" ] && echo true || echo false)
$shouldInitDb && $suCmd postgres bash -c "$customEnv initdb --locale=$useLocale -D $dbPath --noclean" && printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" >> "$dbPath/pg_hba.conf"
! [ -d "$dbPath/stats" ] && $suCmd postgres bash -c "mkdir $dbPath/stats"

# need to make sure address can connect

! [ -f "$dbPath/pg_hba.conf" ] && printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" > "$dbPath/pg_hba.conf"

# LD_DEBUG=libs 
logFile=$([ "$(arg log)" = "" ] && echo "$BASE/postgres.log" || arg log)
$suCmd postgres bash -c "$customEnv pg_ctl start -o '-c config_file=$BASE/etc/postgresql/12/main/postgresql.conf' -D $dbPath" >> $logFile 2>> $logFile

# make database, user, password if needed

if $shouldInitDb || ! [ "$(arg database)" = "" ]; then
  dbName=$([ "$(arg database)" = "" ] && echo "postgres" || arg database)
  $suCmd postgres bash -c "$customEnv createdb $dbName"
fi

if $shouldInitDb || ! [ "$(arg username)" = "" ]; then
  dbUsername=$([ "$(arg username)" = "" ] && echo "username" || arg username)
  dbPassword=$([ "$(arg password)" = "" ] && echo "password" || arg password)
  $suCmd postgres bash -c "$customEnv psql -c \"create role $dbUsername with login password '$dbPassword'; alter user $dbUsername with SUPERUSER;\""
fi

function siginthandler() {
  $suCmd postgres bash -c "$customEnv pg_ctl stop -o '-c config_file=$BASE/etc/postgresql/12/main/postgresql.conf' -D $dbPath"
  exit
}
trap 'siginthandler' EXIT

tail -f $logFile
