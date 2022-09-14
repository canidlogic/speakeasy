#!/usr/bin/env perl
use strict;
use warnings;

# SpeakEasy imports
use SpeakEasy::Datafile;
use SpeakEasy::DB;

=head1 NAME

speakeasy_types.pl - Set the resource types in a SpeakEasy database.

=head1 SYNOPSIS

  ./speakeasy_types.pl db.sqlite types.txt

=head1 DESCRIPTION

This script is used to configure the resource types in the C<rtype>
table of the given SpeakEasy database.

The first argument is the SpeakEasy database to configure.  The second
argument is the path to a text file to use to define the resource types.
See below for the format of the text file.

=head2 Resource types file format

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

Every record must have a C<Type-Class> property that is one of the
following:

  image
  video
  audio
  text

Every record must have a C<Type-Name> property that is the unique name
of the type.  This must be a string of length 1-31 containing only ASCII
alphanumerics and underscores, where the first character is not a digit.

Every record must have a C<MIME-Type> property which is the MIME type to
associate with the data type.  The value will be trimmed of leading and
trailing whitespace but otherwise will be recorded as-is in the
database.  It must have only US-ASCII characters in range [0x21, 0x7e]
and it must have at least one and at most 63 characters.

Optionally, a record may have a C<Default-Thumb> property.  If provided,
the value must be an unsigned decimal integer which gives the resource
number in the database of an image resource that will be the default
thumbnail image for all resources of this type.  If this property is
omitted, there will be no default thumbnail property assigned to this
type.

Records are processed in the order they appear in the file.  Each record
either inserts a new resource type record or updates an existing one
with new values.

=cut

# ==================
# Program entrypoint
# ==================

