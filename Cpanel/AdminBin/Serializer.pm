package Cpanel::AdminBin::Serializer;

# cpanel - Cpanel/AdminBin/Serializer.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::AdminBin::Serializer

=head1 IMPORTANT NOTE!!!

B<ONLY USE THIS MODULE FOR EPHEMERAL DATA.> (e.g., caches, IPC, …)
B<NEVER> use this module for authoritative datastores.

This module does B<NOT> define a specific serialization format.
It I<currently> uses JSON under the hood, but it could potentially
switch to something like CBOR, MessagePack, or Sereal.

So please don’t treat the input/output from this module as JSON.
It technically isn’t JSON anyway since it attempts (imperfectly) to handle
arbitrary binary data. (“Real” JSON is exclusively UTF-8.)

=cut

#----------------------------------------------------------------------

use Cpanel::JSON ();

#----------------------------------------------------------------------

# case CPANEL-2195: Editing Global Filters Breaks UTF-8 Characters
#
# Cpanel::AdminBin::Serializer MUST ROUNDTRIP to UTF-8 BINARY STRINGS
# as we do not have control of the incoming data and it must be passed
# unmodified to the subprocess
#
# We are not alone:
#
# JSON::Parse was written because JSON::XS always does SvUTF8_on even when we don't want it
# https://metacpan.org/pod/distribution/JSON-Parse/lib/JSON/Parse.pod#Handling-of-Unicode
#
# It would be better to use JSON::XS::ByteString::encode_utf8 because
# we are only turing of the utf8 flag on level deep.  This is fine
# for all the current use cases.
#
# Speedy option (IMPLEMENTED):
# Finally we could just patch JSON::XS to not do SvUTF8_on (sv) in
# decode_str when passed a flag
#
our $VERSION = '2.4';

our $MAX_LOAD_LENGTH;
our $MAX_PRIV_LOAD_LENGTH;

BEGIN {
    *MAX_LOAD_LENGTH      = \$Cpanel::JSON::MAX_LOAD_LENGTH;
    *MAX_PRIV_LOAD_LENGTH = \$Cpanel::JSON::MAX_PRIV_LOAD_LENGTH;
    *DumpFile             = *Cpanel::JSON::DumpFile;
}

=head1 FUNCTIONS

=head2 DumpFile( $DATA, $PATH_OR_FH )

XXX: This will dump binary strings verbatim. No function in this module
can load such strings from a filehandle.

Dumps $DATA to $PATH_OR_FH.

=head2 $serialized = Dump( $DATA )

Serializes $DATA to a string.

=cut

BEGIN {
    *Dump = *Cpanel::JSON::Dump;

    # This should not be called because it assumes that JSON is the
    # serialization. Its intent is to be “safe” with regard to HTML
    # output, i.e., to escape “/” as “\/” in JSON.
    *SafeDump = *Cpanel::JSON::SafeDump;

    # XXX Please don’t use this. It doesn’t accept non-UTF8 data,
    # which can bite you when you least expect it to.
    #
    # $_[0] == $file_or_fh
    # $_[1] == $max_load_length
    # $_[2] == $path to the file (this will be in the exception on error)
    *LoadFile = *Cpanel::JSON::LoadFileNoSetUTF8;

    #XXX: This currently will set the UTF-8 flag on the passed-in string!
    #If that's a problem for you, then do:
    #
    #   Load("$json")
    #
    #...which will make a "throw-away" copy of the string that this function
    #can do with as it pleases.
    #
    *Load = *Cpanel::JSON::Load;

    *looks_like_serialized_data = *Cpanel::JSON::looks_like_json;
}

#----------------------------------------------------------------------
# XXX: The *LoadFile methods below exhibit some ill behaviors
# that are being sent in as expediences but should not be imitated:
#
# - Calling private functions in external modules
# - Passing in values that are only relevant if there is an error
#
# In the latter case, a better path might be to create an exception that
# doesn’t know the path, then, at a higher level that does know the path,
# do one of either:
#
# - add the path to the error, then rethrow
# - throw a new error that duplicates the old error but also has the path
#
# XXX TODO: Implement one of the above.
#----------------------------------------------------------------------

=head2 $parsed = SafeLoadFile( $PATH_OR_FH [, $PATH ] )

Loads data from $PATH_OR_FH. This attempts to remove any vestigial
UTF-8 messiness from the underlying Perl scalars in the decoded data.
This is important for working with certain XS libraries (e.g.,
L<DBD::SQLite>) which historically haven’t worked well with cPanel’s
L<JSON::XS> that attempt to make JSON tolerate binary strings.

$PATH is inserted into the error message in the event of failure,
which helps with diagnosing problems. Always give it if you can.

=cut

# $_[0] == $file_or_fh
# $_[1] == $path to the file (this will be in the exception on error)
sub SafeLoadFile {
    return Cpanel::JSON::_LoadFile( $_[0], $Cpanel::JSON::MAX_LOAD_LENGTH, $Cpanel::JSON::DECODE_UTF8, $_[1], $Cpanel::JSON::LOAD_STRICT );
}

#----------------------------------------------------------------------

=head2 $parsed = SafeLoad( $SERIALIZED [, $PATH ] )

Parses a string of serialized data. Similar to C<SafeLoadFile()>,
it will attempt to give you a parse without any UTF-8 funniness that
may trip up the likes of L<DBD::SQLite>.

Note that this function may NOT round-trip correctly with Dump
if the payload includes non-UTF-8 strings. (TODO: Fix this.)

This is not guaranteed to leave $SERIALIZED alone; e.g., it may
do a UTF-8 decode.

=cut

sub SafeLoad {
    utf8::decode( $_[0] );
    return Cpanel::JSON::LoadNoSetUTF8(@_);
}

#----------------------------------------------------------------------

=head2 $new = clone( $DATA )

A deep clone. Only guaranteed to work on data structures that follow
JSON’s data model (which excludes, e.g., regexps, coderefs, etc.).
It I<may> work, but it’s not guaranteed to work.

=cut

sub clone {
    return Cpanel::JSON::LoadNoSetUTF8( Cpanel::JSON::Dump( $_[0] ) );
}

1;
