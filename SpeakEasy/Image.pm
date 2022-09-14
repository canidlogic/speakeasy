package SpeakEasy::Image;
use strict;

# SpeakEasy imports
use SpeakEasy::DB;

# Non-core dependencies
use Imager;

=head1 NAME

SpeakEasy::Image - Manage image transformations and transcoding for
SpeakEasy.

=head1 SYNOPSIS

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

=head1 DESCRIPTION

Module that handles loading and transcoding images as necessary before
they will be stored in a SpeakEasy database.

The constructor gets configuration information from a SpeakEasy
database.  See the constructor for further information.

The C<load> function can then load a full image file into a binary
string, applying any necessary transformations and transcodings.

Two formats are supported for loading, C<jpeg> and C<png>.  It is also
possible to transcode, such that a JPEG input file is converted to a PNG
file (C<jpeg2png>), or a PNG input file is converted to a JPEG 
(C<png2jpeg>).

Loaded images never have transparency.  The first step in loading is to
drop transparency information, if present.  If the input color model is
C<graya> or C<rgba>, then another image is created with the same
dimensions and color model C<gray> or C<rgb> respectively, and filled
with opaque white.  The transparent image is then composed on top of
this image, resulting in a image with no transparency.

The second step in loading is to scale if necessary.  Two profiles are
defined, full-sized and thumb-sized.  Database configuration variables
determine the maximum pixel count in full-profile and thumb-profile
images.  If the input image is within the thumb-profile size, then only
the full-profile image will be generated and the thumb-profile image
will be C<undef> indicating that it is the same as the full-profile
image.

The third step is to apply rotation by 90-degree increments, if
specified to the loading function.  This is useful for JPEG files that
have an orientation field, so the orientation can be corrected.

The fourth step is to encode the image.  All input images are re-encoded
to ensure consistent encoding across all images.  For JPEG images, the
encoding quality is determined by a database configuration variable.

=head1 CONSTRUCTOR

=over 4

=item B<configure(dbc)>

Construct a new C<SpeakEasy::Image> instance based on configuration
information read from the given C<SpeakEasy::DB> connection.

The configuration information is stored in the C<vars> table of the
database.  The following variables are relevant:

C<image_full_pixels> stores an unsigned decimal integer in range
[1, 1999999999] that indicates the maximum number of total pixels
allowed within full-scale images.

C<image_thumb_pixels> stores an unsigned decimal integer in range
[1, 1999999999] that indicates the maximum number of total pixels
allowed within thumb-scale images.

C<image_jpeg_quality> stores an unsigned decimal integer in range
[1, 100] that indicates the JPEG quality to use for JPEG images.

=cut

sub configure {
  
  # Check parameter count
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  # Get invocant and parameter
  my $invocant = shift;
  my $class = ref($invocant) || $invocant;
  
  my $dbc = shift;
  (ref($dbc) and ($dbc->isa('SpeakEasy::DB'))) or
    die "Wrong parameter type, stopped";
  
  # Define the new object
  my $self = { };
  bless($self, $class);
  
  # Read all image_ configuration variables
  $self->{'_config'} = {};
  
  my $dbh = $dbc->beginWork('r');
  my $qr = $dbh->selectall_arrayref(
    "SELECT varskey, varsval FROM vars WHERE varskey GLOB 'image_*'");
  if (defined $qr) {
    for my $rec (@$qr) {
      # Get current key/value pair
      my $key = $rec->[0];
      my $val = $rec->[1];
      
      # Only handle relevant keys
      if (($key eq 'image_full_pixels')
          or ($key eq 'image_thumb_pixels')
          or ($key eq 'image_jpeg_quality')) {
        
        # Convert value to integer
        ($val =~ /\A1?[0-9]{1,9}\z/) or
          die "Invalid value for configuration variable $key, stopped";
        my $nval = int($val);
        
        # Check range
        if ($key eq 'image_jpeg_quality') {
          (($nval > 0) and ($nval <= 100)) or
            die "Configuration variable $key out of range, stopped";
          
        } else {
          ($nval > 0) or
            die "Configuration variable $key out of range, stopped";
        }
        
        # Store in configuration area
        $self->{'_config'}->{$key} = $nval;
      }
    }
  }
  $dbc->finishWork;
  
  # Check that necessary configuration variables were present
  for my $pname ('image_full_pixels', 'image_thumb_pixels',
                  'image_jpeg_quality') {
    (defined $self->{'_config'}->{$pname}) or
      die "Missing configuration variable '$pname', stopped";
  }
  
  # Return the new object
  return $self;
}

=back

=head1 INSTANCE METHODS

=over 4

=item B<load(path, format, rotate)>

Load an image and apply any necessary transformations and encodings.

C<path> is the path to the image to load.

C<format> is the type of image to load.  This can be C<jpeg> or C<png>.
It can also be C<jpeg2png> or C<png2jpeg> if you want to transcode from
one format to another.

C<rotate> is the amount of clockwise rotation needed, in degrees.  It
must be either 0, 90, 180, or 270.

