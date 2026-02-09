#!/bin/bash

# Default settings for VBR with an average bitrate of 5600 Kb/s
DEFAULT_CRF=18
DEFAULT_RATE="5600k"
DEFAULT_BUFSIZE="56000k"

# Function to display usage instructions
show_help() {
    echo "Usage: video-compress <video file> [-s <target size in MB> | -b <target bitrate in Kb/s> | -c <codec> | -m <mode> | -r <rate mode> | -height <height> | -width <width> | --cpu-only]"
    echo "       video-compress -h|--help"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message and exit."
    echo "  -s              Specify target size in MB."
    echo "  -b              Specify target bitrate in Kb/s."
    echo "  -c              Specify codec to use (Options: libx264 (h264), libx265 (hevc), libsvtav1 (av1))."
    echo "                  If omitted, defaults to the same codec as the input or libx265 if codec is not supported."
    echo "                  Automatically upgrades to GPU-accelerated codec if available."
    echo "  -m              Specify encoding mode (cbr or vbr). Default is vbr."
    echo "  -r              Specify rate mode (average or maxrate). Default is average."
    echo "  -height         Specify the height of the output video. Width is adjusted to maintain aspect ratio."
    echo "  -width          Specify the width of the output video. Height is adjusted to maintain aspect ratio unless height is also specified."
    echo "  --cpu-only      Disable GPU acceleration and use CPU for encoding."
    echo
    echo "Arguments:"
    echo "  <video file>    Path to the input video file."
}

# Function to display an error message and exit
error_exit() {
    echo "Error: $1" 1>&2
    exit 1
}

# Check if help flag is provided
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Check if at least one argument is provided
if [ "$#" -lt 1 ]; then
    show_help
    error_exit "No arguments provided."
fi

# Assign command line arguments to variables
INPUT_VIDEO="$1"
shift

# Initialize variables
MODE=""
VALUE=""
USER_SPECIFIED_CODEC=""
CPU_ONLY=false
ENCODING_MODE="vbr"  # Default to VBR
RATE_MODE="average"  # Default to average rate mode
SPECIFIED_HEIGHT=""
SPECIFIED_WIDTH=""
HEIGHT_OR_WIDTH_SPECIFIED=false

# Process additional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s )
      MODE="size"
      VALUE="$2"
      shift 2
      ;;
    -b )
      MODE="bitrate"
      VALUE="$2"
      shift 2
      ;;
    -c )
      USER_SPECIFIED_CODEC="$2"
      shift 2
      ;;
    -m )
      ENCODING_MODE="$2"
      shift 2
      ;;
    -r )
      RATE_MODE="$2"
      shift 2
      ;;
    -height )
      SPECIFIED_HEIGHT="$2"
      HEIGHT_OR_WIDTH_SPECIFIED=true
      shift 2
      ;;
    -width )
      SPECIFIED_WIDTH="$2"
      HEIGHT_OR_WIDTH_SPECIFIED=true
      shift 2
      ;;
    --cpu-only )
      CPU_ONLY=true
      shift
      ;;
    * )
      error_exit "Invalid option: $1"
      ;;
  esac
done

# Check for Nvidia GPU
NVIDIA_GPU=false
NVIDIA_RTX_40_OR_NEWER=false
if nvidia-smi -L > /dev/null 2>&1; then
    NVIDIA_GPU=true
    # Check for RTX 40 series or later
    if nvidia-smi -L | grep -E 'RTX( PRO)? [4-9][0-9][0-9][0-9]' > /dev/null 2>&1; then
        NVIDIA_RTX_40_OR_NEWER=true
    fi
fi

# Set HWACCEL based on codec and GPU type
HWACCEL=false
if [ "$CPU_ONLY" = false ]; then
    if [[ "$CODEC" =~ ^(libsvtav1|av1)$ ]]; then
        if [ "$NVIDIA_RTX_40_OR_NEWER" = true ]; then
            HWACCEL=true
        fi
    elif [ "$NVIDIA_GPU" = true ]; then
        HWACCEL=true
    fi
fi

# Check if ffmpeg and ffprobe are installed
command -v ffmpeg >/dev/null 2>&1 || error_exit "ffmpeg is not installed."
command -v ffprobe >/dev/null 2>&1 || error_exit "ffprobe is not installed."

# Check if the input file exists and is a valid video file
[ -f "$INPUT_VIDEO" ] || error_exit "Input file does not exist."

# Identify the codec of the input video file, if a codec is not specified by the user
CODEC=$USER_SPECIFIED_CODEC
if [ -z "$CODEC" ]; then
    CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
fi

