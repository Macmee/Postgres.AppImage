#!/bin/bash

apt -y install gnupg2 wget lsb-release
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | tee  /etc/apt/sources.list.d/pgdg.list
apt update
apt -y install postgresql-13 postgresql-client-13 postgis postgresql-13-postgis-3 postgresql-13-postgis-3-scripts