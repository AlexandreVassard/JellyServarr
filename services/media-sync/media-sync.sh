#!/bin/bash
set -e

JELLYFIN_ENABLE_SCAN="${JELLYFIN_ENABLE_SCAN:-true}"
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

# The single list of recognised video extensions. Everything below derives
# from it, so adding a format is a one-line change.
VIDEO_EXTENSIONS=(mkv mp4 avi m4v ts)

# find(1) expression matching any of them: ( -iname *.mkv -o -iname *.mp4 ... )
VIDEO_FIND_EXPR=("(")
for ext in "${VIDEO_EXTENSIONS[@]}"; do
    [ "${#VIDEO_FIND_EXPR[@]}" -gt 1 ] && VIDEO_FIND_EXPR+=("-o")
    VIDEO_FIND_EXPR+=(-iname "*.$ext")
done
VIDEO_FIND_EXPR+=(")")

VIDEO_EXTENSION_RE="$(IFS='|'; echo "${VIDEO_EXTENSIONS[*]}")"

# List video files under $1, at most $2 levels deep.
find_videos() {
    find "$1" -maxdepth "$2" -type f "${VIDEO_FIND_EXPR[@]}" 2>/dev/null
}

has_video_files() {
    [ -n "$(find_videos "$1" 3 | head -1)" ]
}

is_video_file() {
    echo "$1" | grep -qiE "\.($VIDEO_EXTENSION_RE)$"
}

# sync_symlinks runs its loops inside pipelines, so a counter variable would
# be lost with the subshell. A marker file survives instead, and tells the
# main loop whether the library actually changed and a scan is warranted.
CHANGES_MARKER=/tmp/media-sync-changed

mark_changed() { : > "$CHANGES_MARKER"; }
changes_pending() { [ -f "$CHANGES_MARKER" ]; }
clear_changes() { rm -f "$CHANGES_MARKER"; }

# Create a symlink and record the change. $1: target, $2: link path.
link_video() {
    [ -L "$2" ] && return 0
    ln -s "$1" "$2" && mark_changed
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
            count=$(find_videos "$item" 1 | wc -l)
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

# Link every video found under $1 into $2/Season $3/.
link_season_videos() {
    local src="$1" show_dir="$2" season="$3" depth="${4:-2}"
    local sdir="$show_dir/Season $season"
    mkdir -p "$sdir"
    find_videos "$src" "$depth" | while IFS= read -r video; do
        link_video "$video" "$sdir/$(basename "$video")"
    done
}

# Link all video files from $1 into $2/Season N/ directories.
# $3: season number hint (from parent folder name); empty = detect from children/files.
link_series_videos() {
    local src="$1" show_dir="$2" season="$3"
    mkdir -p "$show_dir"

    if [ -n "$season" ]; then
        # Season known: all videos inside belong to this season
        link_season_videos "$src" "$show_dir" "$season"
        return
    fi

    # No season hint: look for season subdirectories inside $src
    for child in "$src"/*/; do
        child="${child%/}"
        [ -d "$child" ] || continue
        local c_season
        c_season="$(extract_season_number "$(basename "$child")")"
        [ -z "$c_season" ] && continue
        link_season_videos "$child" "$show_dir" "$c_season"
    done

    # Also handle video files placed directly inside the show folder (with S##E## in name)
    find_videos "$src" 1 | while IFS= read -r video; do
        local vname v_season
        vname="$(basename "$video")"
        v_season="$(extract_season_number "$vname")"
        [ -z "$v_season" ] && continue
        mkdir -p "$show_dir/Season $v_season"
        link_video "$video" "$show_dir/Season $v_season/$vname"
    done
}

sync_symlinks() {
    say "Syncing library symlinks..."
    local webdav_root="${WEBDAV_MOUNT_DIR}"
    mkdir -p "$MOVIES_DIR" "$SERIES_DIR"

    # Movies: remove broken symlinks only
    find "$MOVIES_DIR" -maxdepth 1 -type l | while IFS= read -r link; do
        [ -e "$link" ] || { rm -f "$link" && mark_changed; }
    done

    # Series: remove any symlinks pointing to directories (old approach) and broken ones,
    # then remove empty dirs. File symlinks (new approach) are left intact.
    find "$SERIES_DIR" -type l | while IFS= read -r link; do
        if ! [ -e "$link" ] || [ -d "$link" ]; then
            rm -f "$link" && mark_changed
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
            link_video "$item" "$MOVIES_DIR/$name"

        elif [ "$kind" = "unknown" ] && [ -d "$item" ]; then
            # Movie collection folder (e.g. "Mad Max Collection (1979-2015)/"):
            # the folder name has no clear year/series pattern but contains movie files.
            find_videos "$item" 1 | while IFS= read -r video; do
                local vname
                vname="$(basename "$video")"
                if echo "$vname" | grep -qE "$MOVIE_YEAR_PATTERN"; then
                    link_video "$video" "$MOVIES_DIR/$vname"
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
                    link_video "$item" "$show_dir/Season $item_season/$name"
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

# Ask Jellyfin for a full library scan, but only when sync_symlinks actually
# touched the library. A scan is expensive over the WebDAV mount, and running
# one every cycle regardless of changes kept Jellyfin busy for nothing.
scan_jellyfin_if_needed() {
    if [ "$JELLYFIN_ENABLE_SCAN" != true ]; then
        say "Jellyfin scan is disabled. Skipping..."
        return
    fi
    if ! changes_pending; then
        say "Library unchanged. Skipping Jellyfin scan."
        return
    fi
    if [ -z "$JELLYFIN_TOKEN" ]; then
        say "Jellyfin scan is enabled but no JELLYFIN_TOKEN provided. Skipping Jellyfin scan."
        return
    fi

    say "Library changed. Triggering Jellyfin library scan..."
    if wget -q -O /dev/null \
        --header "X-Emby-Token: ${JELLYFIN_TOKEN}" \
        --post-data "" \
        "${JELLYFIN_URL}/Library/Refresh" 2>&1
    then
        clear_changes
    else
        # Keep the marker so the next cycle retries the scan.
        say "Failed to trigger Jellyfin library scan"
    fi
}

sleep "${WEBDAV_REFRESH_INITIAL_DELAY}"

clear_changes
sync_symlinks || say "Symlink sync failed"

say "Starting refresh loop..."

while wget -q -O /dev/null --post-data="" "http://rclone:5572/vfs/stats" 2>/dev/null; do
    say "Refreshing WebDAV cache..."
    wget -q -O /dev/null --post-data "recursive=true" "http://rclone:5572/vfs/refresh" \
        2>&1 || say "Jellyfin WebDAV refresh failed"
    sync_symlinks || say "Symlink sync failed"

    scan_jellyfin_if_needed

    say "Waiting ${WEBDAV_REFRESH_INTERVAL}s before next Jellyfin WebDAV refresh..."
    sleep "${WEBDAV_REFRESH_INTERVAL}"
done

say "rclone RC unreachable. Exiting."
exit 1
