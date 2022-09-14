#!/usr/bin/env perl
use strict;
use warnings;

# SpeakEasy imports
use SpeakEasy::Datafile;
use SpeakEasy::DB;
use SpeakEasy::Image;

# Non-core imports
use DBI qw(:sql_types);

=head1 NAME

speakeasy_pic.pl - Batch import images into a SpeakEasy database.

=head1 SYNOPSIS

  ./speakeasy_pic.pl db.sqlite script.txt /base/dir/

=head1 DESCRIPTION

This script is used to batch import a number of images into a SpeakEasy
database.

Before using this script, you must set up the C<jpeg> and C<png> types
in the C<rtype> table using C<speakeasy_types.pl>.  You only need
C<jpeg> if you will be storing JPEG files in the database, and you only
need C<png> if you will be storing PNG files in the database.

Before using this script, you must also set up the configuration
variables in the C<vars> table that are required by the module
C<SpeakEasy::Image>.  See the documentation of that module for further
information.

The first argument is the SpeakEasy database to configure.  The second
argument is the path to a text file to use as a batch script.  See below
for the format of the text file batch script.  The third argument is the
base directory in the file system against which file system directories
in the batch script are resolved.  It must end with a forward slash.

=head2 Batch script file format

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
base directory given on the command line.  There is also a current
directory in the database, which starts out at the root level and not in
any subdirectories.

To change the file system current directory, use C<fscd> and supply the
name of a subdirectory in the current directory, or C<..> to go up one
level.  If you specify multiple names separated by slashes, the effect
is equivalent to a sequence of C<fscd> commands in order of the names
given.

To change the database current directory, use C<dbcd> and supply the
name of a subdirectory in the current directory, or C<..> to go up one
level.  Directories that do not exist will be created as new nodes.  The
first C<dbcd> must be into the root directory.  Specifying multiple
names separated by slashes is equivalent in effect to a sequence of
C<dbcd> commands in order of the names given.

To import a picture from the current file system directory into the
current database node, use C<pic> and supply the name of a file relative
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

The only recognized property names are on the C<pic> command.

Property C<Source-Type> may be either C<jpeg> or C<png>, defining the
type of image the source file is.  If not specified, the end of the
filename given in the C<pic> command must be a case-insensitive match
for C<.JPG> C<.JPEG> or C<.PNG> and that will then determine the file
type.

Property C<Target-Type> may be either C<jpeg> or C<png>.  If not
specified, the target type will be the same as the source type.  Use
this property if you want to convert a source JPEG into a PNG in the
database, or a source PNG into a JPEG in the database.

Property C<Clockwise> may be either C<0> C<90> C<180> or C<270>
indicating a clockwise rotation in degrees.  If not specified, it
defaults to zero.

Property C<Name> is a sequence of one to 255 Unicode codepoints that
neither begins nor ends with whitespace.  It represents the name that
will be recorded for this picture in the database.  If not specified, it
defaults to the filename, without any C<.JPG> C<.JPEG> or C<.PNG>
extension.

Property C<Desc> is a sequence of one or more Unicode codepoints that
neither begins nor ends with whitespace.  There may be multiple C<Desc>
properties in a single record, in which case subsequent C<Desc>
properties are concatenated to the end of preceding C<Desc> records,
separated from the preceding record with a space.

Each record is executed in a separate database transaction, so if there
is a failure, every successful transaction up to the point of failure
will be commited.

For the C<pic> command, if a picture with matching name already exists
in a node, the command is skipped.  This allows you to retry scripts
that failed midway through.

=cut

# ==========
# Local data
# ==========

# The base path to resolve paths in the @fs_stack against.
#
# This must end with a slash.  It is set at the entrypoint of the
# script.
#
my $base_path;

# The file system directory stack.
#
# This begins empty, meaning the base path.
#
# Each time a subdirectory is entered, its name is pushed onto the
# stack.  Each time a subdirectory is left, its name is popped from the
# stack.
#
my @fs_stack;

