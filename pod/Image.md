# NAME

SpeakEasy::Image - Manage image transformations and transcoding for
SpeakEasy.

# SYNOPSIS

    use SpeakEasy::Image;
    
    # Configure the imager correctly
    my $img = SpeakEasy::Image->configure($dbc);
    
    # Load a binary blob storing full-size JPEG file and its thumb
    my ($jpeg, $thumb) = $img->load($path, 'jpeg', 0);
    if (defined $thumb) {
      # Thumbnail only defined if different from full-size
      ...
    }
    
    # Also supports PNG profile
    my ($png, $pthumb) = $img->load($path, 'png', 0);
    
    # You can transcode PNG to JPEG or vice versa
    my ($transcode, $tthumb) = $img->load($png_path, 'png2jpeg', 0);
    
    # Load with rotation 90 degrees clockwise
    my ($rotated, $rthumb) = $img->load($path, 'jpeg', 90);

# DESCRIPTION

Module that handles loading and transcoding images as necessary before
they will be stored in a SpeakEasy database.

The constructor gets configuration information from a SpeakEasy
database.  See the constructor for further information.

The `load` function can then load a full image file into a binary
string, applying any necessary transformations and transcodings.

Two formats are supported for loading, `jpeg` and `png`.  It is also
possible to transcode, such that a JPEG input file is converted to a PNG
file (`jpeg2png`), or a PNG input file is converted to a JPEG 
(`png2jpeg`).

Loaded images never have transparency.  The first step in loading is to
drop transparency information, if present.  If the input color model is
`graya` or `rgba`, then another image is created with the same
dimensions and color model `gray` or `rgb` respectively, and filled
with opaque white.  The transparent image is then composed on top of
this image, resulting in a image with no transparency.

The second step in loading is to scale if necessary.  Two profiles are
defined, full-sized and thumb-sized.  Database configuration variables
determine the maximum pixel count in full-profile and thumb-profile
images.  If the input image is within the thumb-profile size, then only
the full-profile image will be generated and the thumb-profile image
will be `undef` indicating that it is the same as the full-profile
image.

The third step is to apply rotation by 90-degree increments, if
specified to the loading function.  This is useful for JPEG files that
have an orientation field, so the orientation can be corrected.

The fourth step is to encode the image.  All input images are re-encoded
to ensure consistent encoding across all images.  For JPEG images, the
encoding quality is determined by a database configuration variable.

# CONSTRUCTOR

- **configure(dbc)**

    Construct a new `SpeakEasy::Image` instance based on configuration
    information read from the given `SpeakEasy::DB` connection.

    The configuration information is stored in the `vars` table of the
    database.  The following variables are relevant:

    `image_full_pixels` stores an unsigned decimal integer in range
    \[1, 1999999999\] that indicates the maximum number of total pixels
    allowed within full-scale images.

    `image_thumb_pixels` stores an unsigned decimal integer in range
    \[1, 1999999999\] that indicates the maximum number of total pixels
    allowed within thumb-scale images.

    `image_jpeg_quality` stores an unsigned decimal integer in range
    \[1, 100\] that indicates the JPEG quality to use for JPEG images.

# INSTANCE METHODS

- **load(path, format, rotate)**

    Load an image and apply any necessary transformations and encodings.

    `path` is the path to the image to load.

    `format` is the type of image to load.  This can be `jpeg` or `png`.
    It can also be `jpeg2png` or `png2jpeg` if you want to transcode from
    one format to another.

    `rotate` is the amount of clockwise rotation needed, in degrees.  It
    must be either 0, 90, 180, or 270.

    The return value in list context has two elements.  The first element is
    a binary string storing the full binary image at full-size profile.  The
    second element is a binary string storing the full binary image at
    thumb-size profile, or it is `undef` if the full-size profile also
    works for the thumb-size profile.

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
