#!/usr/bin/env perl
use strict;
use warnings;

# SpeakEasy imports
use SpeakEasy::DB;

=head1 NAME

speakeasy_new.pl - Create a new SpeakEasy database with the appropriate
structure.

=head1 SYNOPSIS

  ./speakeasy_new.pl newdb.sqlite

=head1 DESCRIPTION

This script is used to create a new, empty SpeakEasy database, with the
appropriate structure but no records.

The database is created at the given path.  The database must not
already exist or a fatal error occurs.

The SQL string embedded in this script contains the complete database
structure.  The following subsections describe the function of each
table within the database.

=head2 node table

Stores the node map.  All resources are stored in a tree of I<nodes>
which is defined by this table.

A node object has a name and a reference to a parent node object.  The
node name and parent reference pair must be unique.  That is, for each
node, each child node must have a unique name.

Exactly one node may have its parent reference set to NULL, indicating
that it is the root node.  For all other nodes, it must be possible to
get from the node to the root node by following parent node references,
with a circular reference error if ever a node is visited twice on this
trip to the root node.

=head2 rtype table

Enumerates the different kinds of resources that can be embedded in the
C<res> table.

Each resource type has a name, which is a string of ASCII alphanumerics
and underscores of length 1-31, where the first character is not a
digit.

Each resource type has a class, which indicates broadly what kind of
multimedia is stored in the resource.  Recognized class names are
C<image>, C<video>, C<audio>, and C<text>.

Each resource type declares a MIME type that is used to identify such
resources to client browsers.

Each resource type may optionally declare a default thumbnail, which is
a reference to a resource in the C<res> table that has a resource of
type-class C<image>.  This may also be set to NULL if there is no
default thumbnail.

The default thumbnail will be used as the thumbnails for all resources
of that type that do not declare their own thumbnail.  Every resource
I<must> have a thumbnail, either explicitly declared for the particular
resource in the C<res> table or from the default thumbnail declared 
here.

=head2 rbin table

Stores the actual raw binary content of embedded resources.

All metadata is stored in the C<res> table.  It is possible for the same
binary blob in the C<rbin> table to have multiple different C<res> table
records selecting it.

=head2 res table

Stores the embedded resources and their metadata.

Every resource must have a type, which is a reference to a record in the
C<rtype> table.

Every resource must have a name, which can be any Unicode string, and it
does not need to be unique in any way.  Within each node, the user is
able to sort resources by name in both ascending and descending order.
By default, the name is the filename of the resource at the time it was
added to the database, but this does not have to be the case.

Every resource must have a timestamp, which is an integer storing the
number of seconds elapsed since midnight GMT at the beginning of January
1, 1970.  The timestamp does not need to be unique in any way.  Within
each node, the user is able to sort resources by timestamp in both
chronological and reverse-chronological order.  By default, the
timestamp is the last-modified time of the file when it was added to the
database, but this does not have to be the case.

A resource may optionally have a description, which is a Unicode text
string.  The description will be displayed alongside the image in
gallery view.  NULL may be used if there is no description.

A resource may optionally declare a thumbnail for itself.  NULL may be
used if there is no specific thumbnail.  In this case, the resource type
record in the C<rtype> table must have a default thumbnail, which will
then be used in the gallery view.  If a thumbnail is defined, it must
reference a resource that has a type-class of C<image>.  Image resources
may refer to themselves as their own thumbnail.

Finally, the res table refers to a record in the C<rbin> table that
stores the actual binary data for the resource.

=head2 list table

Stores listings of resources within each node.

Each list record has a reference to a record in the C<node> table,
defining which node this list record is part of.

Each list record also stores a reference to a record in the C<res>
table, defining which specific resource is meant.

The node reference and resource record pair must be unique.  This means
that the same resource can be used at most once within each node, but a
single resource can appear in multiple nodes.

No sorting is implied by the C<list> table.  The user can sort by
resource names, resource timestamps, or resource types.

=head2 vars table

Stores relevant configuration information in a simple key/value map.

=cut

# Define a string holding the whole SQL script for creating the
# structure of the database, with semicolons used as the termination
# character for each statement and nowhere else
#
my $sql_script = q{

CREATE TABLE node (
  nodeid      INTEGER PRIMARY KEY ASC,
  nodesuper   INTEGER,
  nodename    TEXT NOT NULL,
  UNIQUE      (nodename, nodesuper)
);

CREATE UNIQUE INDEX ix_node_rec
  ON node(nodesuper, nodename);

CREATE INDEX ix_node_dir
  ON node(nodesuper);

CREATE TABLE rtype (
  rtypeid     INTEGER PRIMARY KEY ASC,
  rtypename   TEXT UNIQUE NOT NULL,
  rtypeclass  TEXT NOT NULL,
  rtypemime   TEXT NOT NULL,
  rtypethumb  INTEGER
);

CREATE UNIQUE INDEX ix_rtype_name
  ON rtype(rtypename);

CREATE TABLE rbin (
  rbinid      INTEGER PRIMARY KEY ASC,
  rbinblob    BLOB NOT NULL
);

CREATE TABLE res (
  resid       INTEGER PRIMARY KEY ASC,
  rtypeid     INTEGER NOT NULL,
  resname     TEXT NOT NULL,
  restime     INTEGER NOT NULL,
  resdesc     TEXT,
  resthumb    INTEGER,
  rbinid      INTEGER NOT NULL
);

CREATE TABLE list (
  listid    INTEGER PRIMARY KEY ASC,
  nodeid    INTEGER NOT NULL,
  resid     INTEGER NOT NULL,
  UNIQUE    (nodeid, resid)
);

CREATE UNIQUE INDEX ix_list_rec
  ON list(nodeid, resid);

CREATE INDEX ix_list_node
  ON list(nodeid);

CREATE TABLE vars (
  varsid    INTEGER PRIMARY KEY ASC,
  varskey   TEXT UNIQUE NOT NULL,
  varsval   TEXT NOT NULL
);

CREATE UNIQUE INDEX ix_vars_key
  ON vars(varskey);

};

# ==================
# Program entrypoint
# ==================

# Check that we got one arguments
#
($#ARGV == 0) or die "Expecting one database path argument, stopped";

# Open database connection to a new database
#
my $dbc = SpeakEasy::DB->connect($ARGV[0], 1);

# Begin r/w transaction and get handle
#
my $dbh = $dbc->beginWork('rw');

# Parse our SQL script into a sequence of statements, each ending with
# a semicolon
#
my @sql_list;
@sql_list = $sql_script =~ m/(.*?);/gs
  or die "Failed to parse SQL script, stopped";

# Run all the SQL statements needed to build the the database structure
#
for my $sql (@sql_list) {
  $dbh->do($sql);
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
