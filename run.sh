#!/bin/bash

set -x

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

# we arent allowed to run postgres as root, so if we're root make a new user

userRunningAs=$([ "$(whoami)" = "root" ] && echo "postgres" || echo "$(whoami)")
if [ "$userRunningAs" = "postgres" ] && ! id -u "postgres" >/dev/null 2>&1; then
  mkdir -p /home/postgres
  useradd -d /home/postgres postgres || sudo useradd -d /home/postgres postgres
  chown "$userRunningAs" /home/postgres || sudo chown "$userRunningAs" /home/postgres
fi

# we have to turn off a bunch of settings by default

CONFIG_FILE=$(mktemp /tmp/postgresql-appImage-XXXX)
cat $BASE/etc/postgresql/12/main/postgresql.conf > $CONFIG_FILE

CONFIG_SWAP_FILE=$(mktemp /tmp/postgresql-appImage-swap-XXXX)
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

echo "listen_addresses = '*'" >> $CONFIG_FILE
echo "stats_temp_directory = 'stats'" >> $CONFIG_FILE

mkdir -p /var/run/postgresql/
touch /var/run/postgresql/.s.PGSQL.5432
chown -R "$userRunningAs" /var/run/postgresql/ || sudo chown -R "$userRunningAs" /var/run/postgresql/

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

# resolve the database path and init the db there if the folder is empty

TEMP_DB_PATH=$(mktemp -d /tmp/postgresql-temp-db-XXXX)
dbPath=$([ "$(arg path)" = "" ] && echo "$TEMP_DB_PATH" || arg path)
! [ -d "$dbPath" ] && mkdir -p $dbPath
chown -R "$userRunningAs" $dbPath || sudo chown -R "$userRunningAs" $dbPath
rm -f $dbPath/.DS_Store
shouldInitDb=$([ -z "$(ls -A $dbPath)" ] && echo true || echo false)
$shouldInitDb && $suCmd "$userRunningAs" bash -c "$customEnv initdb --locale=$useLocale -D $dbPath --noclean" && printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" >> "$dbPath/pg_hba.conf"
! [ -d "$dbPath/stats" ] && $suCmd postgres bash -c "mkdir $dbPath/stats"

# need to make sure address can connect

! [ -f "$dbPath/pg_hba.conf" ] && printf "host all all 0.0.0.0/0 md5\nlocal all all trust\n" > "$dbPath/pg_hba.conf"

# Resolve the log file

TEMP_LOG_PATH=$(mktemp /tmp/postgresql-logs-XXXX)
touch $TEMP_LOG_PATH
chown "$userRunningAs" $TEMP_LOG_PATH || sudo chown "$userRunningAs" $TEMP_LOG_PATH
logFile=$([ "$(arg log)" = "" ] && echo "$TEMP_LOG_PATH" || arg log)

# start! LD_DEBUG=libs

$suCmd $userRunningAs bash -c "$customEnv pg_ctl start -o '-c config_file=$CONFIG_FILE' -D $dbPath -l $logFile"

# make database, user, password if needed

if $shouldInitDb || ! [ "$(arg database)" = "" ]; then
  dbName=$([ "$(arg database)" = "" ] && echo "postgres" || arg database)
  $suCmd $userRunningAs bash -c "$customEnv createdb $dbName"
fi

if $shouldInitDb || ! [ "$(arg username)" = "" ]; then
  dbUsername=$([ "$(arg username)" = "" ] && echo "username" || arg username)
  dbPassword=$([ "$(arg password)" = "" ] && echo "password" || arg password)
  $suCmd "$userRunningAs" bash -c "$customEnv psql -c \"create role $dbUsername with login password '$dbPassword'; alter user $dbUsername with SUPERUSER;\""
fi

function siginthandler() {
  $suCmd "$userRunningAs" bash -c "$customEnv pg_ctl stop -o '-c config_file=$CONFIG_FILE' -D $dbPath"
  rm -rf $CONFIG_FILE $TEMP_DB_PATH $TEMP_LOG_PATH
  exit
}
trap 'siginthandler' EXIT

tail -f $logFile
