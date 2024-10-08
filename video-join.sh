#!/bin/bash

# Function to display usage instructions
show_help() {
    echo "Usage: video-join <video files> [-o <output file>]"
    echo "       video-join -h|--help"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message and exit."
    echo "  -o              Specify output file name. Default is 'joined_video.<ext>'."
    echo
    echo "Arguments:"
    echo "  <video files>   Paths to input video files to join (at least two)."
    echo "                  Files can have different extensions but must be compatible formats."
}

# Function to display an error message and exit
error_exit() {
    echo "Error: $1" 1>&2
    exit 1
}

# Check if help flag is provided or insufficient arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
elif [ "$#" -lt 2 ]; then
    show_help
    error_exit "At least two video files must be provided."
fi

# Initialize variables
OUTPUT_VIDEO=""
INPUT_VIDEOS=()

# Process arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o )
            OUTPUT_VIDEO="$2"
            shift 2
            ;;
        -* )
            error_exit "Invalid option: $1"
            ;;
        * )
            INPUT_VIDEOS+=("$1")
            shift
            ;;
    esac
done

# Check that at least two video files are provided
if [ "${#INPUT_VIDEOS[@]}" -lt 2 ]; then
    error_exit "At least two video files must be provided."
fi

# Check if ffmpeg is installed
command -v ffmpeg >/dev/null 2>&1 || error_exit "ffmpeg is not installed."

# Check if input files exist
for video in "${INPUT_VIDEOS[@]}"; do
    [ -f "$video" ] || error_exit "Input file '$video' does not exist."
done

# Determine default output file extension based on the first input video
if [ -z "$OUTPUT_VIDEO" ]; then
    FIRST_EXT="${INPUT_VIDEOS[0]##*.}"
    OUTPUT_VIDEO="joined_video.$FIRST_EXT"
fi

# Prepare a temporary file list for ffmpeg
TEMP_LIST=$(mktemp)
trap 'rm -f "$TEMP_LIST"' EXIT

for video in "${INPUT_VIDEOS[@]}"; do
    # Use absolute paths and escape special characters
    ABSOLUTE_PATH=$(realpath "$video")
    # Escape backslashes and single quotes
    ESCAPED_PATH=${ABSOLUTE_PATH//\\/\\\\}
    ESCAPED_PATH=${ESCAPED_PATH//\'/\'\\\'\'}
    echo "file '$ESCAPED_PATH'" >> "$TEMP_LIST"
done

# Check if output file already exists
[ -f "$OUTPUT_VIDEO" ] && error_exit "Output file '$OUTPUT_VIDEO' already exists. Please remove it or specify a different name."

# Concatenate videos using ffmpeg without re-encoding
echo "Joining videos..."

FFMPEG_CMD="ffmpeg -f concat -safe 0 -i \"$TEMP_LIST\" -c copy \"$OUTPUT_VIDEO\""

# Execute the command
echo "Executing command: $FFMPEG_CMD"
eval $FFMPEG_CMD || error_exit "Failed to join videos. Ensure all videos have compatible formats and codecs."

echo "Videos have been successfully joined into '$OUTPUT_VIDEO'."
