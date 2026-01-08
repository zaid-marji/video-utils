This collection contains the following applications:

1. `video-split-scenes`: An application that splits videos into scenes by detecting black frames that usually indicates transitions between scenes. It uses ffmpeg as a backend.
2. `video-compress`: An application that compresses videos by re-enconding them with a specified target bitrate or target file size. By default it targets a bitrate of 5.6 Mbps. If the video height exceeds 2800 px, it will be rescaled to height of 2160 px while maintaining aspect ratio.
3. `video-bitrate`: An application that finds videos based on their bitrate. By default it displays files in the top 2% bitrate with a bitrate above 9.2 Mbps in the current working directory.
4. `video-join`: An application that joins videos together. It uses ffmpeg as a backend. It can join videos with different codecs, but the output will be in the codec of the first video. The output will be in the same directory as the first video.

# video-split-scenes

Usage:
```sh
video-split-scenes [--duration $d] [--pix_th $pix_th] [--pic_th $pic_th] $file
```

If the output contains scenes that should be merged:
```sh
video-split-scenes [--duration $d] [--pix_th $pix_th] [--pic_th $pic_th] [--merge $merge_scenes] $file
```

If the default time limits need modification:
```sh
video-split-scenes [--duration $d] [--pix_th $pix_th] [--pic_th $pic_th] [--scene_limit $min_scene_duration] [--intro_limit $max_intro_duration] $file
```

To detect white frames instead of black frames:
```sh
video-split-scenes --white $file
```

To defer splitting by using the last valid transition within a time window of the first valid split point (default 30s):
```sh
video-split-scenes --defer $file
video-split-scenes --defer --defer_limit 60 $file
```

Long black segments (>3s by default) are automatically analyzed and adjusted to detect the actual black frame boundaries. This helps when a short black frame is followed by dim content (like credits) that gets merged into one long detection. To adjust or disable:
```sh
video-split-scenes --max_duration 5 $file
video-split-scenes --max_duration 0 $file
video-split-scenes --disable_auto_adjust $file
```

Get help:
```sh
video-split-scenes -h
```

The available parameters control how black frames are detected. Use the help option to get more details about those options.

# video-compress

Usage:
```sh
video-compress [-c $codec] [-b $bitrate] [-s $filesize] [-m $encodemode] [-r $ratemode] [-height $height] [-width $width] [--cpu-only] $file
```

Get help:
```sh
video-compress -h
```

# video-bitrate

Usage:
```sh
video-bitrate [-th $bitrate] [-top $percent] [-size $size] [-target $target] [-order $criteria] [-savings $savings] $dir
```

Get help:
```sh
video-bitrate -h
```

# video-join
Usage:
```sh
video-join $files [-o $output]
```
Get help:
```sh
video-join -h
```
