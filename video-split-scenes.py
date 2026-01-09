import argparse
import subprocess
import re
import os


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


# Set up argument parser
troubleshooting = """
Troubleshooting:
  Credits split between two scenes:
    Make detection stricter: increase picture black ratio threshold (e.g., --pic_th 0.99)
  
  Credits at beginning of scene instead of end:
    Use --defer to split at the last transition in a cluster
  
  Transitions are white instead of black:
    Use --white flag
  
  Part of intro included in first scene:
    Increase upper time limit for the introduction if intro is longer than 3 minutes (e.g., --intro_limit 300)
    Or use --merge 0-1 to include intro in scene 1
  
  Multiple scenes joined together (missing splits):
    Make detection more lenient: reduce minimum duration of black segments (e.g., --duration 0.2)
  
  One scene split into multiple scenes (too many splits):
    Make detection stricter: increase --duration or --pic_th, or decrease --pix_th
    Or merge scenes to combine specific scenes (e.g., --merge 3-5)
"""

parser = argparse.ArgumentParser(
    description="Video Scene Splitter with Keyframe Detection",
    epilog=troubleshooting,
    formatter_class=argparse.RawDescriptionHelpFormatter
)
parser.add_argument("video_file", help="Path to the input video file.")
parser.add_argument("--duration", type=float, default=0.5, help="Minimum duration (in seconds) of a black segment to be considered a transition (default: 0.5s).")
parser.add_argument("--pic_th", type=float, default=0.98, help="Picture black ratio threshold for black frame detection, representing the minimum percentage of pixels that are considered black for the entire picture to be considered black (0-1, default: 0.98). Higher values require more pixels to be black to be considered a black frame.")
parser.add_argument("--pix_th", type=float, default=0.2, help="Pixel threshold for black frame detection, representing the maximum brightness level (0-1, default: 0.2). Lower values require each pixel to be less bright to be considered black.")
parser.add_argument("--merge", type=str, help="Specify scenes to merge in the format '3-5,6-7'.")
parser.add_argument("--scene_limit", type=int, default=300, help="Minimum scene length in seconds (default: 300s).")
parser.add_argument("--intro_limit", type=int, default=180, help="Upper time limit for the introduction in seconds (default: 180s).")
parser.add_argument("--white", action="store_true", help="Detect white frames instead of black frames for scene transitions.")
parser.add_argument("--defer", action="store_true", help="Defer splitting by using the last valid transition within --defer_limit seconds of the first valid split point.")
parser.add_argument("--defer_limit", type=int, default=30, help="Maximum extension (in seconds) from the first valid split point when using --defer (default: 30s).")
parser.add_argument("--max_duration", type=float, default=3.0, help="Maximum duration (in seconds) for a black segment before auto-adjustment is triggered. Set to 0 to disable (default: 3s).")
parser.add_argument("--disable_auto_adjust", action="store_true", help="Disable all automatic adjustments.")
parser.add_argument("--debug", action="store_true", help="Print debug information about detected transitions and split points.")
args = parser.parse_args()

video_file = args.video_file
duration = args.duration
pic_th = args.pic_th
pix_th = args.pix_th
merge_scenes = parse_merge_scenes(args.merge)
min_scene_duration = args.scene_limit       # Minimum duration for a scene in seconds (default: 5 minutes)
intro_time_limit = args.intro_limit         # Maximum duration for the intro in seconds (default: 2 minutes)
detect_white = args.white                   # Detect white frames instead of black frames
defer_mode = args.defer                     # Split at last matching transition instead of first
defer_limit = args.defer_limit              # Maximum extension from first valid split point
max_duration = args.max_duration            # Maximum black segment duration before adjustment
disable_auto_adjust = args.disable_auto_adjust  # Disable all automatic adjustments
debug_mode = args.debug                     # Print debug information

# Validate argument combinations
if defer_limit != 30 and not defer_mode:
    parser.error("--defer_limit requires --defer to be specified")

if max_duration != 0 and max_duration <= duration:
    parser.error("--max_duration must be greater than --duration (or set to 0 to disable)")


def run_command(cmd):
    """Run a command and return its output."""
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e.output}")
        return ""