# Check that we got two arguments
#
($#ARGV == 1) or die "Expecting two arguments, stopped";

# Get and check arguments
#
my $db_path   = $ARGV[0];
my $data_path = $ARGV[1];

(-f $db_path  ) or die "Can't find file '$db_path', stopped";
(-f $data_path) or die "Can't find file '$data_path', stopped";

# Open database connection to database
#
my $dbc = SpeakEasy::DB->connect($db_path, 0);

# Begin r/w transaction and get handle
#
my $dbh = $dbc->beginWork('rw');

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
      # Check for required fields
      for my $rpn ('Type-Class', 'Type-Name', 'MIME-Type') {
        (defined $rec->{$rpn}) or
          die sprintf("Record %d missing required %s property, stopped",
            $rec_line, $rpn);
      }
      
      # Check whether record already defined
      my $qr = $dbh->selectrow_arrayref(
        'SELECT rtypeid FROM rtype WHERE rtypename = ?',
        undef,
        SpeakEasy::DB->string_to_db($rec->{'Type-Name'}));
      
      if (defined $qr) {
        # We already have a type with this name, so update the record
        if (defined $rec->{'Default-Thumb'}) {
          $dbh->do(
            'UPDATE rtype '
            . 'SET rtypeclass = ?, '
            . 'rtypemime = ?, '
            . 'rtypethumb = ? '
            . 'WHERE rtypename = ?',
            undef,
            SpeakEasy::DB->string_to_db($rec->{'Type-Class'}),
            SpeakEasy::DB->string_to_db($rec->{'MIME-Type' }),
            $rec->{'Default-Thumb'},
            SpeakEasy::DB->string_to_db($rec->{'Type-Name' }));
          
        } else {
          $dbh->do(
            'UPDATE rtype '
            . 'SET rtypeclass = ?, '
            . 'rtypemime = ?, '
            . 'rtypethumb = NULL '
            . 'WHERE rtypename = ?',
            undef,
            SpeakEasy::DB->string_to_db($rec->{'Type-Class'}),
            SpeakEasy::DB->string_to_db($rec->{'MIME-Type' }),
            SpeakEasy::DB->string_to_db($rec->{'Type-Name' }));
        }
        
      } else {
        # We are defining a brand-new type
        if (defined $rec->{'Default-Thumb'}) {
          $dbh->do(
            'INSERT INTO rtype '
            . '(rtypename, rtypeclass, rtypemime, rtypethumb) '
            . 'VALUES (?, ?, ?, ?)',
            undef,
            SpeakEasy::DB->string_to_db($rec->{'Type-Name' }),
            SpeakEasy::DB->string_to_db($rec->{'Type-Class'}),
            SpeakEasy::DB->string_to_db($rec->{'MIME-Type' }),
            $rec->{'Default-Thumb'});
          
        } else {
          $dbh->do(
            'INSERT INTO rtype '
            . '(rtypename, rtypeclass, rtypemime) '
            . 'VALUES (?, ?, ?)',
            undef,
            SpeakEasy::DB->string_to_db($rec->{'Type-Name' }),
            SpeakEasy::DB->string_to_db($rec->{'Type-Class'}),
            SpeakEasy::DB->string_to_db($rec->{'MIME-Type' }));
        }
      }
      
      # Finished processing, so reset buffered record to undefined
      $rec = undef;
      $rec_line = undef;
    }
    
  } else {
    # Non-blank line, so begin by defining a new record if none defined
    # yet
    if (not defined $rec) {
      $rec = {};
      $rec_line = $dr->line_number;
    }
    
    # Get the line and trim trailing whitespace and line breaks
    my $ltext = $dr->text;
    chomp $ltext;
    $ltext =~ s/\s+\z//;
    
    # Parse the property line
    ($ltext =~ /\A\s*([^\s:]+)\s*:\s*(\S.*)\z/) or
      die sprintf("Failed to parse line %d, stopped", $dr->line_number);
    
    my $prop_name = $1;
    my $prop_val  = $2;
    
    # Check specific property value
    if ($prop_name eq 'Type-Class') {
      (($prop_val eq 'image') or
        ($prop_val eq 'video') or
        ($prop_val eq 'audio') or
        ($prop_val eq 'text')) or
        die sprintf("Line %d: Unsupported Type-Class value, stopped",
                    $dr->line_number);
    
    } elsif ($prop_name eq 'Type-Name') {
      ($prop_val =~ /\A[A-Za-z_][A-Za-z0-9_]{0,30}\z/) or
        die sprintf("Line %d: Invalid Type-Name value, stopped",
                    $dr->line_number);
      
    } elsif ($prop_name eq 'MIME-Type') {
      ($prop_val =~ /\A[\x{21}-\x{7e}]{1,63}\z/) or
        die sprintf("Line %d: Invalid MIME-Type value, stopped",
                    $dr->line_number);
      
    } elsif ($prop_name eq 'Default-Thumb') {
      # Check that integer in reasonable range and cast as integer
      ($prop_val =~ /\A1?[0-9]{1,9}\z/) or
        die sprintf("Line %d: Invalid Default-Thumb value, stopped",
                    $dr->line_number);
      $prop_val = int($prop_val);
      
      # Check that indicated resource exists and is an image
      my $qr = $dbh->selectrow_arrayref(
        'SELECT resid '
        . 'FROM res '
        . 'INNER JOIN rtype ON rtype.rtypeid = res.rtypeid '
        . 'WHERE resid = ? AND rtypeclass = ?',
        undef,
        $prop_val,
        SpeakEasy::DB->string_to_db('image'));
      (defined $qr) or
        die sprintf(
          "Line %d: Thumb must be existing image resource, stopped",
          $dr->line_number);
      
    } else {
      die sprintf("Line %d: Unrecognized property name, stopped",
                    $dr->line_number);
    }
    
    # Check that not defined yet
    (not defined $rec->{$prop_name}) or
      die sprintf("Record %d: Property %s defined twice, stopped",
                    $rec_line, $prop_name);
    
    # Add this property
    $rec->{$prop_name} = $prop_val;
  }
  
  # Leave loop if we read the end of the file
  unless ($retval) {
    last;
  }
}

# Commit the transaction
#
$dbc->finishWork;

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
