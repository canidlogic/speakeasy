# NAME

speakeasy\_pic.pl - Batch import images into a SpeakEasy database.

# SYNOPSIS

    ./speakeasy_pic.pl db.sqlite script.txt

# DESCRIPTION

This script is used to batch import a number of images into a SpeakEasy
database.

Before using this script, you must set up the `jpeg` and `png` types
in the `rtype` table using `speakeasy_types.pl`.  You only need
`jpeg` if you will be storing JPEG files in the database, and you only
need `png` if you will be storing PNG files in the database.

Before using this script, you must also set up the configuration
variables in the `vars` table that are required by the module
`SpeakEasy::Image`.  See the documentation of that module for further
information.

The first argument is the SpeakEasy database to configure.  The second
argument is the path to a text file to use as a batch script.  See below
for the format of the text file batch script.

## Batch script file format

The batch script file is a UTF-8 plain-text file.  Line breaks may be
LF or CR+LF, and there may be an optional UTF-8 Byte Order Mark (BOM) at
the start of the file.

Blank lines are lines that are empty or contain only whitespace.

Records are sequences of one or more consecutive non-blank lines.  Each
sequence of non-blank lines is a single record.

The first line of a record is the command line.  The following command
lines are defined:

    fscd subdir
    dbcd subdir
    pic source_name.jpg

There is a current directory in the file system, which starts out as the
current directory the script is run in.  There is also a current
directory in the database, which starts out at the root level and not in
any subdirectories.

To change the file system current directory, use `fscd` and supply the
name of a subdirectory in the current directory, or `..` to go up one
level.  If you specify multiple names separated by slashes, the effect
is equivalent to a sequence of `fscd` commands in order of the names
given.

To change the database current directory, use `dbcd` and supply the
name of a subdirectory in the current directory, or `..` to go up one
level.  Directories that do not exist will be created as new nodes.  The
first `dbcd` must be into the root directory.  Specifying multiple
names separated by slashes is equivalent in effect to a sequence of
`dbcd` commands in order of the names given.

To import a picture from the current file system directory into the
current database node, use `pic` and supply the name of a file relative
to the current directory in the file system.  You may use a subdirectory
tree with slashes to get to the file from the current file system
directory.

After the first line of a record, any additional record lines define
properties of the operation.  Each line after the first has the
following format:

    1. Property name
    2. ASCII colon
    3. Property value

Any amount of whitespace is allowed before or after any of these
elements, and it's also allowed to have no whitespace at all.

Unrecognized property names are ignored.  However, property names must
be sequences of 1-31 US-ASCII alphanumeric and hyphen characters.

The only recognized property names are on the `pic` command.

Property `Source-Type` may be either `jpeg` or `png`, defining the
type of image the source file is.  If not specified, the end of the
filename given in the `pic` command must be a case-insensitive match
for `.JPG` `.JPEG` or `.PNG` and that will then determine the file
type.

Property `Target-Type` may be either `jpeg` or `png`.  If not
specified, the target type will be the same as the source type.  Use
this property if you want to convert a source JPEG into a PNG in the
database, or a source PNG into a JPEG in the database.

Property `Clockwise` may be either `0` `90` `180` or `270`
indicating a clockwise rotation in degrees.  If not specified, it
defaults to zero.

Property `Name` is a sequence of one to 255 Unicode codepoints that
neither begins nor ends with whitespace.  It represents the name that
will be recorded for this picture in the database.  If not specified, it
defaults to the filename, without any `.JPG` `.JPEG` or `.PNG`
extension.

Property `Desc` is a sequence of one or more Unicode codepoints that
neither begins nor ends with whitespace.  There may be multiple `Desc`
properties in a single record, in which case subsequent `Desc`
properties are concatenated to the end of preceding `Desc` records,
separated from the preceding record with a space.

Each record is executed in a separate database transaction, so if there
is a failure, every successful transaction up to the point of failure
will be commited.

For the `pic` command, if a picture with matching name already exists
in a node, the command is skipped.  This allows you to retry scripts
that failed midway through.

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