def refine_long_segment(video_file, start_time, end_time, duration_th, pic_th, pix_th, max_duration, detect_white, debug_mode):
    """Refine a long black/white segment by trying stricter pic_th values.
    
    Goal: Find segments shorter than max_duration.
    Returns a list of refined (start, end) tuples, or the original segment if no refinement possible.
    """
    segment_duration = end_time - start_time
    
    # Start slightly before to avoid missing the beginning of the black frame
    analysis_start = max(0, start_time - 0.5)
    analysis_duration = segment_duration + 1.0  # Add buffer at end too
    
    # Try up to 2 increasingly strict thresholds
    current_th = pic_th
    for attempt in range(2):
        test_th = round((current_th + 1.0) / 2, 4)
        
        if debug_mode:
            print(f"    Trying stricter threshold (attempt {attempt + 1}): pic_th={test_th}")
        
        # Run blackdetect on the segment with buffer
        vf_filter = f'{"negate," if detect_white else ""}blackdetect=d={duration_th}:pic_th={test_th}:pix_th={pix_th}'
        cmd = [
            'ffmpeg', '-ss', str(analysis_start), '-i', video_file, '-t', str(analysis_duration),
            '-vf', vf_filter,
            '-an', '-f', 'rawvideo', '-y', '/dev/null'
        ]
        output = run_command(cmd)
        
        # Parse refined black frames
        refined_frames = re.findall(r'black_start:(\d+\.?\d+).*?black_end:(\d+\.?\d+)', output)
        
        if not refined_frames:
            if debug_mode:
                print(f"      No detections (too strict), keeping original")
            return [(start_time, end_time)]
        
        # Adjust timestamps to absolute time and filter to original segment range
        refined = []
        for s, e in refined_frames:
            abs_start = analysis_start + float(s)
            abs_end = analysis_start + float(e)
            # Only include segments that overlap with original range
            if abs_end > start_time and abs_start < end_time:
                # Clamp to original range
                abs_start = max(abs_start, start_time)
                abs_end = min(abs_end, end_time)
                refined.append((abs_start, abs_end))
        
        if not refined:
            if debug_mode:
                print(f"      No segments in original range, keeping original")
            return [(start_time, end_time)]
        
        # Filter: only keep segments shorter than max_duration
        short_segments = [(s, e) for s, e in refined if (e - s) < max_duration]
        
        if short_segments:
            if debug_mode:
                print(f"      Found {len(short_segments)} short segment(s): {[(f'{s:.2f}', f'{e:.2f}') for s, e in short_segments]}")
            return short_segments
        
        # No short segments found, try stricter threshold
        if debug_mode:
            durations = [f"{e-s:.2f}s" for s, e in refined]
            print(f"      All {len(refined)} segment(s) too long: {durations}")
        
        current_th = test_th
    
    if debug_mode:
        print(f"      Keeping original after {attempt + 1} attempts")
    return [(start_time, end_time)]


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


def should_merge(scene_number):
    """Check if a scene should be merged based on the current scene number."""
    for start, end in merge_scenes:
        if start <= scene_number < end:
            return True
    return False


# Extract the file extension
_, file_extension = os.path.splitext(video_file)

# Detect black/white frames using ffmpeg
# For white frame detection, we negate the video first so white becomes black
frame_type = "white" if detect_white else "black"
print(f"Detecting {frame_type} frames, please wait...")
vf_filter = f'{"negate," if detect_white else ""}blackdetect=d={duration}:pic_th={pic_th}:pix_th={pix_th}'
ffmpeg_detect_cmd = ['ffmpeg', '-i', video_file, '-vf', vf_filter, '-an', '-f', 'rawvideo', '-y', '/dev/null']
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
black_frames = [(float(x[0]), float(x[1])) for x in black_frames]
black_frames = sorted(black_frames, key=lambda x: x[0])

# Debug: print all detected transitions
if debug_mode:
    print(f"\nDetected {len(black_frames)} transitions:")
    for i, (start, end) in enumerate(black_frames):
        kf = find_nearest_keyframe(keyframes, start, end)
        print(f"  {i+1}. {start:.2f}s - {end:.2f}s (keyframe: {kf:.2f}s)" if kf else f"  {i+1}. {start:.2f}s - {end:.2f}s (no keyframe)")
    print()

