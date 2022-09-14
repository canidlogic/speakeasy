#!/usr/bin/env perl
use strict;
use warnings;

# SpeakEasy imports
use SpeakEasy::Datafile;

# Core imports
use Encode qw( decode );

=head1 NAME

speakeasy_picscan.pl - Generate a script for speakeasy_pic by scanning
directories.

=head1 SYNOPSIS

  ./speakeasy_picscan.pl scan.script /base/path/
  ./speakeasy_picscan.pl scan.script /base/path/ -forcejpg

=head1 DESCRIPTION

This script performs directory scanning to generate a script that can
then be fed into the C<speakeasy_pic.pl> script.

The first argument is the path to a text file that defines what to scan.
See below for the format of the text file.

The second argument is the base path to start scanning in.  It must end
with a forward slash.  You will need to use this same base path when
running the C<speakeasy_pic.pl> script on the generated script.

The optional third argument is C<-forcejpg>.  If present, every single
C<pic> command in the generated script will have a C<Target-Type>
property that is set to C<jpeg>.  This will cause everything to get
transcoded to JPEG when it is imported into the database.

=head2 Scanning file format

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
slashes next to each other.  None of the directory names may be C<.> or
C<..>

The second line is the path to a node in the SpeakEasy database.  It has
the same format as the first line.  It is always relative to the root of
the node tree, such that the first directory name in the path is the
root directory in the node tree.

Each record is transformed into a sequence of instructions in the
generated script.  The first set of instructions positions the current
directory of the file system in the given directory and the current
directory of the SpeakEasy database in the other given directory.  Then,
there are a sequence of C<pic> instructions to import all the images
that are found in that directory during scanning.  The next set of
instructions for each record returns the current directory of the file
system and the current directory of the SpeakEasy database back to their
initial states.  The final set of instructions for each record is a
recursive invocation to process any subdirectories, using subdirectories
with matching names in the SpeakEasy database as well.

During scanning, the only entities that should be encountered are either
regular files that have a C<.jpg> C<.jpeg> or C<.png> extension (case
insensitive), or subdirectories.  If anything else is encountered, a
warning will be printed to standard error but otherwise the entity will
be skipped and processing will continue.

=cut

# =========
# Constants
# =========

# Maximum recursive depth for entering subdirectories.
#
my $MAX_DEPTH = 1024;

# ===============
# Local functions
# ===============

