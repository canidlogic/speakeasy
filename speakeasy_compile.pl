#!/usr/bin/env perl
use strict;
use warnings;

# SpeakEasy imports
use SpeakEasy::DB;

# Scavenger imports
use Scavenger::Encode;

# Non-core imports
use JSON::Tiny qw(encode_json);

# Core imports
use Math::BigInt;

=head1 NAME

speakeasy_compile.pl - Compile a SpeakEasy database into a binary
SpeakEasy format.

=head1 SYNOPSIS

  ./speakeasy_compile.pl db.sqlite compiled.speakeasy

=head1 DESCRIPTION

Compiles a SpeakEasy SQL database into a special binary format which can
be loaded into the HTML5 SpeakEasy viewer app.

The script requires a path to the SpeakEasy SQL database to compile, and
the path to the compiled SpeakEasy viewer binary file that should be
generated.  The SpeakEasy SQL database should have been created with the
C<speakeasy_new.pl> script.  The format of the generated SpeakEasy
binary format is described below.

=head2 SpeakEasy binary format

The SpeakEasy viewer format is a type of Scavenger file.  It has the
primary signature C<72edf078> and the secondary signature C<spkez1>.

Object #0 is special, as it is always the root node.  Objects can either
be nodes or blobs.  Nodes store JSON describing one of the nodes in the
node tree, while blobs store raw binary data for an embedded multimedia
file.

Node JSON stores a JSON object that has the following properties:

=over 4

=item B<trail>

An array of one or more node subarrays indicating how to get from the
root node to this node.  Each node subarray has two elements, the first
being the object ID of the node and the second being the node name as a
string.  The first element of the trail array is always for the root
node, so it always has the object ID zero.  The last element of the
trail array corresponds to the current node.  For the root node, the
trail will only have a single element representing the root node.

=item B<folders>

A JSON array storing subfolder subarrays.  Each subarray has two
elements, the first being the object ID of the subfolder node and the
second being the node name as a string.  The subarrays are not in any
particular order.  This property will be an empty array if there are no
subfolders for this node.

=item B<files>

A JSON array storing all the multimedia resources present in this node.
Each multimedia resource is represented by a JSON object.  The C<rclass>
property is a string value that is either C<image>, C<video>, C<audio>,
or C<text> which defines the basic kind of resource.

The C<rbin> property is an integer holding the object ID of the blob
storing the raw file data, and the C<rmime> is a string storing the MIME
type of that blob.  The C<tbin> and <tmime> properties have the same
interpretation, except they are for the thumbnail, which is always of
the multimedia class C<image>.

The C<rname> is the resource name.  The C<rtime> is the
timestamp of the resource, in the following format:

  YYYY-MM-DD HH:MM:SS

Zero-padding is used to keep the string always the exact length.

Finally, resource objects may optionally have a C<desc> property, which
is a string storing an extra description of the resource.

=back

=cut

# =========
# Constants
# =========

# The maximum recursive depth that can be reached during compilation.
#
my $MAX_DEPTH = 2048;

# ==========
# Local data
# ==========

# The SpeakEasy::DB instance.
#
# This must be set before any calls to the local functions.  It should
# be ready for read operations on the SpeakEasy database.
#
# There should also be temporary table temp.remap defined on the
# connection.  This table has the column objidx which is the object
# index in the Scavenger file being constructed.  The table also has the
# column pair etype and eid.  etype is 0 for a node, 1 for a binary.
# eid is either a nodeid or a rbinid, depending on etype.  objidx must
# be unique within the table, and the (etype, eid) pair must also be
# unique within the table.
#
my $dbc;

# The Scavenger encoder.
#
# This must be set before any calls to the local functions.
#
my $enc;

# ===============
# Local functions
# ===============

# pack_rbin(rbinid)
# -----------------
#
sub pack_rbin {
  # Get parameter
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  my $rbinid = shift;
  (not ref($rbinid)) or die "Wrong parameter type, stopped";
  $rbinid = int($rbinid);
  
  # Start read work
  my $dbh = $dbc->beginWork('r');
  my $qr;
  
  # Load the resource
  $qr = $dbh->selectrow_arrayref(
    'SELECT rbinblob FROM rbin WHERE rbinid=?',
    undef,
    $rbinid);
  (defined $qr) or die "Failed to locate binary, stopped";
  my $binary = $qr->[0];
  
  # Pack the resource into the Scavenger file
  $enc->beginObject;
  $enc->writeBinary($binary);
  
  # Finish read work
  $dbc->finishWork;
}

