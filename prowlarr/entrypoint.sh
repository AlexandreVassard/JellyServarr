#!/bin/bash
set -e

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

mkdir -p /config/Definitions/Custom

for src_file in /default/Definitions/Custom/*; do
    filename=$(basename "$src_file")
    dest_file="/config/Definitions/Custom/$filename"

    if [ ! -e "$dest_file" ]; then
        say "Copying $filename to config folder"
        cp -a "$src_file" "$dest_file"
    else
        say "$filename already exists. Skipping."
    fi
done

exec /init
