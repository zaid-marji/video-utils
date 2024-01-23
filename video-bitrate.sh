#!/bin/bash

# Default values
default_bitrate_threshold=9200  # in kbps
default_percentage=2  # top 2%
default_file_size_threshold=600  # in MB

# Help message
help_message=$(cat << EOF
Usage: video-bitrate [OPTIONS] [DIRECTORY]
Find video files in a given directory based on their bitrate.

Options:
  -th [bitrate]    Set the bitrate threshold in kbps. Files with a bitrate above this value will be displayed. Default is $default_bitrate_threshold.
  -top [percent]   Display the top X percent of files based on bitrate. Default is $default_percentage.
  -size [size]     Set the minimum file size in MB. Files above this size will be displayed. Default is $default_file_size_threshold.
  -h, --help       Display this help message and exit.

If no options are provided, the script operates in the current directory and uses default values for options.
EOF
)

# Function to get the bitrate of a video file in kbps
get_bitrate() {
    bitrate=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$1" 2>&1)
    if [[ $? -ne 0 ]] || [[ ! $bitrate =~ ^[0-9]+$ ]]; then
        echo "Error processing file $1" >&2
        echo 0
    else
        echo $(($bitrate / 1000))
    fi
}

# Function to get the size of a video file
get_file_size() {
    stat --printf="%s" "$1"
}

# Function to find videos above a bitrate threshold and file size
find_above_threshold() {
    threshold_bitrate="$1"
    threshold_file_size=$(($2 * 1024 * 1024)) # Convert MB to bytes
    local -n _result=$3
    while IFS= read -r -d '' file; do
        file_size=$(get_file_size "$file")
        if [[ "$file_size" -ge "$threshold_file_size" ]]; then
            bitrate=$(get_bitrate "$file")
            if [[ "$bitrate" -ge "$threshold_bitrate" ]]; then
                relative_path="${file#$search_dir/}"
                _result["$relative_path"]=$bitrate:$file_size
            fi
        fi
    done < <(find "$search_dir" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) -print0)
}

# Function to find top X% bitrate videos with a file size filter
find_top_percentage() {
    percentage="$1"
    threshold_file_size=$(($2 * 1024 * 1024)) # Convert MB to bytes
    local -n _result=$3
    declare -A file_bitrates
    video_files=()

    # Collect video files
    while IFS= read -r -d '' file; do
        file_size=$(get_file_size "$file")
        if [[ "$file_size" -ge "$threshold_file_size" ]]; then
            video_files+=("$file")
        fi
    done < <(find "$search_dir" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) -print0)

    # Get bitrates of all files and store in an associative array
    for file in "${video_files[@]}"; do
        bitrate=$(get_bitrate "$file")
        file_bitrates["$file"]="$bitrate"
    done

    # Number of files to select
    local num_files=${#video_files[@]}
    local top_count=$((num_files * percentage / 100))
    [[ "$top_count" -eq 0 ]] && top_count=1

    # Sort files by bitrate and get the top X%
    IFS=$'\n' sorted_files=($(for file in "${!file_bitrates[@]}"; do echo "$file:${file_bitrates[$file]}"; done | sort -t : -k 2 -nr | head -n "$top_count"))

    for file in "${sorted_files[@]}"; do
        file_size=$(get_file_size "${file%:*}")
        relative_path="${file%:*}"
        relative_path="${relative_path#$search_dir/}"
        _result["$relative_path"]="${file_bitrates[${file%:*}]}:$file_size"
    done
}

# Parse arguments
bitrate_threshold=""
percentage=""
file_size_threshold=""
search_dir="$(pwd)"

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -th)
            bitrate_threshold="$2"
            shift # past argument
            shift # past value
            ;;
        -top)
            percentage="$2"
            shift # past argument
            shift # past value
            ;;
        -size)
            file_size_threshold="$2"
            shift # past argument
            shift # past value
            ;;
        -h|--help)
            echo "$help_message"
            exit 0
            ;;
        *)
            search_dir="$1" # Assume it's the directory path
            shift # past argument
            ;;
    esac
done

# Apply default values if neither argument is provided
if [[ -z $bitrate_threshold ]] && [[ -z $percentage ]] && [[ -z $file_size_threshold ]]; then
    bitrate_threshold=$default_bitrate_threshold
    percentage=$default_percentage
    file_size_threshold=$default_file_size_threshold
fi

# Ensure search_dir has a trailing slash for correct relative path calculation
search_dir="${search_dir%/}"

declare -A above_threshold
declare -A top_percentage
declare -A result

# Find files above threshold if specified
if [[ -n $bitrate_threshold ]] && [[ -n $file_size_threshold ]]; then
    find_above_threshold "$bitrate_threshold" "$file_size_threshold" above_threshold
elif [[ -n $bitrate_threshold ]]; then
    find_above_threshold "$bitrate_threshold" $default_file_size_threshold above_threshold
fi

# Find top percentage if specified
if [[ -n $percentage ]] && [[ -n $file_size_threshold ]]; then
    find_top_percentage "$percentage" "$file_size_threshold" top_percentage
elif [[ -n $percentage ]]; then
    find_top_percentage "$percentage" $default_file_size_threshold top_percentage
fi

# Combine results if both options were used, otherwise use what was found
if [[ -n $bitrate_threshold ]] && [[ -n $percentage ]]; then
    # Compound mode
    for file in "${!above_threshold[@]}"; do
        if [[ -n "${top_percentage[$file]}" ]]; then
            result["$file"]="${above_threshold[$file]}"
        fi
    done
else
    # Single mode
    if [[ -n $bitrate_threshold ]]; then
        for file in "${!above_threshold[@]}"; do
            result["$file"]="${above_threshold[$file]}"
        done
    fi
    if [[ -n $percentage ]]; then
        for file in "${!top_percentage[@]}"; do
            result["$file"]="${top_percentage[$file]}"
        done
    fi
fi

# Create an array to hold the result strings
result_strings=()
for filepath in "${!result[@]}"; do
    IFS=':' read -r bitrate filesize <<< "${result[$filepath]}"
    # Append each result string to the array
    result_strings+=("$bitrate $((filesize / 1024 / 1024)) $filepath")
done

# Sort the result strings array in descending order of bitrate and print
IFS=$'\n' sorted_results=($(sort -nr <<< "${result_strings[*]}"))
for res in "${sorted_results[@]}"; do
    # Split the result string into its components
    IFS=' ' read -r bitrate filesize filepath <<< "$res"
    echo "File: $filepath, Bitrate: $bitrate, Size: $filesize MB"
done
