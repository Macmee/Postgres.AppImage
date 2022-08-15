# What

This repo offers an AppImage for Postgresql, psql and other pg utilities.

You can download the AppImage from the dist/ folder in this repo.

# Why?

I wanted a portable & quick way to run a postgres server as well as utility binaries such as `psql`, `pg_dump`.

Although it's fairly trivial to just run postgres via docker, docker isn't always available everywhere (for example within a docker container itself without DnD).

This project makes it incredibly simple to run postgres as a singular binary.

# Examples

(note: swap `aarch64` for `x86_64` if you're on an intel/amd machine)

* running `./Postgres-12-aarch64.AppImage` on its own will run a postgres server with default parameters. A username of `username` password of `password` and default database `postgres`.
* running `./Postgres-12-aarch64.AppImage --username bob --password abc123 --database myproject --path $HOME/mydbdata` will run a database with the provided username, password and database name, and it will store that database in your home folder in the `mydbdata` folder.

You can also pass the `--locale C.UTF-8` option to change locales which might be useful for other languages.

# Utilities

The AppImage also comes with every utility binary that comes with postgres, such as `psql`, `initdb`, `vacuumdb` and so on. For example:

`./Postgres-12-aarch64.AppImage psql "postgresql://username:password@localhost:5431/postgres"`

Will run a postgres shell.

# Building From Source

I suggest doing this from within a docker container i.e. `docker run --rm -v $(pwd):/data -it debian:buster /bin/bash` otherwise it will install postgres on your local machine, and also because it's ideal to build AppImages on older distros such as Debian Buster so that modules like glibc are forward compatible.

Once up just run `/data/build.sh` and the build script will install postgres and build the AppImage. Artifacts are produced in the `out` folder and the generated AppImage in the `dist` folder.

# Other Versions of Postgresql

Right now this is only setup to build Postgres version 12, but in the future I plan on adding support for other versions too. If you want to take a shot at it, search this repo for references to 12 in `build.sh` and `run.sh`.