# Adjust long black segments if enabled
auto_adjust_enabled = not disable_auto_adjust and max_duration > 0
adjustments_made = False
if auto_adjust_enabled:
    adjusted_black_frames = []
    for start, end in black_frames:
        segment_duration = end - start
        if segment_duration > max_duration:
            if debug_mode:
                print(f"  Long segment detected: {start:.2f}s - {end:.2f}s ({segment_duration:.2f}s)")
            adjusted = refine_long_segment(video_file, start, end, duration, pic_th, pix_th, max_duration, detect_white, debug_mode)
            # Check if adjustment actually changed something
            if adjusted != [(start, end)]:
                adjustments_made = True
            adjusted_black_frames.extend(adjusted)
        else:
            adjusted_black_frames.append((start, end))
    black_frames = sorted(adjusted_black_frames, key=lambda x: x[0])

# Debug: print all detected transitions (after adjustment) only if adjustments were made
if adjustments_made:
    print("Long black segment(s) detected and adjusted.")
    if debug_mode:
        print(f"\nDetected {len(black_frames)} transitions (after pic_th adjustment):")
        for i, (start, end) in enumerate(black_frames):
            kf = find_nearest_keyframe(keyframes, start, end)
            print(f"  {i+1}. {start:.2f}s - {end:.2f}s (keyframe: {kf:.2f}s)" if kf else f"  {i+1}. {start:.2f}s - {end:.2f}s (no keyframe)")
        print()

# Determine the end of the intro
intro_end = 0.0
for start, end in black_frames:
    if start < intro_time_limit:
        scene_end = find_nearest_keyframe(keyframes, start, end)
        intro_end = max(intro_end, scene_end if scene_end else end)
    else:
        break

# Process each scene
# First pass: collect ALL valid keyframe transitions (not filtered by min_scene_duration yet)
all_transitions = []
for start, end in black_frames:
    scene_end = find_nearest_keyframe(keyframes, start, end)
    if scene_end and scene_end > intro_end:
        all_transitions.append(scene_end)

# Debug: print all transitions
if debug_mode:
    print(f"All valid transitions after intro ({len(all_transitions)}): {[f'{t:.2f}s' for t in all_transitions]}")

# Second pass: determine split points based on mode
split_points = []
current_start = intro_end
premerge_scene_number = 1

if defer_mode:
    # Defer: for each "long enough" segment, find the LAST transition within defer_limit of the first valid split
    i = 0
    while i < len(all_transitions):
        # First, check if this transition is far enough from current_start
        if all_transitions[i] - current_start >= min_scene_duration:
            first_valid_split = all_transitions[i]
            # Find the last transition within defer_limit of the first valid split
            j = i
            while j < len(all_transitions) - 1:
                if all_transitions[j + 1] - first_valid_split <= defer_limit:
                    j += 1
                else:
                    break
            
            # Use the last transition within the limit
            if should_merge(premerge_scene_number):
                current_start = all_transitions[j]
                premerge_scene_number += 1
            else:
                split_points.append(all_transitions[j])
                current_start = all_transitions[j]
                premerge_scene_number += 1
            i = j + 1
        else:
            i += 1
else:
    # Non-greedy: use the FIRST transition that meets min_scene_duration
    for t in all_transitions:
        if t - current_start >= min_scene_duration:
            if should_merge(premerge_scene_number):
                current_start = t
                premerge_scene_number += 1
                continue
            split_points.append(t)
            current_start = t
            premerge_scene_number += 1

# Debug: print split points
if debug_mode:
    print(f"Final split points ({len(split_points)}): {[f'{s:.2f}s' for s in split_points]}")
    print()

# Check if intro should be merged with scene 1
merge_intro = should_merge(0)

# Process intro if it exists and shouldn't be merged
if intro_end > 0 and not merge_intro:
    print(f"Processing intro (ends at {intro_end}s)...")
    output_file = f'Intro{file_extension}'
    ffmpeg_intro_cmd = ['ffmpeg', '-ss', '0', '-i', video_file, '-t', str(intro_end), '-c', 'copy', output_file]
    subprocess.run(ffmpeg_intro_cmd)

# Second pass: output scenes using the split points
scene_start = 0 if merge_intro else intro_end
scene_number = 1

for scene_end in split_points:
    duration = scene_end - scene_start
    output_file = f'Scene {scene_number}{file_extension}'
    print(f"Processing scene {scene_number} (starts at {scene_start}s, ends at {scene_end}s)...")
    ffmpeg_scene_cmd = ['ffmpeg', '-ss', str(scene_start), '-i', video_file, '-t', str(duration), '-c', 'copy', output_file]
    subprocess.run(ffmpeg_scene_cmd)
    scene_start = scene_end
    scene_number += 1

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
