#!/bin/bash

BASEDIR="/scratch/gpfs/EOST/changgoo/tigress_classic"
dir_pattern=${1:-*}

# enable nullglob so globs that don't match vanish instead of remaining literal
shopt -s nullglob

for path in $BASEDIR/$dir_pattern; do
    [ -d "$path" ] || continue
    DIR=$(basename "$path")
    mkdir -p "$path/movies"
    echo "Processing directory: $DIR"

    for KIND in cr_slices cr_snapshot_prj cr_snapshot snapshot; do
        pattern="$path/$KIND/*.png"
        outfile="$path/movies/${DIR}_${KIND}.mp4"

        # skip if no images
        if ! compgen -G "$pattern" > /dev/null; then
            echo "  no images for $KIND, skipping"
            continue
        fi

        # Quote the glob so ffmpeg handles it (do not let the shell expand it).
        ffmpeg -y -r 15 -f image2 -pattern_type glob -i "$pattern" \
            -r 15 -pix_fmt yuv420p -vcodec libx264 \
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -f mp4 "$outfile"

        echo "  Created movie: $outfile"
    done
done
