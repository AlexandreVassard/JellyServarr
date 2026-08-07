#!/bin/bash
set -e

JELLYFIN_ENABLE_SCAN="${JELLYFIN_ENABLE_SCAN:-true}"
JELLYFIN_SCAN_DELAY="${JELLYFIN_SCAN_DELAY:-10}"
JELLYFIN_URL="${JELLYFIN_URL:-http://jellyfin:8096}"
JELLYFIN_TOKEN="${JELLYFIN_TOKEN:-}"

# Container-side paths, fixed by the volumes declared for this service in
# compose.yml. They are constants, not settings: changing one here without
# changing the matching volume silently breaks the sync.
WEBDAV_MOUNT_DIR=/mnt/webdav
MOVIES_DIR=/mnt/medias/movies
SERIES_DIR=/mnt/medias/series

WEBDAV_REFRESH_INTERVAL="${WEBDAV_REFRESH_INTERVAL:-60}"
WEBDAV_REFRESH_INITIAL_DELAY="${WEBDAV_REFRESH_INITIAL_DELAY:-15}"

say() {
    echo >&2 "$(date '+%Y-%m-%d %H:%M:%S') >> $*"
}

has_video_files() {
    find "$1" -maxdepth 3 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) -print -quit 2>/dev/null | grep -q .
}

is_video_file() {
    echo "$1" | grep -qiE "\.(mkv|mp4|avi|m4v|ts)$"
}

# Matches a movie year in various formats:
#   (1964)              - year in parens
#   (1964 something)    - year in parens followed by extra info
#   .1964.              - year between dots (scene naming)
#   " 1964 " / " 1964."- year surrounded by spaces or space+dot
MOVIE_YEAR_PATTERN='\([12][0-9]{3}\)|\([12][0-9]{3}[^0-9-]|\.[12][0-9]{3}\.| [12][0-9]{3} | [12][0-9]{3}\.'

classify_item() {
    local item="$1" search="$2"
    if echo "$search" | grep -qiE 'S[0-9]{2}E[0-9]{2}|[^a-zA-Z0-9]S[0-9]{2}[^0-9]|[Ss]aison[[:space:]]+[0-9]|[Ss]eason[[:space:]]+[0-9]'; then
        echo "series"
    elif echo "$(basename "$item")" | grep -qE "$MOVIE_YEAR_PATTERN"; then
        # A folder with a year in its name is a series if it contains multiple video files
        if [ -d "$item" ]; then
            local count
            count=$(find "$item" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) 2>/dev/null | wc -l)
            [ "$count" -gt 1 ] && echo "series" || echo "movie"
        else
            echo "movie"
        fi
    else
        echo "unknown"
    fi
}

# Extract show name from a season/episode folder/file name:
#   "Stranger Things (2016) S04 MULTi..."        -> "Stranger Things"
#   "Stranger.Things.S01.MULTI..."               -> "Stranger Things"
#   "Chapeau melon et bottes de cuir saison 2"   -> "Chapeau melon et bottes de cuir"
extract_show_name() {
    echo "$1" \
        | sed -E 's/[[:space:].]*[Ss]eason[[:space:]]+[0-9]+.*//' \
        | sed -E 's/[[:space:].]*[Ss]aison[[:space:]]+[0-9]+.*//' \
        | sed -E 's/[[:space:].]*[Ss][0-9]{2}([Ee][0-9]{2})?.*//' \
        | sed 's/\./ /g' \
        | sed -E 's/[[:space:]]*\([12][0-9]{3}\)[[:space:]]*//' \
        | sed -E 's/[[:space:]]+/ /g' \
        | sed -E 's/^[[:space:]]+|[[:space:]]+$//'
}

