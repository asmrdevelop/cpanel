package Cpanel::JSON;

# cpanel - Cpanel/JSON.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Fcntl::Constants   ();
use Cpanel::FHUtils::Tiny      ();
use Cpanel::JSON::Unicode      ();
use Cpanel::LoadFile::ReadFast ();
use JSON::XS                   ();
use Cpanel::UTF8::Strict       ();

# Constants
our $NO_DECODE_UTF8 = 0;
our $DECODE_UTF8    = 1;

our $LOAD_STRICT  = 0;
our $LOAD_RELAXED = 1;

our $MAX_LOAD_LENGTH_UNLIMITED = 0;
our $MAX_LOAD_LENGTH           = 65535;

our $MAX_PRIV_LOAD_LENGTH = 4194304;    # four megs

# This object must not be created in BEGIN {} or
# perlcc will crash because it will get stuck with
# a reference
our $XS_ConvertBlessed_obj;
our $XS_RelaxedConvertBlessed_obj;
our $XS_NoSetUTF8RelaxedConvertBlessed_obj;
our $XS_NoSetUTF8ConvertBlessed_obj;

our $VERSION = '2.5';

my $copied_boolean = 0;

sub DumpFile {
    my ( $file, $data ) = @_;

    if ( Cpanel::FHUtils::Tiny::is_a($file) ) {
        print {$file} Dump($data) || return 0;
    }
    else {
        if ( open( my $fh, '>', $file ) ) {
            print {$fh} Dump($data);
            close($fh);
        }
        else {
            return 0;
        }
    }
    return 1;
}

sub copy_boolean {

    # Required for compiled code.  Case 109225.
    if ( !$copied_boolean ) {
        *Types::Serialiser::Boolean:: = *JSON::PP::Boolean::;
        $copied_boolean               = 1;
    }
    return;
}

sub _create_new_json_object {
    copy_boolean() if !$copied_boolean;
    return JSON::XS->new()->shrink(1)->allow_nonref(1)->convert_blessed(1);
}

# Do not save these values as variables, as that causes segfaults.
sub true {
    copy_boolean() if !$copied_boolean;
    my $x = 1;
    return bless \$x, 'Types::Serialiser::Boolean';
}

sub false {
    copy_boolean() if !$copied_boolean;
    my $x = 0;
    return bless \$x, 'Types::Serialiser::Boolean';
}

# Useful for debugging.
sub pretty_dump {
    return _create_new_json_object()->pretty(1)->encode( $_[0] );
}

my $XS_Canonical_obj;

sub canonical_dump {
    return ( $XS_Canonical_obj ||= _create_new_json_object()->canonical(1) )->encode( $_[0] );
}

sub pretty_canonical_dump {
    return _create_new_json_object()->canonical(1)->indent->space_before->space_after->encode( $_[0] );
}

#NOTE: This can clobber $@.
sub Dump {
    return ( $XS_ConvertBlessed_obj ||= _create_new_json_object() )->encode( $_[0] );
}

#XXX: This currently will set the UTF-8 flag on the passed-in string!
#If that's a problem for you, then do:
#
#   Load("$json")
#
#...which will make a "throw-away" copy of the string that this function
#can do with as it pleases.
#
# Load* will throw an Cpanel::Exception::JSONParseError in the event
# the JSON cannot be parsed. This code is highly optimized to be able to
# read in a file that has a JSON encoded string on each line like
# Cpanel::Output writes.  Since we do this in a very tight loop and
# can easily read in 50k+ lines, its performance is very important.
#
# $_[0] == $data
# $_[1] == $path
sub Load {
    local $@;

    _replace_unicode_escapes_if_needed( \$_[0] );

    return eval { ( $XS_ConvertBlessed_obj ||= _create_new_json_object() )->decode( $_[0] ); } // ( ( $@ && _throw_json_error( $@, $_[1], \$_[0] ) ) || undef );
}

# $_[0] == $data
# $_[1] == $path
sub LoadRelaxed {
    local $@;

    _replace_unicode_escapes_if_needed( \$_[0] );

    return eval { ( $XS_RelaxedConvertBlessed_obj ||= _create_new_json_object()->relaxed(1) )->decode( $_[0] ); } // ( ( $@ && _throw_json_error( $@, $_[1], \$_[0] ) ) || undef );
}

