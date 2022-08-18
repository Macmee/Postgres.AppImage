#!/bin/bash

#set -x

allArgs="$@" # cute little helper to read "--name value" arguments!
arg() { echo $allArgs | grep "\-\-$1 " | grep -Ev "\-\-$1 \-\-[a-z]" | sed -e "s/^.*\-\-$1 \([^ ^$]*\).*$/\1/" ; }

VERSION="$(cat $APPDIR/VERSION)"
BASE="$APPDIR/root"
BIN="$BASE/usr/lib/postgresql/$VERSION/bin"
cd $BIN

export PATH="$PATH:$BIN"
export LD_LIBRARY_PATH="$BASE/usr/lib"

# some distros (fedora docker image) dont have su so we need to use sudo

suCmd="su"
(! command -v su > /dev/null || [ "$(uname)" = 'darwin' ]) && suCmd="sudo -u"

# if the user specified a specific binary to run, lets do that and bail

if ! [ "$1" = "" ] && [ -f "$BASE/usr/lib/postgresql/$VERSION/bin/$1" ]; then
  args="${@:2}"
  eval $BIN/$1 $args
  exit $?
fi

# we arent allowed to run postgres as root, so if we're root make a new user

userRunningAs=$([ "$(whoami)" = "root" ] && echo "postgres" || echo "$(whoami)")
if [ "$userRunningAs" = "postgres" ] && ! id -u "postgres" >/dev/null 2>&1; then
  mkdir -p /home/postgres
  useradd -d /home/postgres postgres || sudo useradd -d /home/postgres postgres
  chown "$userRunningAs" /home/postgres || sudo chown "$userRunningAs" /home/postgres
fi

runPrefix=$([ "$(whoami)" = "root" ] && echo "$suCmd $userRunningAs bash -c " || echo "bash -c ")

# we have to turn off a bunch of settings by default

CONFIG_FILE=$($runPrefix "mktemp /tmp/postgresql-appImage-XXXX")
cat $BASE/etc/postgresql/$VERSION/main/postgresql.conf > $CONFIG_FILE

CONFIG_SWAP_FILE=$($runPrefix "mktemp /tmp/postgresql-appImage-swap-XXXX")
function deleteFromConfigFile() {
  cat $CONFIG_FILE | grep -v "$1" > $CONFIG_SWAP_FILE
  cat $CONFIG_SWAP_FILE > $CONFIG_FILE
  rm -f $CONFIG_SWAP_FILE
}
deleteFromConfigFile data_directory
deleteFromConfigFile ssl_cert_file
deleteFromConfigFile ssl_key_file
deleteFromConfigFile "ssl = on"
deleteFromConfigFile listen_addresses
deleteFromConfigFile stats_temp_directory
deleteFromConfigFile hba_file
deleteFromConfigFile include_dir
deleteFromConfigFile unix_socket_directories
deleteFromConfigFile external_pid_file
deleteFromConfigFile ident_file

echo "listen_addresses = '*'" >> $CONFIG_FILE
echo "stats_temp_directory = 'stats'" >> $CONFIG_FILE

# if the caller provided another config file, include it

! [ "$(arg configFile)" = "" ] && echo "include = '$(arg configFile)'" >> $CONFIG_FILE

# determine socket path

socketDir=$([ "$(arg socketDir)" = "" ] && echo "/tmp" || arg socketDir)
echo "unix_socket_directories = '$socketDir'" >> $CONFIG_FILE

# determine port

port=$([ "$(arg port)" = "" ] && echo "5432" || arg port)

# determine where to write the pidfile to

pidFile=$([ "$(arg pidFile)" = "" ] && $runPrefix "mktemp /tmp/postgresql-pidfile-XXXX" || arg pidFile)
echo "external_pid_file = '$pidFile'" >> $CONFIG_FILE

# respect given locale and fallback to en_US.utf8 if needed

