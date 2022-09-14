# NAME

speakeasy\_types.pl - Set the resource types in a SpeakEasy database.

# SYNOPSIS

    ./speakeasy_types.pl db.sqlite types.txt

# DESCRIPTION

This script is used to configure the resource types in the `rtype`
table of the given SpeakEasy database.

The first argument is the SpeakEasy database to configure.  The second
argument is the path to a text file to use to define the resource types.
See below for the format of the text file.

## Resource types file format

The resource types file is a UTF-8 plain-text file.  Line breaks may be
LF or CR+LF, and there may be an optional UTF-8 Byte Order Mark (BOM) at
the start of the file.

Blank lines are lines that are empty or contain only whitespace.

Records are sequences of one or more consecutive non-blank lines.  Each
sequence of non-blank lines is a single record.

Each record line has the following format:

    1. Property name
    2. ASCII colon
    3. Property value

Any amount of whitespace is allowed before or after any of these
elements, and it's also allowed to have no whitespace at all.

Every record must have a `Type-Class` property that is one of the
following:

    image
    video
    audio
    text

Every record must have a `Type-Name` property that is the unique name
of the type.  This must be a string of length 1-31 containing only ASCII
alphanumerics and underscores, where the first character is not a digit.

Every record must have a `MIME-Type` property which is the MIME type to
associate with the data type.  The value will be trimmed of leading and
trailing whitespace but otherwise will be recorded as-is in the
database.  It must have only US-ASCII characters in range \[0x21, 0x7e\]
and it must have at least one and at most 63 characters.

Optionally, a record may have a `Default-Thumb` property.  If provided,
the value must be an unsigned decimal integer which gives the resource
number in the database of an image resource that will be the default
thumbnail image for all resources of this type.  If this property is
omitted, there will be no default thumbnail property assigned to this
type.

Records are processed in the order they appear in the file.  Each record
either inserts a new resource type record or updates an existing one
with new values.

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
