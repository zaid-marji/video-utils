import argparse
import subprocess
import re
import os

def run_command(cmd):
    """Run a command and return its output."""
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e.output}")
        return ""

def find_nearest_keyframe(keyframes, transition_start, transition_end):
    """Find the nearest keyframe to the midpoint of a transition.

    It uses the following logic:
    1. If there are no keyframes before or after the midpoint, return None.
    2. If the nearest keyframe is within the transition, return the nearest keyframe to the midpoint.
    3. If the distance to the nearest keyframe from both sides is close, return the nearest keyframe before the midpoint.
    4. Return the nearest keyframe to the midpoint.

    Args:
        keyframes: A list of keyframe timestamps.
        midpoint: The midpoint of the transition.
        transition_start: The start of the transition.
        transition_end: The end of the transition.
    """
    
    midpoint = (transition_start + transition_end) / 2
    before_midpoint = [kf for kf in keyframes if kf <= midpoint]
    after_midpoint = [kf for kf in keyframes if kf >= midpoint]

    if not before_midpoint and not after_midpoint:
        return None  # No keyframes in transition
    
    if not before_midpoint:
        return after_midpoint[0]
    
    if not after_midpoint:
        return before_midpoint[-1]

    nearest_before = before_midpoint[-1]
    nearest_after = after_midpoint[0]

    # Check if the nearest keyframe is within the transition
    if nearest_before >= transition_start and nearest_after <= transition_end:
        # Find the nearest keyframe to the midpoint
        if midpoint - nearest_before <= nearest_after - midpoint:
            return nearest_before
        else:
            return nearest_after
        
    if nearest_before >= transition_start:
        return nearest_before
    if nearest_after <= transition_end:
        return nearest_after
    
    # Check if the distance to the nearest keyframe from both sides is close
    if abs((midpoint - nearest_before) - (nearest_after - midpoint)) <= 0.5:
        return nearest_before
    
    # Return the nearest keyframe
    if midpoint - nearest_before <= nearest_after - midpoint:
        return nearest_before
    else:
        return nearest_after


def parse_merge_scenes(input_str):
    """Parse input string for scene merge specifications."""
    if not input_str:
        return []
    scene_ranges = input_str.split(',')
    merge_list = []
    for scene_range in scene_ranges:
        start, end = map(int, scene_range.split('-'))
        merge_list.append((start, end))
    return merge_list


def should_merge(scene_number):
    """Check if a scene should be merged based on the current scene number."""
    for start, end in merge_scenes:
        if start <= scene_number < end:
            return True
    return False


# Set up argument parser
parser = argparse.ArgumentParser(description="Video Scene Splitter with Keyframe Detection")
parser.add_argument("video_file", help="Path to the input video file.")
parser.add_argument("--duration", type=float, default=0.5, help="Minimum duration (in seconds) of a black scene to be considered a transition (default: 0.5s).")
parser.add_argument("--pic_th", type=float, default=0.98, help="Picture black ratio threshold for black frame detection, representing the minimum percentage of pixels that are considered black for the entire picture to be considered black (0-1, default: 0.98). Higher values require more pixels to be black to be considered a black frame.")
parser.add_argument("--pix_th", type=float, default=0.2, help="Pixel threshold for black frame detection, representing the maximum brightness level (0-1, default: 0.2). Lower values require each pixel to be less bright to be considered black.")
parser.add_argument("--merge", type=str, help="Specify scenes to merge in the format '3-5,6-7'.")
parser.add_argument("--scene_limit", type=int, default=300, help="Minimum scene length in seconds (default: 300s).")
parser.add_argument("--intro_limit", type=int, default=180, help="Upper time limit for the introduction in seconds (default: 180s).")
args = parser.parse_args()

video_file = args.video_file
duration = args.duration
pic_th = args.pic_th
pix_th = args.pix_th
merge_scenes = parse_merge_scenes(args.merge)
min_scene_duration = args.scene_limit       # Minimum duration for a scene in seconds (default: 5 minutes)
intro_time_limit = args.intro_limit         # Maximum duration for the intro in seconds (default: 2 minutes)

# Extract the file extension
_, file_extension = os.path.splitext(video_file)

# Detect black frames using ffmpeg
print("Detecting black frames, please wait...")
ffmpeg_detect_cmd = ['ffmpeg', '-i', video_file, '-vf', f'blackdetect=d={duration}:pic_th={pic_th}:pix_th={pix_th}', '-an', '-f', 'rawvideo', '-y', '/dev/null']
black_frames_output = run_command(ffmpeg_detect_cmd)

# Detect keyframes using ffprobe
print("Detecting keyframes, please wait...")
ffprobe_cmd = ['ffprobe', '-select_streams', 'v', '-skip_frame', 'nokey', '-show_frames', '-show_entries', 'frame=pkt_pts_time', '-of', 'csv=p=0', video_file]
keyframes_output = run_command(ffprobe_cmd)

# Extract keyframe timestamps from the ffprobe output and sort them
keyframe_pattern = r'\d+\.\d+'  # Regex pattern to match timestamps
keyframes = sorted(set(float(match) for match in re.findall(keyframe_pattern, keyframes_output) if match))

# Find black frame ranges and sort them
black_frames = re.findall(r'black_start:(\d+\.?\d+).*?black_end:(\d+\.?\d+)', black_frames_output)
black_frames = map(lambda x: (float(x[0]), float(x[1])), black_frames)
black_frames = sorted(black_frames, key=lambda x: x[0])

# Determine the end of the intro
intro_end = 0.0
for start, end in black_frames:
    if start < intro_time_limit:
        scene_end = find_nearest_keyframe(keyframes, start, end)
        intro_end = max(intro_end, scene_end if scene_end else end)
    else:
        break

# Process intro if it exists
if intro_end > 0:
    print(f"Processing intro (ends at {intro_end}s)...")
    output_file = f'Intro{file_extension}'
    ffmpeg_intro_cmd = ['ffmpeg', '-ss', '0', '-i', video_file, '-t', str(intro_end), '-c', 'copy', output_file]
    subprocess.run(ffmpeg_intro_cmd)

# Process each scene
scene_start = intro_end
scene_number = 1
premerge_start = intro_end
premerge_scene_number = 1
for start, end in black_frames:
    scene_end = find_nearest_keyframe(keyframes, start, end)
    duration = scene_end - scene_start
    premerge_duration = scene_end - premerge_start

    if scene_end and premerge_duration >= min_scene_duration:
        if should_merge(premerge_scene_number):
            premerge_start = scene_end
            premerge_scene_number += 1
            continue
        output_file = f'Scene {scene_number}{file_extension}'
        print(f"Processing scene {scene_number} (starts at {scene_start}s, ends at {scene_end}s)...")
        ffmpeg_scene_cmd = ['ffmpeg', '-ss', str(scene_start), '-i', video_file, '-t', str(duration), '-c', 'copy', output_file]
        subprocess.run(ffmpeg_scene_cmd)
        scene_start = scene_end
        premerge_start = scene_end
        scene_number += 1
        premerge_scene_number += 1

# Process the ending
end_time = float(run_command(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', video_file]))  # Get the duration of the video
if end_time - scene_start > 0:
    duration = end_time - scene_start
    output_file = f'Scene {scene_number}{file_extension}'
    if duration < min_scene_duration:
        output_file = f'Outro{file_extension}'
    print(f"Processing scene (starts at {scene_start}s)...")
    ffmpeg_ending_cmd = ['ffmpeg', '-ss', str(scene_start), '-i', video_file, '-c', 'copy', output_file]
    subprocess.run(ffmpeg_ending_cmd)

print("Video splitting completed.")