# Check if the codec is supported; if not, fallback to libx265
if ! [[ "$CODEC" =~ ^(libx264|libx265|h264|hevc|libsvtav1|av1)$ ]]; then
    echo "Unsupported or unknown codec: $CODEC. Falling back to default codec libx265."
    CODEC="libx265"
fi

# Upgrade to GPU-accelerated codec if available and not CPU only
if [ "$HWACCEL" = true ]; then
    case "$CODEC" in
        libx264 | h264 ) CODEC="h264_nvenc";;
        libx265 | hevc ) CODEC="hevc_nvenc";;
        libsvtav1 | av1 ) CODEC="av1_nvenc";;
    esac
fi

# Prepare output file name
OUTPUT_VIDEO="compressed_$INPUT_VIDEO"
[ -f "$OUTPUT_VIDEO" ] && error_exit "Output file already exists. Please remove it or use a different name."

# Check video height and adjust if no height/width/bitrate is specified and height is greater than or equal to 2800
if [ -z "$MODE" ] && [ "$HEIGHT_OR_WIDTH_SPECIFIED" = false ]; then
    INPUT_HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
    if [ "$INPUT_HEIGHT" -ge 2800 ]; then
        SPECIFIED_HEIGHT=2160
    fi
fi

# Encoding settings based on mode, encoder, and encoding mode (CBR or VBR)
if [[ "$CODEC" =~ ^(h264_nvenc|hevc_nvenc)$ ]]; then
    # NVENC encoder presets
    NVENC_PRESET="p7"  # You can change this to p1 (fastest) to p7 (best quality)
    ENCODE_SETTINGS="-c:v $CODEC -preset $NVENC_PRESET"
elif [[ "$CODEC" =~ ^(libsvtav1|av1)$ ]]; then
    # Preset for AV1 using libsvtav1
    AV1_PRESET="2"  # You can change this to 0 (best quality) to 12 (fastest)
    ENCODE_SETTINGS="-c:v libsvtav1 -preset $AV1_PRESET"
    RATE_MODE="maxrate"  # libsvtav1 requires maxrate to be set
else
    # Preset for software-based encoders
    SOFTWARE_PRESET="slower"
    ENCODE_SETTINGS="-c:v $CODEC -preset $SOFTWARE_PRESET"
fi

# Set video scale if height or width is specified
if [ -n "$SPECIFIED_HEIGHT" ] || [ -n "$SPECIFIED_WIDTH" ]; then
    SCALE="-vf scale="
    [ -n "$SPECIFIED_WIDTH" ] && SCALE+="${SPECIFIED_WIDTH}:" || SCALE+="-1:"
    [ -n "$SPECIFIED_HEIGHT" ] && SCALE+="${SPECIFIED_HEIGHT}" || SCALE+="-1"
    ENCODE_SETTINGS="$ENCODE_SETTINGS $SCALE"
fi

if [ "$MODE" = "size" ]; then
    # Calculate approximate bitrate for target size
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")
    DURATION=${DURATION%.*} # Convert to integer by trimming the decimal part
    TARGET_SIZE_BITS=$(( VALUE * 8 * 1024 * 1024 ))
    AVERAGE_BITRATE=$(( TARGET_SIZE_BITS / DURATION ))
    RATE="${AVERAGE_BITRATE}k"
    BUFSIZE="$(( AVERAGE_BITRATE * 10 ))k"
elif [ "$MODE" = "bitrate" ]; then
    RATE="${VALUE}k"
    BUFSIZE="$(( VALUE * 10 ))k"
else
    RATE=$DEFAULT_RATE
    BUFSIZE=$DEFAULT_BUFSIZE
fi

if [ "$ENCODING_MODE" = "cbr" ]; then
    ENCODE_SETTINGS="$ENCODE_SETTINGS -b:v $RATE -bufsize $BUFSIZE"
else
    ENCODE_SETTINGS="$ENCODE_SETTINGS -crf $DEFAULT_CRF -b:v $RATE -bufsize $BUFSIZE"
fi

if [ "$RATE_MODE" = "maxrate" ]; then
    ENCODE_SETTINGS="$ENCODE_SETTINGS -maxrate $RATE"
fi

# Print the ffmpeg command
FFMPEG_CMD="ffmpeg -i \"$INPUT_VIDEO\" $ENCODE_SETTINGS -c:a copy \"$OUTPUT_VIDEO\""
echo "Executing command: $FFMPEG_CMD"

# Encoding using ffmpeg
echo "Starting compression..."
eval $FFMPEG_CMD || error_exit "Encoding failed."

echo "Compression completed: '$OUTPUT_VIDEO'"