# Extract season number (as integer) from a name, or empty string if not found.
#   "Stranger.Things.S03.MULTI..."  -> "3"
#   "Saison 1"                      -> "1"
#   "Season 04"                     -> "4"
extract_season_number() {
    local name="$1" num
    num=$(echo "$name" | grep -oiE '(Season|Saison)[[:space:]]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -n "$num" ] && { printf '%d' "$((10#$num))"; return; }
    num=$(echo " $name " | grep -oiE '[^a-zA-Z]S[0-9]{2}' | grep -oE '[0-9]+' | head -1)
    [ -n "$num" ] && { printf '%d' "$((10#$num))"; return; }
    echo ""
}

VIDEO_FIND_ARGS="-maxdepth 2 -type f \( -iname *.mkv -o -iname *.mp4 -o -iname *.avi -o -iname *.m4v -o -iname *.ts \)"

# Link all video files from $1 into $2/Season N/ directories.
# $3: season number hint (from parent folder name); empty = detect from children/files.
link_series_videos() {
    local src="$1" show_dir="$2" season="$3"
    mkdir -p "$show_dir"

    if [ -n "$season" ]; then
        # Season known: all videos inside belong to this season
        local sdir="$show_dir/Season $season"
        mkdir -p "$sdir"
        find "$src" -maxdepth 2 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) 2>/dev/null \
        | while IFS= read -r video; do
            local vname
            vname="$(basename "$video")"
            [ -L "$sdir/$vname" ] || ln -s "$video" "$sdir/$vname"
        done
        return
    fi

    # No season hint: look for season subdirectories inside $src
    for child in "$src"/*/; do
        child="${child%/}"
        [ -d "$child" ] || continue
        local c_season
        c_season="$(extract_season_number "$(basename "$child")")"
        [ -z "$c_season" ] && continue
        local sdir="$show_dir/Season $c_season"
        mkdir -p "$sdir"
        find "$child" -maxdepth 2 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) 2>/dev/null \
        | while IFS= read -r video; do
            local vname
            vname="$(basename "$video")"
            [ -L "$sdir/$vname" ] || ln -s "$video" "$sdir/$vname"
        done
    done

    # Also handle video files placed directly inside the show folder (with S##E## in name)
    find "$src" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) 2>/dev/null \
    | while IFS= read -r video; do
        local vname v_season
        vname="$(basename "$video")"
        v_season="$(extract_season_number "$vname")"
        [ -z "$v_season" ] && continue
        local sdir="$show_dir/Season $v_season"
        mkdir -p "$sdir"
        [ -L "$sdir/$vname" ] || ln -s "$video" "$sdir/$vname"
    done
}

sync_symlinks() {
    say "Syncing library symlinks..."
    local webdav_root="${WEBDAV_MOUNT_DIR}"
    mkdir -p "$MOVIES_DIR" "$SERIES_DIR"

    # Movies: remove broken symlinks only
    find "$MOVIES_DIR" -maxdepth 1 -type l | while IFS= read -r link; do
        [ -e "$link" ] || rm -f "$link"
    done

    # Series: remove any symlinks pointing to directories (old approach) and broken ones,
    # then remove empty dirs. File symlinks (new approach) are left intact.
    find "$SERIES_DIR" -type l | while IFS= read -r link; do
        if ! [ -e "$link" ] || [ -d "$link" ]; then
            rm -f "$link"
        fi
    done
    find "$SERIES_DIR" -mindepth 1 -depth -type d -empty -delete 2>/dev/null

    for item in "$webdav_root"/*; do
        [ -e "$item" ] || continue
        local name
        name="$(basename "$item")"

        if [ -f "$item" ]; then
            is_video_file "$name" || continue
        elif [ -d "$item" ]; then
            has_video_files "$item" || continue
        else
            continue
        fi

        local search="$name"
        [ -d "$item" ] && search="$search $(ls "$item" 2>/dev/null | head -20 | tr '\n' ' ')"
        local kind
        kind="$(classify_item "$item" "$search")"

        if [ "$kind" = "movie" ]; then
            local link="$MOVIES_DIR/$name"
            [ -L "$link" ] || ln -s "$item" "$link"

        elif [ "$kind" = "unknown" ] && [ -d "$item" ]; then
            # Movie collection folder (e.g. "Mad Max Collection (1979-2015)/"):
            # the folder name has no clear year/series pattern but contains movie files.
            find "$item" -maxdepth 1 -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.m4v" -o -iname "*.ts" \) 2>/dev/null \
            | while IFS= read -r video; do
                local vname
                vname="$(basename "$video")"
                if echo "$vname" | grep -qE "$MOVIE_YEAR_PATTERN"; then
                    local link="$MOVIES_DIR/$vname"
                    [ -L "$link" ] || ln -s "$video" "$link"
                fi
            done

        elif [ "$kind" = "series" ]; then
            local show_name show_dir item_season
            show_name="$(extract_show_name "$name")"
            show_dir="$SERIES_DIR/$show_name"

            if [ -f "$item" ]; then
                # Individual episode file at WebDAV root
                item_season="$(extract_season_number "$name")"
                if [ -n "$item_season" ]; then
                    mkdir -p "$show_dir/Season $item_season"
                    local link="$show_dir/Season $item_season/$name"
                    [ -L "$link" ] || ln -s "$item" "$link"
                fi
            else
                # Directory: either a season pack (S01 in name) or a show folder
                item_season="$(extract_season_number "$name")"
                link_series_videos "$item" "$show_dir" "$item_season"
            fi
        fi
    done

    say "Symlink sync complete."
}

sleep "${WEBDAV_REFRESH_INITIAL_DELAY}"

sync_symlinks || say "Symlink sync failed"

say "Starting refresh loop..."

while wget -q -O /dev/null --post-data="" "http://rclone:5572/vfs/stats" 2>/dev/null; do
    say "Refreshing WebDAV cache..."
    wget -q -O /dev/null --post-data "recursive=true" "http://rclone:5572/vfs/refresh" \
        2>&1 || say "Jellyfin WebDAV refresh failed"
    sync_symlinks || say "Symlink sync failed"

    if [ "$JELLYFIN_ENABLE_SCAN" = true ]; then
        if [ -z "$JELLYFIN_TOKEN" ]; then
            say "Jellyfin scan is enabled but no JELLYFIN_TOKEN provided. Skipping Jellyfin scan."
        else
            say "Waiting ${JELLYFIN_SCAN_DELAY}s before Jellyfin scan..."
            sleep "${JELLYFIN_SCAN_DELAY}"

            say "Triggering Jellyfin library scan..."
            wget -q -O /dev/null \
                --header "X-Emby-Token: ${JELLYFIN_TOKEN}" \
                --post-data "" \
                "${JELLYFIN_URL}/Library/Refresh" \
                2>&1 || say "Failed to trigger Jellyfin library scan"
        fi
    else
        say "Jellyfin scan is disabled. Skipping..."
    fi

    say "Waiting ${WEBDAV_REFRESH_INTERVAL}s before next Jellyfin WebDAV refresh..."
    sleep "${WEBDAV_REFRESH_INTERVAL}"
done

say "rclone RC unreachable. Exiting."
exit 1
