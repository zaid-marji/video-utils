#!/bin/bash

# Default values
default_bitrate_threshold=9200  # in kbps
default_percentage=2  # top 2%
default_file_size_threshold=600  # in MB
default_target_bitrate=5600  # in kbps
default_order_criteria="savings"  # Default ordering criteria
default_savings_threshold=234  # in MB

# Help message
help_message=$(cat << EOF
Usage: video-bitrate [OPTIONS] [DIRECTORY]
Find video files in a given directory based on their bitrate.

Options:
  -th [bitrate]      Set the bitrate threshold in kbps. Files with a bitrate above this value will be displayed. Default is $default_bitrate_threshold.
  -top [percent]     Display the top X percent of files based on bitrate or savings. Default is $default_percentage.
  -size [size]       Set the minimum file size in MB. Files above this size will be displayed. Default is $default_file_size_threshold.
  -target [bitrate]  Set the target bitrate in kbps for estimating savings. Default is $default_target_bitrate.
  -order [criteria]  Specify the order criteria ('bitrate' or 'savings'). Default is $default_order_criteria.
  -savings [savings] Set the minimum savings in MB. Files above this savings will be displayed. Default is $default_savings_threshold.
  -h, --help         Display this help message and exit.
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

# Function to get the size of a video file in bytes
get_file_size() {
    stat --printf="%s" "$1"
}

# Function to estimate storage saving if converted to target bitrate
calculate_savings() {
    local current_bitrate=$1
    local file_size=$2  # size in bytes
    local target_bitrate=$3
    if [[ $current_bitrate -eq 0 ]]; then
        echo 0
    else
        echo $(( (current_bitrate - target_bitrate) * file_size / current_bitrate / 1024 / 1024 ))  # Convert to MB
    fi
}

# Function to find videos above a bitrate threshold and file size
find_above_threshold() {
    local threshold_bitrate="$1"
    local threshold_file_size=$(($2 * 1024 * 1024))  # Convert MB to bytes
    local savings_threshold="$3"  # Savings threshold in MB
    local -n _result=$4
    while IFS= read -r -d '' file; do
        file_size=$(get_file_size "$file")
        if [[ "$file_size" -ge "$threshold_file_size" ]]; then
            bitrate=$(get_bitrate "$file")
            if [[ "$bitrate" -ge "$threshold_bitrate" ]] && [[ $(calculate_savings "$bitrate" "$file_size" "$default_target_bitrate") -ge "$savings_threshold" ]]; then
                relative_path="${file#$search_dir/}"
                _result["$relative_path"]=$bitrate:$file_size:$(calculate_savings "$bitrate" "$file_size" "$default_target_bitrate")
            fi
        fi
    done < <(find "$search_dir" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) -print0)
}