# The database directory stack.
#
# This begins empty, meaning the root and not in any node.
#
# Each time a node is entered, its nodeid is pushed onto the stack.
# Each time a node is left, its nodeid is popped from the stack.
#
my @db_stack;

# ===============
# Local functions
# ===============

# fscd(path, lnum)
# ----------------
#
# Interpret a "fscd" command.
#
sub fscd {
  # Get parameters
  ($#_ == 1) or die "Wrong number of parameters, stopped";
  
  my $path = shift;
  (not ref($path)) or die "Wrong parameter type, stopped";
  
  my $lnum = shift;
  (not ref($lnum)) or die "Wrong parameter type, stopped";
  $lnum = int($lnum);
  
  # If there are any slashes in the path, recursively interpret each
  # command and then return
  if ($path =~ /\//) {
    # Check that neither first nor last character is slash
    ((not ($path =~ /\A\//)) and
      (not ($path =~ /\/\z/))) or
      die "Record $lnum: Path can't begin or end with slash, stopped";
    
    # Check that no two slashes in a row
    (not ($path =~ /\/\//)) or
      die "Record $lnum: Can't have two slashes in a row, stopped";
    
    # Split on slashes
    my @comp = split /\//, $path;
    
    # Recursively handle each component
    for my $a (@comp) {
      fscd($a, $lnum);
    }
    
    # Now we can return
    return;
  }
  
  # If we got here, no slashes in path; next, handle the special ".."
  # and "." cases
  if ($path eq '.') {
    # Do nothing and return in this case
    return;
  
  } elsif ($path eq '..') {
    # Make sure at least one directory on stack
    ($#fs_stack >= 0) or
      die "Record $lnum: Can't travel out of current tree, stopped";
    
    # Pop directory off stack and return
    pop @fs_stack;
    return;
  }
  
  # If we got here, then add the directory to the stack
  push @fs_stack, ($path);
}

# dbcd(path, dbc, lnum)
# ---------------------
#
# Interpret a "dbcd" command.
#
sub dbcd {
  # Get parameters
  ($#_ == 2) or die "Wrong number of parameters, stopped";
  
  my $path = shift;
  (not ref($path)) or die "Wrong parameter type, stopped";
  
  my $dbc = shift;
  (ref($dbc) and ($dbc->isa('SpeakEasy::DB'))) or
    die "Wrong parameter type, stopped";
  
  my $lnum = shift;
  (not ref($lnum)) or die "Wrong parameter type, stopped";
  $lnum = int($lnum);
  
  # If there are any slashes in the path, recursively interpret each
  # command and then return
  if ($path =~ /\//) {
    # Check that neither first nor last character is slash
    ((not ($path =~ /\A\//)) and
      (not ($path =~ /\/\z/))) or
      die "Record $lnum: Path can't begin or end with slash, stopped";
    
    # Check that no two slashes in a row
    (not ($path =~ /\/\//)) or
      die "Record $lnum: Can't have two slashes in a row, stopped";
    
    # Split on slashes
    my @comp = split /\//, $path;
    
    # Recursively handle each component
    for my $a (@comp) {
      dbcd($a, $dbc, $lnum);
    }
    
    # Now we can return
    return;
  }
  
  # If we got here, no slashes in path; next, handle the special ".."
  # and "." cases
  if ($path eq '.') {
    # Do nothing and return in this case
    return;
  
  } elsif ($path eq '..') {
    # Make sure at least one directory on stack
    ($#db_stack >= 0) or
      die "Record $lnum: Can't travel out of current tree, stopped";
    
    # Pop directory off stack and return
    pop @db_stack;
    return;
  }
  
  # If we got here, then we need to enter a directory; check whether we
  # are currently in a directory
  my $dbh = $dbc->beginWork('rw');
  if ($#db_stack >= 0) {
    # We are in some node, so we will be entering a subdirectory; get
    # the current node ID
    my $current = $db_stack[-1];
    
    # Check whether we already have the given directory
    my $new_id = undef;
    my $qr = $dbh->selectrow_arrayref(
      'SELECT nodeid FROM node WHERE nodesuper=? AND nodename=?',
      undef,
      $current, SpeakEasy::DB->string_to_db($path));
    if (defined $qr) {
      $new_id = $qr->[0];
    }
    
    # If we didn't find an existing directory, add a new one
    if (not defined $new_id) {
      my $max_id = 0;
      $qr = $dbh->selectrow_arrayref(
        'SELECT nodeid FROM node ORDER BY nodeid DESC');
      if (defined $qr) {
        $max_id = $qr->[0];
      }
      
      $new_id = $max_id + 1;
      
      $dbh->do(
        'INSERT INTO node (nodeid, nodename, nodesuper) '
        . 'VALUES (?, ?, ?)',
        undef,
        $new_id,
        SpeakEasy::DB->string_to_db($path),
        $current);
    }
    
    # Push the new node ID onto the stack
    push @db_stack, ($new_id);
  
  } else {
    # We are not currently in a directory, so we will be entering the
    # root directory; check if there is a root directory defined
    my $root_id   = undef;
    my $root_name = undef;
    
    my $qr = $dbh->selectrow_arrayref(
      'SELECT nodeid, nodename FROM node WHERE nodesuper ISNULL');
    if (defined $qr) {
      $root_id   = $qr->[0];
      $root_name = SpeakEasy::DB->db_to_string($qr->[1]);
    }
    
    # If root name defined, make sure same name was provided
    if (defined $root_name) {
      ($root_name eq $path) or
        die "Record $lnum: Root node does not match database, stopped";
    }
    
    # If root ID not defined, then add the root record
    if (not defined $root_id) {
      my $max_id = 0;
      $qr = $dbh->selectrow_arrayref(
        'SELECT nodeid FROM node ORDER BY nodeid DESC');
      if (defined $qr) {
        $max_id = $qr->[0];
      }
      
      $root_id = $max_id + 1;
      
      $dbh->do(
        'INSERT INTO node (nodeid, nodename) VALUES (?, ?)',
        undef,
        $root_id, SpeakEasy::DB->string_to_db($path));
    }
    
    # Push root ID onto stack
    push @db_stack, ($root_id);
  }
  $dbc->finishWork;
}

# pic(path, dbc, attrib, lnum)
# ----------------------------
#
# Interpret a "pic" command.
#
sub pic {
  # Get parameters
  ($#_ == 3) or die "Wrong number of parameters, stopped";
  
  my $path = shift;
  (not ref($path)) or die "Wrong parameter type, stopped";
  
  my $dbc = shift;
  (ref($dbc) and ($dbc->isa('SpeakEasy::DB'))) or
    die "Wrong parameter type, stopped";
  
  my $attr = shift;
  (ref($attr) eq 'HASH') or die "Wrong parameter type, stopped";
  
  my $lnum = shift;
  (not ref($lnum)) or die "Wrong parameter type, stopped";
  $lnum = int($lnum);
  
  # Form the full path to the image
  my $image_path;
  if (($#fs_stack >= 0) and (not ($path =~ /\A\//))) {
    $image_path = join('/', @fs_stack) . '/' . $path;
  } else {
    $image_path = $path;
  }
  
  # Attempt to auto-detect a source type from the path
  my $src_type = undef;
  if (($path =~ /\.jpg\z/i) or ($path =~ /\.jpeg\z/i)) {
    $src_type = 'jpeg';
  
  } elsif ($path =~ /\.png\z/i) {
    $src_type = 'png';
  }
  
  # Set explicit source type if given
  if (defined $attr->{'Source-Type'}) {
    $src_type = $attr->{'Source-Type'};
    (($src_type eq 'jpeg') or ($src_type eq 'png')) or
      die "Record $lnum: Invalid source type, stopped";
  }
  
  # Source type must now be known
  (defined $src_type) or
    die "Record $lnum: Can't determine source type, stopped";
  
  # Target type by default is same as source type
  my $target_type = $src_type;
  
  # If explicit target type is given, use that
  if (defined $attr->{'Target-Type'}) {
    $target_type = $attr->{'Target-Type'};
    (($target_type eq 'jpeg') or ($target_type eq 'png')) or
      die "Record $lnum: Invalid target type, stopped";
  }
  
  # Given source and target type, determine format for image
  my $fmt_type;
  if (($src_type eq 'jpeg') and ($target_type eq 'jpeg')) {
    $fmt_type = "jpeg";
    
  } elsif (($src_type eq 'png') and ($target_type eq 'png')) {
    $fmt_type = "png";
    
  } elsif (($src_type eq 'jpeg') and ($target_type eq 'png')) {
    $fmt_type = "jpeg2png";
    
  } elsif (($src_type eq 'png') and ($target_type eq 'jpeg')) {  
    $fmt_type = "png2jpeg";
    
  } else {
    die "Unexpected";
  }
  
  # Determine rotation setting
  my $rotation = 0;
  if (defined $attr->{'Clockwise'}) {
    $rotation = "$attr->{'Clockwise'}";
    (($rotation eq '0') or ($rotation eq '90') or
      ($rotation eq '180') or ($rotation eq '270')) or
      die "Record $lnum: Unsupported rotation, stopped";
    $rotation = int($rotation);
  }
  
  # Auto-detect name property
  my $pic_name;
  if ($path =~ /\A(.+)\.(?:jpg|jpeg|png)\z/i) {
    $pic_name = $1;
  } else {
    $pic_name = $path;
  }
  
  # Set explicit name if given
  if (defined $attr->{'Name'}) {
    $pic_name = $attr->{'Name'};
    ($pic_name =~ /\A\S(.*\S)?\z/) or
      die "Record $lnum: Invalid name given, stopped";
  }
  
  # Get description if given
  my $desc = undef;
  if (defined $attr->{'Desc'}) {
    $desc = $attr->{'Desc'};
  }
  
  # Get current node ID
  my $current_node;
  if ($#db_stack >= 0) {
    $current_node = $db_stack[-1];
  } else {
    die "Record $lnum: Must be in a database node, stopped";
  }
  
  # Get timestamp from the file
  my (undef, undef, undef, undef, undef, undef, undef, undef, undef,
      $tstamp, undef, undef, undef) = stat($image_path) or
    die "Failed to read timestamp for $image_path, stopped";
  
  # Open database transaction
  my $dbh = $dbc->beginWork('rw');
  
  # Check whether we can skip this image
  my $qr = $dbh->selectrow_arrayref(
    'SELECT listid '
    . 'FROM list '
    . 'INNER JOIN res ON res.resid = list.resid '
    . 'WHERE nodeid=? AND resname=?',
    undef,
    $current_node, $pic_name);
  if (defined $qr) {
    # We can skip this
    print { \*STDERR } "Skipping $image_path...\n";
    $dbc->finishWork;
    return;
  }
  
  # Get the rtypeid for the target type
  my $rtypeid = undef;
  
  $qr = $dbh->selectrow_arrayref(
    'SELECT rtypeid FROM rtype WHERE rtypename=?',
    undef,
    SpeakEasy::DB->string_to_db($target_type));
  if (defined $qr) {
    $rtypeid = $qr->[0];
  } else {
    die "Missing defined rtype for '$target_type', stopped";
  }
  
  # Check 
  
  # Get the maximum resid in use, or zero if none in use
  my $max_res = 0;
  $qr = $dbh->selectrow_arrayref(
    'SELECT resid FROM res ORDER BY resid DESC');
  if (defined $qr) {
    $max_res = $qr->[0];
  }
  
  # Get the maximum rbinid in use, or zero if none in use
  my $max_rbin = 0;
  $qr = $dbh->selectrow_arrayref(
    'SELECT rbinid FROM rbin ORDER BY rbinid DESC');
  if (defined $qr) {
    $max_rbin = $qr->[0];
  }
  
  # Get a new imager object
  my $imager = SpeakEasy::Image->configure($dbc);
  
  # Report what we are doing
  print { \*STDERR } "Loading $image_path...\n";
  
  # Transcode the image
  my ($full, $thumb) = $imager->load($image_path, $fmt_type, $rotation);
  
  # If there's a thumbnail, we add that resource first
  my $thumb_id = undef;
  if (defined $thumb) {
    my $thumb_bin = $max_rbin + 1;
    $max_rbin++;
    
    my $thumb_sth = $dbh->prepare(
      'INSERT INTO rbin (rbinid, rbinblob) VALUES (?, ?)');
    $thumb_sth->bind_param(1, $thumb_bin);
    $thumb_sth->bind_param(2, $thumb, SQL_BLOB);
    $thumb_sth->execute;
    
    $thumb_id = $max_res + 1;
    $max_res++;
    
    $dbh->do(
      'INSERT INTO res '
      . '(resid, rtypeid, resname, restime, resthumb, rbinid) '
      . 'VALUES (?, ?, ?, ?, ?, ?)',
      undef,
      $thumb_id,
      $rtypeid,
      SpeakEasy::DB->string_to_db('thumb:' . $pic_name),
      $tstamp,
      $thumb_id,
      $thumb_bin);
  }
  
  # Now add the main resource
  my $full_bin = $max_rbin + 1;
  $max_rbin++;
  
  my $full_sth = $dbh->prepare(
    'INSERT INTO rbin (rbinid, rbinblob) VALUES (?, ?)');
  $full_sth->bind_param(1, $full_bin);
  $full_sth->bind_param(2, $full, SQL_BLOB);
  $full_sth->execute;
  
  my $full_id = $max_res + 1;
  $max_res++;
  
  if (not defined $thumb_id) {
    $thumb_id = $full_id;
  }
  
  if (defined $desc) {
    $dbh->do(
      'INSERT INTO res '
      . '(resid, rtypeid, resname, restime, resdesc, resthumb, rbinid) '
      . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
      undef,
      $full_id,
      $rtypeid,
      SpeakEasy::DB->string_to_db($pic_name),
      $tstamp,
      $desc,
      $thumb_id,
      $full_bin);
    
  } else {
    $dbh->do(
      'INSERT INTO res '
      . '(resid, rtypeid, resname, restime, resthumb, rbinid) '
      . 'VALUES (?, ?, ?, ?, ?, ?)',
      undef,
      $full_id,
      $rtypeid,
      SpeakEasy::DB->string_to_db($pic_name),
      $tstamp,
      $thumb_id,
      $full_bin);
  }
  
  # Finally, link the new resource into the node
  $dbh->do(
    'INSERT INTO list (nodeid, resid) VALUES (?, ?)',
    undef,
    $current_node,
    $full_id);
  
  # Finish database transaction
  $dbc->finishWork;
}

# ==================
# Program entrypoint
# ==================

# Check that we got three arguments
#
($#ARGV == 2) or die "Expecting three arguments, stopped";

# Get and check arguments
#
my $db_path   = $ARGV[0];
my $data_path = $ARGV[1];
$base_path    = $ARGV[2];

(-f $db_path  ) or die "Can't find file '$db_path', stopped";
(-f $data_path) or die "Can't find file '$data_path', stopped";
($base_path =~ /\/\z/) or
  die "Base path must end with slash, stopped";

# Load the database
#
my $dbc = SpeakEasy::DB->connect($db_path, 0);

# Load the data file
#
my $dr = SpeakEasy::Datafile->load($data_path);

# Process each line
#
# If rec is defined, then the following properties are defined within
# it:
# 
# cmd stores the command on the command line
# path stores the path on the command line
# prop stores a hashref with properties
# line stores the line number the record began on
#
my $rec = undef;

while (1) {
  # Attempt to read another line
  my $retval = $dr->advance;
  
  # Check whether we are at end of file, or line is blank, or line is
  # not blank
  if ((not $retval) or ($dr->text =~ /\A\s*\z/)) {
    # Blank line or end of file, so process buffered record if defined
    if (defined $rec) {
      # Dispatch to command handlers
      if ($rec->{'cmd'} eq 'fscd') {
        fscd($rec->{'path'}, $rec->{'line'});
        
      } elsif ($rec->{'cmd'} eq 'dbcd') {
        $dbc->beginWork('rw');
        dbcd($rec->{'path'}, $dbc, $rec->{'line'});
        $dbc->finishWork;
        
      } elsif ($rec->{'cmd'} eq 'pic') {
        $dbc->beginWork('rw');
        pic($rec->{'path'}, $dbc, $rec->{'prop'}, $rec->{'line'});
        $dbc->finishWork;
        
      } else {
        die sprintf("Record %d: Unrecognized command, stopped",
                      $rec->{'line'});
      }
      
      # Finished processing, so reset buffered record to undefined
      $rec = undef;
    }
    
  } elsif (not defined $rec) {
    # We got a non-blank line that starts a record, so begin by defining
    # the initial state of the record
    $rec = {};
    $rec->{'prop'} = {};
    $rec->{'line'} = $dr->line_number;
    
    # Get the line and trim trailing whitespace and line breaks
    my $ltext = $dr->text;
    chomp $ltext;
    $ltext =~ s/\s+\z//;
    
    # Parse command line
    ($ltext =~ /\A\s*(\S+)\s+(\S.*)\z/) or
      die sprintf("Line %d: Invalid command line, stopped",
              $dr->line_number);
    
    my $cmd  = $1;
    my $path = $2;
    
    # Check command
    (($cmd eq 'fscd') or ($cmd eq 'dbcd') or ($cmd eq 'pic')) or
      die sprintf("Line %d: Invalid command %s, stopped",
              $dr->line_number, $cmd);
    
    # Store command and path in record
    $rec->{'cmd' } = $cmd;
    $rec->{'path'} = $path;
    
  } else {
    # Non-blank line, and record already defined, so parse a property
    # line and add it
    (defined $rec) or die "Unexpected";
    
    # Get the line and trim trailing whitespace and line breaks
    my $ltext = $dr->text;
    chomp $ltext;
    $ltext =~ s/\s+\z//;
    
    # Parse the property line
    ($dr->text =~ /\A\s*([A-Za-z\-]{1,31})\s*:\s*(\S.*)\z/) or
      die sprintf("Failed to parse line %d, stopped", $dr->line_number);
    
    my $prop_name = $1;
    my $prop_val  = $2;
    
    # Special handling for "Desc" property, else use a general case
    if ($prop_name eq 'Desc') {
      # Check whether property already defined
      if (defined $rec->{'prop'}->{'Desc'}) {
        # Already defined, so concat with space
        $rec->{'prop'}->{'Desc'} = $rec->{'prop'}->{'Desc'}
                                    . ' '
                                    . $prop_val;
        
      } else {
        # Not already defined, so define it new
        $rec->{'prop'}->{'Desc'} = $prop_val;
      }
    
    } else {
      # Not the Desc property, so check not already defined
      (not defined $rec->{'prop'}->{$prop_name}) or
        die sprintf("Record %d: Property %s defined twice, stopped",
                  $rec->{'line'}, $prop_name);
      
      # Store in properties
      $rec->{'prop'}->{$prop_name} = $prop_val;
    }
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
