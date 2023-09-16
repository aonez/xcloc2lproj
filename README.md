## xcloc2lproj

A macOS commandline utility for parsing `xcloc` translation files into `lproj` translation strings.

```
Usage: xcloc2lproj <options> [<xcloc_path>...]

Options:
  -d path                Parse all xcloc files found in `path`
  -o output_file         Output file, default is the current path
  -exclude-id id         Exclude translation units that their id match the `id` string
  -exclude-file file     Exclude origin strings files that match the `file` path
  -x                     Do not create paths, only strings files
  -lproj                 Append .lproj extension to the language folder
  -q                     Be quiet
```

This project is made using Swift and under the BSD or GPL licenses. Copyright © aone. All rights reserved.
