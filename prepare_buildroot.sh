#!/bin/bash

# removes directories in the buildroot folder which should be overriden
# by directories in the br_external directory

# always prepares the buildroot in the directory below this script
# according to the br_external directory

cd $(dirname "${BASH_SOURCE[0]}")

pushd .
cd buildroot || { printf 'Error: Could not cd to buildroot\n' >&2; exit 1; }
test -z "$(git status  --porcelain)" || git checkout --force
test $? -eq 0 || { printf 'Error: reset buildroot\n' >&2; exit 1; }
popd

for directory in $(find br_external -name .override -printf %h | sed 's/^br_external/buildroot/' ) ; do
    rm -rf "$directory"
done