# Function to find top X% bitrate videos with a file size filter
find_top_percentage() {
    local percentage="$1"
    local threshold_file_size=$(($2 * 1024 * 1024))  # Convert MB to bytes
    local threshold_bitrate="$3"  # Include threshold bitrate checking
    local savings_threshold="$4"  # Include savings threshold
    local -n _result=$5
    declare -A file_data
    video_files=()  # Reset array to ensure clean state

    # Collect video files that meet the file size threshold
    while IFS= read -r -d '' file; do
        file_size=$(get_file_size "$file")
        if [[ "$file_size" -ge "$threshold_file_size" ]]; then
            bitrate=$(get_bitrate "$file")
            savings=$(calculate_savings "$bitrate" "$file_size" "$default_target_bitrate")
            file_data["$file"]="$bitrate|$file_size|$savings"
            video_files+=("$file")  # Storing entire file path
        fi
    done < <(find "$search_dir" -type f \( -name "*.mp4" -o -name "*.mkv" -o -name "*.avi" -o -name "*.mov" \) -print0)

    local total_file_count=${#video_files[@]}
    local top_count=$(((total_file_count * percentage + 50) / 100))  # Calculate 2% of files meeting the file size threshold
    top_count=${top_count:-1}  # Ensure at least one file is shown

    # Apply filters for bitrate and savings and sort the files
    sorted_files=()
    for file in "${video_files[@]}"; do
        IFS='|' read -r bitrate file_size_bytes savings <<< "${file_data["$file"]}"
        if [[ "$bitrate" -ge "$threshold_bitrate" ]] && [[ "$savings" -ge "$savings_threshold" ]]; then
            sorted_files+=("$file|$bitrate|$file_size_bytes|$savings")
        fi
    done

    # Sort by savings or bitrate based on order_criteria
    if [[ "$order_criteria" == "savings" ]]; then
        IFS=$'\n' sorted_files=($(sort -t '|' -k4 -nr <<< "${sorted_files[*]}"))
    else
        IFS=$'\n' sorted_files=($(sort -t '|' -k2 -nr <<< "${sorted_files[*]}"))
    fi

    # Output file details
    for entry in "${sorted_files[@]:0:$top_count}"; do
        IFS='|' read -r file bitrate file_size_bytes savings <<< "$entry"
        local file_size_mb=$((file_size_bytes / 1024 / 1024))  # Convert bytes to MB
        local relative_path="${file#$search_dir/}"  # Extract relative path
        echo "File: $relative_path, Bitrate: $bitrate kbps, Size: $file_size_mb MB, Savings: $savings MB"
    done
}

# Parse arguments
bitrate_threshold=""
percentage=""
file_size_threshold=""
target_bitrate=""
order_criteria=""
savings_threshold=""
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
        -target)
            target_bitrate="$2"
            shift # past argument
            shift # past value
            ;;
        -order)
            order_criteria="$2"
            shift # past argument
            shift # past value
            ;;
        -savings)
            savings_threshold="$2"
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

# Apply default values if options are not provided
[[ -z $bitrate_threshold ]] && bitrate_threshold=$default_bitrate_threshold
[[ -z $percentage ]] && percentage=$default_percentage
[[ -z $file_size_threshold ]] && file_size_threshold=$default_file_size_threshold
[[ -z $target_bitrate ]] && target_bitrate=$default_target_bitrate
[[ -z $order_criteria ]] && order_criteria=$default_order_criteria
[[ -z $savings_threshold ]] && savings_threshold=$default_savings_threshold

# Ensure search_dir has a trailing slash for correct relative path calculation
search_dir="${search_dir%/}"

declare -A above_threshold
declare -A top_percentage
declare -A result

# Find files above threshold if specified
if [[ -n $bitrate_threshold ]] && [[ -n $file_size_threshold ]] && [[ -n $savings_threshold ]]; then
    find_above_threshold "$bitrate_threshold" "$file_size_threshold" "$savings_threshold" above_threshold
fi

# Find top percentage if specified
if [[ -n $percentage ]] && [[ -n $file_size_threshold ]] && [[ -n $savings_threshold ]]; then
    find_top_percentage "$percentage" "$file_size_threshold" "$bitrate_threshold" "$savings_threshold" top_percentage
fi

# Combine results if both options were used, otherwise use what was found
if [[ -n $bitrate_threshold ]] && [[ -n $percentage ]]; then
    # Compound mode
    for file in "${!above_threshold[@]}"; do
        if [[ -n "${top_percentage[$file]}" ]]; then
            result["$file"]="${top_percentage[$file]}"
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
    IFS=':' read -r bitrate filesize savings <<< "${result[$filepath]}"
    # Append each result string to the array
    result_strings+=("$bitrate $((filesize / 1024 / 1024)) $savings $filepath")
done

# Sort the result strings array based on the order criteria
if [[ "$order_criteria" == "savings" ]]; then
    IFS=$'\n' sorted_results=($(sort -k 3 -nr <<< "${result_strings[*]}"))
else
    IFS=$'\n' sorted_results=($(sort -k 1 -nr <<< "${result_strings[*]}"))
fi

# Print results
for res in "${sorted_results[@]}"; do
    # Split the result string into its components
    IFS=' ' read -r bitrate filesize savings filepath <<< "$res"
    echo "File: $filepath, Bitrate: $bitrate kbps, Size: $filesize MB, Savings: $savings MB"
done