# verify_recdir(str, lnum)
# ------------------------
#
# Check whether a given string is a valid directory line in an input
# record.
#
# Valid lines have at least one and at most 1024 characters, and do not
# end with a whitespace character.
#
# Valid lines have neither first nor last character as forward slash,
# and never have two forward slashes in a row.
#
# Valid lines never have . or .. as directory names.
#
# Fatal errors occur if the line is not valid.  lnum is the line number
# to report in case of error.
#
sub verify_recdir {
  # Get parameters
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  my $str = shift;
  (not ref($str)) or die "Wrong parameter type, stopped";
  $str = "$str";
  
  my $lnum = shift;
  (not ref($lnum)) or die "Wrong parameter type, stopped";
  $lnum = int($lnum);
  
  # Check basic format
  ($str =~ /\A.{0,1023}\S\z/) or
    die "Line $lnum: At most 1024 characters in a path, stopped";
  
  # Check slashes
  ((not ($str =~ /\A\//)) and (not ($str =~ /\/\z/))) or
    die "Line $lnum: Path can't start or end with slash, stopped";
  (not ($str =~ /\/\//)) or
    die "Line $lnum: Path can't have consecutive slashes, stopped";
  
  # Check each component
  for my $comp (split /\//, $str) {
    ($comp ne '.') or
      die "Line $lnum: Can't use . as directory name, stopped";
    ($comp ne '..') or
      die "Line $lnum: Can't use .. as directory name, stopped";
  }
}

# proc_dir(fsdir, dbdir, base_path, force_jpg, lnum, depth)
# ---------------------------------------------------------
#
# Recursive function to generate pic script instructions and write them
# to standard output.
#
# fsdir is the subdirectory trail in the file system.  dbdir is the
# subdirectory trail in the SpeakEasy database.  Both must pass the
# function verify_recdir.
#
# base_path is the base path in the file system.  It must end in a
# forward slash.
#
# force_jpg is 1 if each scanned result should be forced into JPEG
# format when entered in the database, 0 if not.
#
# lnum is the first line of the record that is being processed, for sake
# of diagnostic reports.
#
# depth is the recursive depth.  Set it to zero when calling for the
# first time.
#
sub proc_dir {
  # Get parameters
  ($#_ == 5) or die "Wrong number of parameters, stopped";
  
  my $fsdir     = shift;
  my $dbdir     = shift;
  my $base_path = shift;
  my $force_jpg = shift;
  my $lnum      = shift;
  my $depth     = shift;
  
  (not ref($base_path)) or die "Wrong parameter type, stopped";
  $base_path = "$base_path";
  ($base_path =~ /\/\z/) or die "Invalid base path, stopped";
  
  (not ref($force_jpg)) or die "Wrong parameter type, stopped";
  if ($force_jpg) {
    $force_jpg = 1;
  } else {
    $force_jpg = 0;
  }
  
  (not ref($lnum)) or die "Wrong parameter type, stopped";
  $lnum = int($lnum);
  
  (not ref($depth)) or die "Wrong parameter type, stopped";
  $depth = int($depth);
  
  verify_recdir($fsdir, $lnum);
  verify_recdir($dbdir, $lnum + 1);
  
  # Check recursive depth restriction
  ($depth <= $MAX_DEPTH) or
    die "Record $lnum: Recursive scanning depth exceeded, stopped";
  
  # Generate paths to undo the filesystem and database paths
  my $fsundo = '';
  for my $a (split /\//, $fsdir) {
    if (length($fsundo) < 1) {
      $fsundo = '..';
    } else {
      $fsundo = $fsundo . '/..';
    }
  }
  
  my $dbundo = '';
  for my $a (split /\//, $dbdir) {
    if (length($dbundo) < 1) {
      $dbundo = '..';
    } else {
      $dbundo = $dbundo . '/..';
    }
  }
  
  # Start subdirectory array out empty
  my @subdirs;
  
  # Get file system directory path and check that it exists as directory
  my $fs_path = $base_path . $fsdir;
  (-d $fs_path) or die "Can't find directory '$fs_path', stopped";
  
  # Open directory for iteration
  opendir(my $dh, $fs_path) or
    die "Failed to read directory '$fs_path', stopped";
  
  # Print commands to enter directories
  print "dbcd $dbdir\n\n";
  print "fscd $fsdir\n\n";
  
  # Iterate through all directory entries
  for(my $ent = readdir($dh); defined $ent; $ent = readdir($dh)) {
    # Attempt to decode file name as UTF-8, then fall back to CP-1250
    # (Latin-1) if that fails
    eval {
      $ent = decode('UTF-8', $ent,
                Encode::FB_CROAK | Encode::LEAVE_SRC);
    };
    if ($@) {
      $ent = decode('CP1250', $ent,
                Encode::FB_CROAK | Encode::LEAVE_SRC);
    }
    
    # Skip the '.' and '..' entries
    if (($ent eq '.') or ($ent eq '..')) {
      next;
    }
    
    # Get full path to entity
    my $full_path = $fs_path . '/' . $ent;
    
    # Handle types of entity
    if (-f $full_path) {
      # Regular file, verify known extension
      if ($ent =~ /\.(?:jpg|jpeg|png)\z/i) {
        # Verify entity doesn't begin with whitespace
        if ($ent =~ /\A\S/) {
          # Entity is fine, so add the pic command
          print "pic $ent\n";
          
          # If force_jpg, then add target type
          if ($force_jpg) {
            print "Target-Type: jpeg\n";
          }
          
          # Blank line to end record
          print "\n";
        } else {
          # Entity begins with whitespace, so warn and don't process
          warn "Warning: Whitespace begins in '$full_path', skipped\n";
        }
        
      } else {
        # Unknown extension, so warn and don't process
        warn "Warning: Unknown extension for '$full_path', skipped\n";
      }
      
    } elsif (-d $full_path) {
      # Subdirectory, so add the entity to the subdirectory list after
      # checking it doesn't begin or end with whitespace
      if (($ent =~ /\A\S/) and ($ent =~ /\S\z/)) {
        push @subdirs, ($ent);
      } else {
        warn "Warning: Invalid whitespace in '$full_path', skipped\n";
      }
      
    } else {
      # Neither regular file nor directory
      warn "Warning: Unsupported entity type at '$full_path'\n";
    }
  }
  
  # Print commands to go back to base directories
  print "fscd $fsundo\n\n";
  print "dbcd $dbundo\n\n";
  
  # Close directory
  closedir($dh) or die "Failed to close directory iteration, stopped";
  
  # Now recursively process any subdirectories we found
  for my $sdir (@subdirs) {
    my $fssub = $fsdir . '/' . $sdir;
    my $dbsub = $dbdir . '/' . $sdir;
    proc_dir($fssub, $dbsub, $base_path, $force_jpg, $lnum, $depth + 1);
  }
}

# ==================
# Program entrypoint
# ==================

# Set UTF-8 output and warnings
#
binmode(STDOUT, ":encoding(UTF-8)") or
  die "Failed to set UTF-8 output, stopped";
binmode(STDERR, ":encoding(UTF-8)") or
  die "Failed to set UTF-8 diagnostics, stopped";

# Check that we got two or three arguments
#
(($#ARGV == 1) or ($#ARGV == 2)) or
  die "Wrong number of program arguments, stopped";

# Get and check arguments
#
my $data_path = $ARGV[0];
my $base_dir  = $ARGV[1];
my $force_jpg = 0;

(-f $data_path) or die "Can't find file '$data_path', stopped";
($base_dir =~ /\/\z/) or
  die "Base directory must end with forward slash, stopped";

if ($#ARGV >= 2) {
  ($ARGV[2] eq '-forcejpg') or
    die "Unrecognized option $ARGV[2], stopped";
  $force_jpg = 1;
}

# Load the data file
#
my $dr = SpeakEasy::Datafile->load($data_path);

# Process each line
#
my $rec = undef;
my $rec_line = undef;

while (1) {
  # Attempt to read another line
  my $retval = $dr->advance;
  
  # Check whether we are at end of file, or line is blank, or line is
  # not blank
  if ((not $retval) or ($dr->text =~ /\A\s*\z/)) {
    # Blank line or end of file, so process buffered record if defined
    if (defined $rec) {
      # Check for required length
      (scalar(@$rec) == 2) or
        die "Record $rec_line: Must have two lines in record, stopped";
      
      # Process the directory
      proc_dir(
        $rec->[0],
        $rec->[1],
        $base_dir,
        $force_jpg,
        $rec_line,
        0);
      
      # Finished processing, so reset buffered record to undefined
      $rec = undef;
      $rec_line = undef;
    }
    
  } else {
    # Non-blank line, so begin by defining a new record if none defined
    # yet
    if (not defined $rec) {
      $rec = [];
      $rec_line = $dr->line_number;
    }
    
    # Check that less than two lines buffered
    (scalar(@$rec) < 2) or
      die sprintf("Line %d: Too many lines in record, stopped",
                  $dr->line_number);
    
    # Get the line and trim trailing whitespace and line breaks
    my $ltext = $dr->text;
    chomp $ltext;
    $ltext =~ s/\s+\z//;
    
    # Verify this line
    verify_recdir($ltext, $dr->line_number);
    
    # Add this directory to buffer
    push @$rec, ($ltext);
  }
  
  # Leave loop if we read the end of the file
  unless ($retval) {
    last;
  }
}

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
