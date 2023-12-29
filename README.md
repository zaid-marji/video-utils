This application splits videos into scenes by detecting black frames that usually indicates transitions between scenes. It uses ffmpeg as a backend.

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