sub _throw_json_error {
    my ( $exception, $path, $dataref ) = @_;

    local $@;
    require Cpanel::Exception;
    die $exception if $@;
    die 'Cpanel::Exception'->can('create')->( 'JSONParseError', { 'error' => $exception, 'path' => $path, 'dataref' => $dataref } );
}

#
# case CPANEL-2195: Editing Global Filters Breaks UTF-8 Characters
#
# no_set_utf8 is patched JSON::XS to not do SvUTF8_on (sv) in
# decode_str when passed a flag
#
# Cpanel::AdminBin::Serializer MUST ROUNDTRIP to UTF-8 BINARY STRINGS
# as we do not have control of the incoming data and it must be passed
# unmodified to the subprocess
#
# $_[0] == $data
# $_[1] == $path
sub LoadNoSetUTF8 {
    local $@;

    _replace_unicode_escapes_if_needed( \$_[0] );

    return eval { ( $XS_NoSetUTF8ConvertBlessed_obj ||= _create_new_no_set_utf8_json_object() )->decode( $_[0] ); } // ( ( $@ && _throw_json_error( $@, $_[1], \$_[0] ) ) || undef );
}

# $_[0] == $data
# $_[1] == $path
sub LoadNoSetUTF8Relaxed {
    local $@;

    _replace_unicode_escapes_if_needed( \$_[0] );

    return eval { ( $XS_NoSetUTF8RelaxedConvertBlessed_obj ||= _create_new_no_set_utf8_json_object()->relaxed(1) )->decode( $_[0] ); } // ( ( $@ && _throw_json_error( $@, $_[1], \$_[0] ) ) || undef );
}

sub _create_new_no_set_utf8_json_object {
    my $obj = _create_new_json_object();
    if ( $obj->can('no_set_utf8') ) {
        $obj->no_set_utf8(1);
    }
    else {
        warn "JSON::XS is missing the no_set_utf8 flag";
    }
    return $obj;
}

sub _replace_unicode_escapes_if_needed {
    my $json_r = shift;

    return unless defined $$json_r;
    if ( -1 != index( $$json_r, '\\u' ) ) {
        Cpanel::JSON::Unicode::replace_unicode_escapes_with_utf8($json_r);
    }

    return;
}

#----------------------------------------------------------------------
# XXX: The *LoadFile methods below accept values that are only relevant
# if there is an error. A better path might be to create an exception that
# doesn’t know the path, then, at a higher level that does know the path,
# do one of either:
#
# - add the path to the error, then rethrow
# - throw a new error that duplicates the old error but also has the path
#
# XXX TODO: Implement one of the above.
#
# This may also be the time to split these functions into two separate
# ones: one for a filehandle, and the other for a path.
#----------------------------------------------------------------------

# $_[0] == $file_or_fh
# $_[1] == $path
# $_[2] == $decode_utf8
sub SafeLoadFile {    # only allow a small bit of data to be loaded
    return _LoadFile( $_[0], $MAX_LOAD_LENGTH, $_[2] || $NO_DECODE_UTF8, $_[1], $LOAD_STRICT );
}

# $_[0] == $file_or_fh
# $_[1] == $path
# $_[2] == $decode_utf8
sub LoadFile {
    return _LoadFile( $_[0], $MAX_LOAD_LENGTH_UNLIMITED, $_[2] || $NO_DECODE_UTF8, $_[1], $LOAD_STRICT );
}

# $_[0] == $file_or_fh
# $_[1] == $path
# $_[2] == $decode_utf8
sub LoadFileRelaxed {
    return _LoadFile( $_[0], $MAX_LOAD_LENGTH_UNLIMITED, $_[2] || $NO_DECODE_UTF8, $_[1], $LOAD_RELAXED );
}

# $_[0] == $file_or_fh
# $_[1] == $max_load_length
# $_[2] == $path to the file (this will be in the exception on error)
sub LoadFileNoSetUTF8 {
    return _LoadFile( $_[0], $_[1] || $MAX_LOAD_LENGTH_UNLIMITED, $DECODE_UTF8, $_[2], $LOAD_STRICT );
}

