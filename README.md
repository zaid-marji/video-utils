This collection contains two applications:

1. `video-split-scenes`: An application that splits videos into scenes by detecting black frames that usually indicates transitions between scenes. It uses ffmpeg as a backend.
2. `video-compress`: An application that compresses videos by re-enconding them with a specified target bitrate or target file size. By default it targets a bitrate of 5.6 Mbps. If the video height exceeds 2800 px, it will be rescaled to height of 2160 px while maintaining aspect ratio.

# video-split-scenes

Usage:
```sh
video-split-scenes [--duration $d] [--pix_th $pix_th] [--pic_th $pic_th] $file
```

If the output contains scenes that should be merged:
```sh
video-split-scenes [--duration $d] [--pix_th $pix_th] [--pic_th $pic_th] [--merge $merge_scenes] $file
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