The return value in list context has two elements.  The first element is
a binary string storing the full binary image at full-size profile.  The
second element is a binary string storing the full binary image at
thumb-size profile, or it is C<undef> if the full-size profile also
works for the thumb-size profile.

=cut

sub load {
  
  # Check parameter count
  ($#_ == 3) or die "Wrong number of parameters, stopped";
  
  # Get self and parameters
  my $self = shift;
  (ref($self) and $self->isa(__PACKAGE__)) or
    die "Wrong parameter type, stopped";
  
  my $path = shift;
  (not ref($path)) or die "Wrong parameter type, stopped";
  (-f $path) or die "Can't find file '$path', stopped";
  
  my $fmt = shift;
  (not ref($fmt)) or die "Wrong parameter type, stopped";
  (($fmt eq 'jpeg') or ($fmt eq 'png') or
    ($fmt eq 'jpeg2png') or ($fmt eq 'png2jpeg')) or
    die "Unrecognized image format type '$fmt', stopped";
  
  my $rotate = shift;
  (not ref($rotate)) or die "Wrong parameter type, stopped";
  $rotate = "$rotate";
  (($rotate eq '0') or ($rotate eq '90') or
    ($rotate eq '180') or ($rotate eq '270')) or
    die "Invalid rotation setting, stopped";
  $rotate = int($rotate);
 
  # Load the source image
  my $src_fmt;
  if (($fmt eq 'jpeg') or ($fmt eq 'jpeg2png')) {
    $src_fmt = 'jpeg';
  } elsif (($fmt eq 'png') or ($fmt eq 'png2jpeg')) {
    $src_fmt = 'png';
  } else {
    die "Unexpected";
  }
  
  my $src_image = Imager->new();
  if ($src_fmt eq 'png') {
    # For PNG, avoid benign errors such as incorrect sRGB profile
    $src_image->read(
        file => $path,
        type => $src_fmt,
        png_ignore_benign_errors => 1) or
      die sprintf("Failed to decode image '%s' because '%s', stopped",
                    $path, $src_image->errstr);
  } else {
    $src_image->read(file => $path, type => $src_fmt) or
      die sprintf("Failed to decode image '%s' because '%s', stopped",
                    $path, $src_image->errstr);
  }
  
  # If the source image has transparency, we need to compose it over an
  # opaque white background; otherwise, composed image is same as source
  # image
  my $comp_image;
  if ($src_image->colormodel eq 'graya') {
    # Source image has grayscale and alpha, so composite it and then
    # release the source image
    $comp_image = Imager->new(
                    xsize => $src_image->getwidth,
                    ysize => $src_image->getheight,
                    model => 'gray') or
      die "Failed to create compositing image, stopped";
    $comp_image->box(filled => 1, color => 'white');
    $comp_image->rubthrough(
                    src => $src_image,
                    tx  => 0,
                    ty  => 0) or
      die "Failed to composite image, stopped";
    
    $src_image->img_set(xsize => 4, ysize => 4);
    
  } elsif ($src_image->colormodel eq 'rgba') {
    # Source image has RGB and alpha, so composite it and then release
    # the source image
    $comp_image = Imager->new(
                    xsize => $src_image->getwidth,
                    ysize => $src_image->getheight,
                    model => 'rgb') or
      die "Failed to create compositing image, stopped";
    $comp_image->box(filled => 1, color => 'white');
    $comp_image->rubthrough(
                    src => $src_image,
                    tx  => 0,
                    ty  => 0) or
      die "Failed to composite image, stopped";
    
    $src_image->img_set(xsize => 4, ysize => 4);
    
  } elsif (($src_image->colormodel eq 'gray') or
            ($src_image->colormodel eq 'rgb')) {
    # Source image has no alpha channel, so use that
    $comp_image = $src_image;
  
  } else {
    die "Unknown color model for '$path', stopped";
  }
  
  # Compute the total number of pixels in the composited image
  my $original_pixels = $comp_image->getwidth * $comp_image->getheight;
  
  # If total number of pixels exceeds full-size limit, we need to scale
  # the image; otherwise, skip full-size scaling
  my $full_image;
  if ($original_pixels > $self->{'_config'}->{'image_full_pixels'}) {
    # We need to scale, so get greater and lesser dimensions
    my $greater = $comp_image->getwidth;
    my $lesser  = $comp_image->getheight;
    if ($lesser > $greater) {
      $greater = $comp_image->getheight;
      $lesser  = $comp_image->getwidth;
    }
    ($greater >= $lesser) or die "Unexpected";
    
    # Let x be greater dimension, then:
    #
    #   x * (x * lesser / greater) = limit
    #                          x^2 = limit * greater / lesser
    #                            x = SQRT(limit * greater / lesser)
    #
    # Now compute dimensions:
    
    my $target_greater = sqrt(
                          ($self->{'_config'}->{'image_full_pixels'}
                            * $greater) / $lesser);
    my $target_lesser  = ($target_greater * $lesser) / $greater;
    
    $target_greater = int($target_greater);
    $target_lesser  = int($target_lesser);
    
    # Make sure each dimension at least two
    if ($target_greater < 2) {
      $target_greater = 2;
    }
    if ($target_lesser < 2) {
      $target_lesser = 2;
    }
    
    # Now get target dimensions
    my $target_width  = $target_greater;
    my $target_height = $target_lesser;
    if ($comp_image->getheight > $comp_image->getwidth) {
      $target_height = $target_greater;
      $target_width  = $target_lesser;
    }
    
    # Perform scaling
    $full_image = $comp_image->scale(
                      xpixels => $target_width,
                      ypixels => $target_height,
                      type    => 'nonprop');
    (defined $full_image) or
      die "Failed to scale image, stopped";
    
    # In this case, we can now release the composited image
    $comp_image->img_set(xsize => 4, ysize => 4);
    
  } else {
    # No scaling needed, so just use composited image
    $full_image = $comp_image;
  }
  
  # If rotation is required, perform that now
  my $rot_image;
  if ($rotate > 0) {
    # Perform the rotation
    $rot_image = $full_image->rotate(right => $rotate);
    (defined $rot_image) or
      die "Failed to rotate image, stopped";
    
    # In this case, we can now release the full-size image
    $full_image->img_set(xsize => 4, ysize => 4);
    
  } else {
    # No rotation needed, so just use full-size image
    $rot_image = $full_image;
  }
  
  # Compute the total number of pixels in the rotated image
  my $full_pixels = $rot_image->getwidth * $rot_image->getheight;
  
  # If total number of pixels in full-size exceeds thumb-size limit, we
  # need to scale the image into a thumbnail copy; otherwise, set the
  # thumbnail to undef
  my $thumb_image = undef;
  if ($full_pixels > $self->{'_config'}->{'image_thumb_pixels'}) {
    # We need to scale, so get greater and lesser dimensions
    my $greater = $rot_image->getwidth;
    my $lesser  = $rot_image->getheight;
    if ($lesser > $greater) {
      $greater = $rot_image->getheight;
      $lesser  = $rot_image->getwidth;
    }
    ($greater >= $lesser) or die "Unexpected";
    
    # Let x be greater dimension, then:
    #
    #   x * (x * lesser / greater) = limit
    #                          x^2 = limit * greater / lesser
    #                            x = SQRT(limit * greater / lesser)
    #
    # Now compute dimensions:
    
    my $target_greater = sqrt(
                          ($self->{'_config'}->{'image_thumb_pixels'}
                            * $greater) / $lesser);
    my $target_lesser  = ($target_greater * $lesser) / $greater;
    
    $target_greater = int($target_greater);
    $target_lesser  = int($target_lesser);
    
    # Make sure each dimension at least two
    if ($target_greater < 2) {
      $target_greater = 2;
    }
    if ($target_lesser < 2) {
      $target_lesser = 2;
    }
    
    # Now get target dimensions
    my $target_width  = $target_greater;
    my $target_height = $target_lesser;
    if ($rot_image->getheight > $rot_image->getwidth) {
      $target_height = $target_greater;
      $target_width  = $target_lesser;
    }
    
    # Perform scaling
    $thumb_image = $rot_image->scale(
                      xpixels => $target_width,
                      ypixels => $target_height,
                      type    => 'nonprop');
    (defined $thumb_image) or
      die "Failed to scale image, stopped";
    
    # Do NOT release source image this time, because we need to keep it
    # around
  }
  
  # rot_image now has our full-size image, and thumb_image has our
  # thumbnail image, or undef if a separate thumbnail is not required;
  # time to write the image files
  my $output_fmt;
  if (($fmt eq 'jpeg') or ($fmt eq 'png2jpeg')) {
    $output_fmt = 'jpeg';
  } elsif (($fmt eq 'png') or ($fmt eq 'jpeg2png')) {
    $output_fmt = 'png';
  } else {
    die "Unexpected";
  }
  
  my $binary_full  = '';
  my $binary_thumb = '';
  
  if ($output_fmt eq 'jpeg') {
    $rot_image->write(
                  data        => \$binary_full,
                  type        => $output_fmt,
                  jpegquality =>
                    $self->{'_config'}->{'image_jpeg_quality'})
      or die "Failed to transcode image, stopped";
    
    if (defined $thumb_image) {
      $thumb_image->write(
                    data        => \$binary_thumb,
                    type        => $output_fmt,
                    jpegquality =>
                      $self->{'_config'}->{'image_jpeg_quality'})
        or die "Failed to transcode image, stopped";
    } else {
      $binary_thumb = undef;
    }
      
  } else {
    $rot_image->write(
                  data => \$binary_full,
                  type => $output_fmt)
      or die "Failed to transcode image, stopped";
    
    if (defined $thumb_image) {
      $thumb_image->write(
                    data => \$binary_thumb,
                    type => $output_fmt)
        or die "Failed to transcode image, stopped";
    } else {
      $binary_thumb = undef;
    }
  }
  
  # Return transcoded images
  return ($binary_full, $binary_thumb);
}

=back

=head1 AUTHOR

Noah Johnson, C<noah.johnson@loupmail.com>

=head1 COPYRIGHT AND LICENSE

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

=cut

# End with something that evaluates to true
#
1;