# pack_node(nodeid)
# -----------------
#
sub pack_node {
  # Get parameter
  ($#_ == 0) or die "Wrong number of parameters, stopped";
  
  my $nodeid = shift;
  (not ref($nodeid)) or die "Wrong parameter type, stopped";
  $nodeid = int($nodeid);
  
  # Start read work
  my $dbh = $dbc->beginWork('r');
  my $qr;
  my $sth;
  
  # Build the trail from the current node to the root
  my @trail;
  my $trace = $nodeid;
  while (defined $trace) {
    # Load current node record
    $qr = $dbh->selectrow_arrayref(
      'SELECT nodename, nodesuper FROM node WHERE nodeid=?',
      undef,
      $trace);
    (defined $qr) or die "Failed to find node record, stopped";
    
    my $nodename  = SpeakEasy::DB->db_to_string($qr->[0]);
    my $nodesuper = $qr->[1];
    
    # Add the current node record to the start of the trail
    unshift @trail, ([$trace, $nodename]);
    
    # Move to the parent record (or undefined if this was root)
    $trace = $nodesuper;
    
    # Check depth limit
    if (scalar(@trail) > $MAX_DEPTH) {
      die "Too much recursive depth, stopped";
    }
  }
  
  # Build the subfolder list
  my @subfolders;
  $sth = $dbh->prepare(
    'SELECT nodeid, nodename FROM node WHERE nodesuper=?');
  $sth->bind_param(1, $nodeid);
  $sth->execute;
  while(my $rec = $sth->fetchrow_arrayref) {
    # Get current record
    my $folderid   = $rec->[0];
    my $foldername = SpeakEasy::DB->db_to_string($rec->[1]);
    
    # Add to subfolder list
    push @subfolders, ([$folderid, $foldername]);
  }
  
  # Build the file entries
  my @files;
  $sth = $dbh->prepare(
    'SELECT rt1.rtypeclass, rt1.rtypemime, rt1.rtypethumb, '
    . 'rs1.resname, rs1.restime, rs1.resdesc, rs1.resthumb, rs1.rbinid, '
    . 'rs1.resid, rt2.rtypemime, rt3.rtypemime '
    . 'FROM list '
    . 'INNER JOIN res AS rs1 ON rs1.resid = list.resid '
    . 'INNER JOIN rtype AS rt1 ON rt1.rtypeid = rs1.rtypeid '
    . 'LEFT OUTER JOIN res AS rs2 ON rs2.resid = rs1.resthumb '
    . 'LEFT OUTER JOIN rtype AS rt2 ON rt2.rtypeid = rs2.rtypeid '
    . 'LEFT OUTER JOIN res AS rs3 ON rs3.resid = rt1.rtypethumb '
    . 'LEFT OUTER JOIN rtype AS rt3 ON rt3.rtypeid = rs3.rtypeid '
    . 'WHERE nodeid = ?');
  $sth->bind_param(1, $nodeid);
  $sth->execute;
  while(my $rec = $sth->fetchrow_arrayref) {
    # Get current record
    my $rtypeclass = SpeakEasy::DB->db_to_string($rec->[0]);
    my $rtypemime  = SpeakEasy::DB->db_to_string($rec->[1]);
    my $rtypethumb = $rec->[2];
    my $resname    = SpeakEasy::DB->db_to_string($rec->[3]);
    my $restime    = $rec->[4];
    my $resdesc    = $rec->[5];
    my $resthumb   = $rec->[6];
    my $rbinid     = $rec->[7];
    my $resid      = $rec->[8];
    my $thumbmime  = $rec->[9];
    my $rthumbmime = $rec->[10];
    
    # Decode description if defined
    if (defined $resdesc) {
      $resdesc = SpeakEasy::DB->db_to_string($resdesc);
    }
    
    # Figure out the thumbnail and mime type
    my $thumb_id;
    my $thumb_mime;
    
    if (defined $resthumb) {
      $thumb_id = $resthumb;
      $thumb_mime = SpeakEasy::DB->db_to_string($thumbmime);
      
    } elsif (defined $rtypethumb) {
      $thumb_id = $rtypethumb;
      $thumb_mime = SpeakEasy::DB->db_to_string($rthumbmime);
    
    } else {
      die "Missing thumbnail for resource $resid, stopped";
    }
    
    # Parse the datetime
    my ($sec, $min, $hour, $mday, $mon, $year, undef, undef, undef) =
      gmtime($restime);
    
    $year += 1900;
    $mon++;
    
    # Create the timestamp string
    my $tstamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                    $year,
                    $mon,
                    $mday,
                    $hour,
                    $min,
                    $sec);
    
    # Define the file object with all required fields (except the
    # thumbnail mime, which we will do later)
    my $fil = {
      'rclass' => $rtypeclass,
      'rbin'   => $rbinid,
      'rmime'  => $rtypemime,
      'tbin'   => $thumb_id,
      'tmime'  => $thumb_mime,
      'rname'  => $resname,
      'rtime'  => $tstamp
    };
    
    # Define optional properties on file object
    if (defined $resdesc) {
      $fil->{'desc'} = $resdesc;
    }
    
    # Add the file object to the list
    push @files, ($fil);
  }
  
  # Remap all the node IDs to object IDs in the trail
  for my $a (@trail) {
    $qr = $dbh->selectrow_arrayref(
      'SELECT objidx FROM temp.remap '
      . 'WHERE etype = 0 AND eid = ?',
      undef,
      $a->[0]);
    (defined $qr) or die "Failed to look up remap, stopped";
    $a->[0] = $qr->[0];
  }
  
  # Remap all the node IDs to object IDs in the subfolders
  for my $a (@subfolders) {
    $qr = $dbh->selectrow_arrayref(
      'SELECT objidx FROM temp.remap '
      . 'WHERE etype = 0 AND eid = ?',
      undef,
      $a->[0]);
    (defined $qr) or die "Failed to look up remap, stopped";
    $a->[0] = $qr->[0];
  }
  
  # Remap the binary references to object IDs in the files
  for my $a (@files) {
    $qr = $dbh->selectrow_arrayref(
      'SELECT objidx FROM temp.remap '
      . 'WHERE etype = 1 AND eid = ?',
      undef,
      $a->{'rbin'});
    (defined $qr) or die "Failed to look up remap, stopped";
    $a->{'rbin'} = $qr->[0];
    
    $qr = $dbh->selectrow_arrayref(
      'SELECT objidx FROM temp.remap '
      . 'WHERE etype = 1 AND eid = ?',
      undef,
      $a->{'tbin'});
    (defined $qr) or die "Failed to look up remap, stopped";
    $a->{'tbin'} = $qr->[0];
  }
  
  # Form the whole node object
  my %node = (
    'trail'   => \@trail,
    'folders' => \@subfolders,
    'files'   => \@files
  );
  
  # Encode the whole thing to a JSON binary string
  my $json = encode_json(\%node);
  
  # Add binary object storing the JSON to the Scavenger file
  $enc->beginObject;
  $enc->writeBinary($json);
  
  # Finish read work
  $dbc->finishWork;
}