useLocale=$([ "$(arg locale)" = "" ] && echo "C.UTF-8" || arg locale)
(! locale -a | sed -e 's/-//g' | grep -i C.UTF8) && useLocale="en_US.utf8"

deleteFromConfigFile lc_messages
deleteFromConfigFile lc_monetary
deleteFromConfigFile lc_numeric
deleteFromConfigFile lc_time
echo "lc_messages = '$useLocale'" >> $CONFIG_FILE
echo "lc_monetary = '$useLocale'" >> $CONFIG_FILE
echo "lc_numeric = '$useLocale'" >> $CONFIG_FILE
echo "lc_time = '$useLocale'" >> $CONFIG_FILE
chown "$userRunningAs" $CONFIG_FILE || sudo chown "$userRunningAs" $CONFIG_FILE

# resolve the database path and init the db there if the folder is empty. noclean because initdb can segfault quite
# easily unfortunately (probably my fault somehow) but it fails so late that it still works!

TEMP_DB_PATH=$($runPrefix "mktemp -d /tmp/postgresql-temp-db-XXXX")
dbPath=$([ "$(arg dataDir)" = "" ] && echo "$TEMP_DB_PATH" || arg dataDir)
! [ -d "$dbPath" ] && mkdir -p $dbPath
chown -R "$userRunningAs" $dbPath || sudo chown -R "$userRunningAs" $dbPath
rm -f $dbPath/.DS_Store
[ -z "$(ls -A $dbPath)" ] && $runPrefix "$BIN/pg_ctl -D $dbPath -p $BIN/initdb initdb -o '--locale=$useLocale --noclean'"
! [ -d "$dbPath/stats" ] && $runPrefix "mkdir $dbPath/stats"

# deal with the hba file which is what determines who can connect from what ip, type of auth etc

if [ "$(arg hbaFile)" = "" ]; then
  printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" >> "$dbPath/pg_hba.conf" # default all local users no pw needed, remote users need pw
  echo "hba_file = '$dbPath/pg_hba.conf'" >> $CONFIG_FILE
else
  echo "hba_file = '$(arg hbaFile)'" >> $CONFIG_FILE
fi

# need to make sure address can connect

! [ -f "$dbPath/pg_hba.conf" ] && (printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" > "$dbPath/pg_hba.conf")

# Resolve the log file

TEMP_LOG_PATH=$($runPrefix "mktemp /tmp/postgresql-logs-XXXX")
touch $TEMP_LOG_PATH
chown "$userRunningAs" $TEMP_LOG_PATH || sudo chown "$userRunningAs" $TEMP_LOG_PATH
logFile=$([ "$(arg logFile)" = "" ] && echo "$TEMP_LOG_PATH" || arg logFile)

# start! LD_DEBUG=libs
$runPrefix "$BIN/pg_ctl -p $BIN/postgres -o '-p $port -c config_file=$CONFIG_FILE' -D $dbPath -l $logFile start"

# make database, user, password if needed

if $shouldInitDb || ! [ "$(arg database)" = "" ]; then
  dbName=$([ "$(arg database)" = "" ] && echo "$userRunningAs" || arg database)
  $runPrefix "$BIN/createdb $dbName -h $socketDir -p $port"
fi

if $shouldInitDb || ! [ "$(arg username)" = "" ]; then
  dbUsername=$([ "$(arg username)" = "" ] && echo "username" || arg username)
  dbPassword=$([ "$(arg password)" = "" ] && echo "password" || arg password)
  $runPrefix "$BIN/psql -h $socketDir -p $port -c \"create role $dbUsername with login password '$dbPassword'; alter user $dbUsername with SUPERUSER;\""
fi

function siginthandler() {
  $runPrefix "$BIN/pg_ctl -p $BIN/postgres -o '-p $port -c config_file=$CONFIG_FILE' -D $dbPath -l $logFile stop"
  rm -rf $CONFIG_FILE $TEMP_DB_PATH $TEMP_LOG_PATH
  exit
}
trap 'siginthandler' EXIT

tail -f $logFile