#Copied and slightly tweaked from JSON::Syck;
#
#NOTE: This can clobber $@ and $!.
#
sub _LoadFile {
    my ( $file, $max, $decode_utf8, $path, $relaxed ) = @_;

    my $data;
    if ( Cpanel::FHUtils::Tiny::is_a($file) ) {
        if ($max) {
            my $togo = $max;
            $data = '';
            my $bytes_read;
            while ( $bytes_read = read( $file, $data, $togo, length $data ) && length $data < $max ) {
                $togo -= $bytes_read;
            }
        }
        else {
            Cpanel::LoadFile::ReadFast::read_all_fast( $file, $data );
        }
    }
    else {
        local $!;
        open( my $fh, '<:stdio', $file ) or do {
            my $err = $!;

            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess("Cannot open “$file”: $err");
        };
        Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data );
        if ( !length $data ) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess("“$file” is empty.");
        }
        close $fh or warn "close($file) failed: $!";
    }

    if ( $decode_utf8 && $decode_utf8 == $DECODE_UTF8 ) {

        # Without this, if we read a filename from a JSON file, using it in open
        # or sysopen results in double-encoding.
        Cpanel::UTF8::Strict::decode($data);

        return $relaxed ? LoadNoSetUTF8Relaxed( $data, $path || $file ) : LoadNoSetUTF8( $data, $path || $file );
    }

    return $relaxed ? LoadRelaxed( $data, $path || $file ) : Load( $data, $path || $file );
}

#so that </script> becomes <\/script> in HTML, to prevent XSS attacks
#Note that the output from this is still valid JSON and will be interpreted
#correctly in browser JSON parsers (but NOT JSON::Syck as of v0.38).
#
#NOTE: This can clobber $@.
#
sub SafeDump {
    my $raw_json = ( $XS_ConvertBlessed_obj ||= _create_new_json_object() )->encode( $_[0] );
    $raw_json =~ s{\/}{\\/}g if $raw_json =~ tr{/}{};
    return $raw_json;
}

#Returns two things:
#1) whether the file handle's data "looks like" valid JSON
#2) the # of bytes that we read from the file handle to make that determination
sub _fh_looks_like_json {
    my ($fh) = @_;

    my $bytes_read = 0;

    my $buffer = q{};

    local $!;

    #Loop until we have non-whitespace or we're at EOF.
    while ( $buffer !~ tr{ \t\r\n\f}{}c && !eof $fh ) {
        $bytes_read += ( read( $fh, $buffer, 1, length $buffer ) // die "read() failed: $!" );
    }

    return (
        _string_looks_like_json($buffer),
        \$buffer,
    );
}

#Looks at the first byte of the passed-in (NON-reference) string.
#Returns a boolean.
sub _string_looks_like_json {    ##no critic qw(RequireArgUnpacking)
                                 # $_[0]: str
    return $_[0] =~ m/\A\s*[\[\{"0-9]/ ? 1 : 0;
}

#NOTE: For now, this assumes that there is no leading whitespace.
#
#Accepts either a filehandle or a string. (Avoids copying the string.)
#If a filehandle, will seek() back to where it started .. so don't feed
#non-seekable filehandles into this!
sub looks_like_json {    ##no critic qw(RequireArgUnpacking)
                         # $_[0]: txt
    if ( Cpanel::FHUtils::Tiny::is_a( $_[0] ) ) {
        my $fh = $_[0];

        my ( $looks_like_json, $fragment_ref ) = _fh_looks_like_json($fh);
        my $bytes_read = length $$fragment_ref;

        if ($bytes_read) {
            seek( $fh, -$bytes_read, $Cpanel::Fcntl::Constants::SEEK_CUR ) or die "seek() failed: $!";
        }

        return $looks_like_json;
    }

    return _string_looks_like_json( $_[0] );
}

sub to_bool {
    my ($val) = @_;

    $val = 0 if defined $val && $val eq 'false';
    return !!$val ? true() : false();
}

1;
