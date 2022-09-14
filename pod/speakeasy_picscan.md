# NAME

speakeasy\_picscan.pl - Generate a script for speakeasy\_pic by scanning
directories.

# SYNOPSIS

    ./speakeasy_picscan.pl scan.script /base/path/
    ./speakeasy_picscan.pl scan.script /base/path/ -forcejpg

# DESCRIPTION

This script performs directory scanning to generate a script that can
then be fed into the `speakeasy_pic.pl` script.

The first argument is the path to a text file that defines what to scan.
See below for the format of the text file.

The second argument is the base path to start scanning in.  It must end
with a forward slash.  You will need to use this same base path when
running the `speakeasy_pic.pl` script on the generated script.

The optional third argument is `-forcejpg`.  If present, every single
`pic` command in the generated script will have a `Target-Type`
property that is set to `jpeg`.  This will cause everything to get
transcoded to JPEG when it is imported into the database.

## Scanning file format

The scanning file is a UTF-8 plain-text file.  Line breaks may be LF or
CR+LF, and there may be an optional UTF-8 Byte Order Mark (BOM) at the
start of the file.

Blank lines are lines that are empty or contain only whitespace.

Records are sequences of exactly two consecutive non-blank lines.
Records must be separated from each other with at least one blank line.
Trailing whitespace will be trimmed, but not leading whitespace.

The first line is the path to a directory relative to the given base
path.  Subdirectory names must be separated by forward slashes.  Neither
the first nor last character may be a slash, and you may not have two
slashes next to each other.  None of the directory names may be `.` or
`..`

The second line is the path to a node in the SpeakEasy database.  It has
the same format as the first line.  It is always relative to the root of
the node tree, such that the first directory name in the path is the
root directory in the node tree.

Each record is transformed into a sequence of instructions in the
generated script.  The first set of instructions positions the current
directory of the file system in the given directory and the current
directory of the SpeakEasy database in the other given directory.  Then,
there are a sequence of `pic` instructions to import all the images
that are found in that directory during scanning.  The next set of
instructions for each record returns the current directory of the file
system and the current directory of the SpeakEasy database back to their
initial states.  The final set of instructions for each record is a
recursive invocation to process any subdirectories, using subdirectories
with matching names in the SpeakEasy database as well.

During scanning, the only entities that should be encountered are either
regular files that have a `.jpg` `.jpeg` or `.png` extension (case
insensitive), or subdirectories.  If anything else is encountered, a
warning will be printed to standard error but otherwise the entity will
be skipped and processing will continue.

# AUTHOR

Noah Johnson, `noah.johnson@loupmail.com`

# COPYRIGHT AND LICENSE

Copyright (C) 2022 Multimedia Data Technology Inc.

MIT License:

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