# ==================
# Program entrypoint
# ==================

# Check that we got two arguments
#
($#ARGV == 1) or die "Wrong number of program arguments, stopped";

# Get the arguments
#
my $db_path  = $ARGV[0];
my $out_path = $ARGV[1];

(-f $db_path) or die "Can't find file '$db_path', stopped";
(not (-e $out_path)) or die "File '$out_path' already exists, stopped";

# Open a database connection and start a read-write transaction
#
$dbc = SpeakEasy::DB->connect($db_path, 0);
my $dbh = $dbc->beginWork('rw');

# Figure out the number of nodes and the number of binaries in the
# database
#
my $node_count;
my $rbin_count;

my $qr = $dbh->selectrow_arrayref(
  'SELECT count(nodeid) FROM node');
if (defined $qr) {
  $node_count = $qr->[0];
} else {
  $node_count = 0;
}

$qr = $dbh->selectrow_arrayref(
  'SELECT count(rbinid) FROM rbin');
if (defined $qr) {
  $rbin_count = $qr->[0];
} else {
  $rbin_count = 0;
}

# Figure out the root node
#
my $root_node;

$qr = $dbh->selectrow_arrayref(
  'SELECT nodeid FROM node WHERE nodesuper ISNULL');
if (defined $qr) {
  $root_node = $qr->[0];
} else {
  die "Can't find the root node, stopped";
}

# The temporary table temp.nodes will have a primary key numbering the
# nodes, named tid, and the nodeid used in the database, as nodeid;
# furthermore, the root node will be the first node in this temporary
# table
#
$dbh->do(
  'CREATE TEMPORARY TABLE temp.nodes ('
  . 'tid INTEGER PRIMARY KEY ASC,'
  . 'nodeid INTEGER NOT NULL'
  . ')'
);

$dbh->do(
  'INSERT INTO temp.nodes (nodeid) VALUES (?)',
  undef,
  $root_node);

$dbh->do(
  'INSERT INTO temp.nodes (nodeid) '
  . 'SELECT t1.nodeid FROM main.node AS t1 '
  . 'WHERE t1.nodeid <> ?',
  undef,
  $root_node);

# The temporary table temp.rbins will have a primary key numbering the
# binaries, named bid, and the rbinid used in the database, as rbinid
#
$dbh->do(
  'CREATE TEMPORARY TABLE temp.rbins ('
  . 'bid INTEGER PRIMARY KEY ASC, '
  . 'rbinid INTEGER NOT NULL'
  . ')'
);

$dbh->do(
  'INSERT INTO temp.rbins (rbinid) '
  . 'SELECT t1.rbinid FROM main.rbin AS t1');

# Get the lowest primary key index in both nodes and rbins tables
#
my $lowest_node;
my $lowest_rbin;

$qr = $dbh->selectrow_arrayref(
  'SELECT tid FROM temp.nodes ORDER BY tid ASC'
);
if (defined $qr) {
  $lowest_node = $qr->[0];
} else {
  $lowest_node = 0;
}

$qr = $dbh->selectrow_arrayref(
  'SELECT bid FROM temp.rbins ORDER BY bid ASC'
);
if (defined $qr) {
  $lowest_rbin = $qr->[0];
} else {
  $lowest_rbin = 0;
}

# Now create the temp.remap table defined earlier in the documentation
# for the $dbc local data variable
#
$dbh->do(
  'CREATE TEMPORARY TABLE temp.remap ('
  . 'remapid INTEGER PRIMARY KEY ASC, '
  . 'objidx  INTEGER UNIQUE NOT NULL, '
  . 'etype   INTEGER NOT NULL, '
  . 'eid     INTEGER NOT NULL, '
  . 'UNIQUE  (etype, eid)'
  . ')'
);

$dbh->do(
  'CREATE UNIQUE INDEX temp.ix_remap_obj ON remap(objidx)'
);

$dbh->do(
  'CREATE UNIQUE INDEX temp.ix_remap_e ON remap(etype, eid)'
);

$dbh->do(
  'INSERT INTO temp.remap (objidx, etype, eid) '
  . 'SELECT (t1.tid + ?), 0, t1.nodeid '
  . 'FROM temp.nodes AS t1',
  undef,
  (0 - $lowest_node));

$dbh->do(
  'INSERT INTO temp.remap (objidx, etype, eid) '
  . 'SELECT (t1.bid + ?), 1, t1.rbinid '
  . 'FROM temp.rbins AS t1',
  undef,
  ($node_count - $lowest_rbin));

# Get the highest object index in the remap table
#
$qr = $dbh->selectrow_arrayref(
  'SELECT objidx FROM temp.remap ORDER BY objidx DESC');
(defined $qr) or die "No objects to pack, stopped";
my $highest_object = $qr->[0];

# We now have mapped out how we will pack the database into the
# Scavenger file, so initialize the Scavenger encoder
#
$enc = Scavenger::Encode->create($out_path, '72edf078', 'spkez1');

# Pack each of the objects
#
for(my $i = 0; $i <= $highest_object; $i++) {

  # Figure out what we are packing for this object
  $qr = $dbh->selectrow_arrayref(
    'SELECT etype, eid FROM temp.remap WHERE objidx=?',
    undef,
    $i);
  (defined $qr) or die "Failed to find object record, stopped";
  
  my $etype = $qr->[0];
  my $eid   = $qr->[1];
  
  # Dispatch to appropriate local function and also log status message
  if ($etype == 0) {
    print { \*STDERR } "Packing node $eid...\n";
    pack_node($eid);
    
  } elsif ($etype == 1) {
    print { \*STDERR } "Packing binary $eid...\n";
    pack_rbin($eid);
    
  } else {
    die "Unexpected";
  }
}

# If we got all the way here, commit the transaction and complete the
# Scavenger encoding
#
$dbc->finishWork;
$enc->complete;

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
