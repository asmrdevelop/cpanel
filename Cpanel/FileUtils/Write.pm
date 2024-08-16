package Cpanel::FileUtils::Write;

# cpanel - Cpanel/FileUtils/Write.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Write - for (most of) your file-writing needs

=head1 SYNOPSIS

    Cpanel::FileUtils::Write::write( '/path/to/file', 'my content' );

    Cpanel::FileUtils::Write::overwrite( '/path/to/file', 'my content' );

=head1 DESCRIPTION

This module contains race-safe logic to write a file. All of the writers
in this function write out the file contents to a temporary file and then move
those contents into place. This provides race safety as well as protection
against partial file writes.

=head1 MEMORY USAGE

THIS MODULE IS CORE TO LOTS OF DAEMONS THAT HAVE LOW MEMORY REQUIREMENTS.
PLEASE CONSIDER PLACING NEW FUNCTIONS IN A NEW MODULE.

=cut

use Cpanel::Fcntl::Constants ();
use Cpanel::Autodie ( 'rename', 'syswrite_sigguard', 'seek', 'print', 'truncate' );
use Cpanel::Exception       ();
use Cpanel::FileUtils::Open ();
use Cpanel::Finally         ();
use Cpanel::Debug           ();

# We define Errno::EXIST explictly here because of memory requirements.
# Please see the note about about the LOW MEMORY REQUIREMENTS
our $Errno_EEXIST = 17;

our $MAX_TMPFILE_CREATE_ATTEMPTS = 1024;
my $DEFAULT_PERMS = 0600;
my $_WRONLY_CREAT_EXCL;

=head1 FUNCTIONS

=head2 write_fh(FH, CONTENT)

Given an already-open filehandle FH, rewind the filehandle, write CONTENT to it,
and then truncate it at the new length.

=cut

sub write_fh {    ##no critic qw(RequireArgUnpacking)
                  # $_[0]: fh
                  # $_[1]: content
    my $fh = $_[0];

    Cpanel::Autodie::seek( $fh, 0, 0 );
    Cpanel::Autodie::print( $fh, $_[1] );
    Cpanel::Autodie::truncate( $fh, tell($fh) );

    return 1;
}

=head2 write(FILENAME, CONTENT [, PERMS_OR_OPTSHR])

Write the string CONTENT to the file FILENAME.

Throws an exception if the file already exists. If you want to
clobber the filehandle instead, use C<overwrite()>.

PERMS_OR_OPTSHR, if given, should be either:

=over

=item * An octal number. B<NOTE:> this is
not a string made to look like an octal number.
The default value is 0600. Note also that, unlike the value given to
Perl’s C<syswrite> built-in, this is the
B<real> value that will be written to disk;
i.e., the process’s umask will have no effect.

=item * A hash reference of options (all optional):

=over

=item * C<before_installation> - callback that will run immediately
prior to the installation of the fully-written-out file. The callback
receives the filehandle to the file.
This is useful if you want to, e.g., C<chown()> the file prior to its being
installed so that there is never any point at which an invalid filesystem
state (e.g., a production file with improper ownership) exists.

=back

=back

This returns the filehandle to the file, which is useful, e.g.,
if you need to C<stat()> the file afterwards.

B<UNFORTUNATELY:> it also allows operations like C<chown()>.
This is the wrong way to do C<chown()> here, though; to maintain
system integrity, a chown() B<MUST> happen
in the C<before_installation> callback (see above).

=cut

sub write {
    return _write_to_tmpfile( @_[ 0 .. 2 ], \&_write_finish );
}

=head2 overwrite(FILENAME, CONTENT [, PERMS_OR_CALLBACK])

Like C<write()> but will overwrite any preexisting file.

=cut

sub overwrite {
    return _write_to_tmpfile( @_[ 0 .. 2 ], \&_overwrite_finish );
}

sub overwrite_no_exceptions {
    my $fh;

    local $@;
    eval {
        $fh = overwrite(@_);
        1;
    } or Cpanel::Debug::log_warn("overwrite exception: $@");

    # force a boolean context
    return !!$fh;
}

sub _write_to_tmpfile {    ##no critic qw(RequireArgUnpacking)
                           # $_[1]: content
    my ( $filename, $perms_or_hr, $finish_cr ) = ( $_[0], $_[2], $_[3] );

    if ( !defined $filename ) {
        exists $INC{'Carp.pm'} ? Carp::confess("write() called with undefined filename") : die("write() called with undefined filename");
    }

    if ( ref $filename ) {
        die "Use write_fh to write to a file handle. ($filename is a filehandle, right?)";
    }

    my ( $fh, $tmpfile_is_renamed );

    if ( -l $filename ) {
        require Cpanel::Readlink;
        $filename = Cpanel::Readlink::deep($filename);
    }

    #NOTE: Omitting local($!, $^E) per Release Team request.
    #TODO: Create a sysopen_with_real_perms that die()s on failure.

    my ( $callback_cr, $tmp_perms );

    if ( 'HASH' eq ref $perms_or_hr ) {
        $callback_cr = $perms_or_hr->{'before_installation'};
    }
    else {
        $tmp_perms = $perms_or_hr;
    }

    $tmp_perms //= $DEFAULT_PERMS;

    my ( $tmpfile, $attempts ) = ( '', 0 );

    while (1) {
        local $!;
        my $rand = rand(99999999);
        $rand = sprintf( '%x', substr( $rand, 2 ) );

        #Prefix the temp filename with a dot so that our various tools
        #that reject initial dot won’t see the temp file.
        my $last_slash_idx = rindex( $filename, '/' );
        $tmpfile = $filename;
        substr( $tmpfile, 1 + $last_slash_idx, 0 ) = ".tmp.$rand.";

        last if Cpanel::FileUtils::Open::sysopen_with_real_perms(
            $fh,
            $tmpfile,
            ( $_WRONLY_CREAT_EXCL ||= ( $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_WRONLY ) ),
            $tmp_perms,
        );

        if ( $! != $Errno_EEXIST ) {
            die Cpanel::Exception::create( 'IO::FileCreateError', [ error => $!, path => $tmpfile, permissions => $tmp_perms ] );
        }

        ++$attempts;
        if ( $attempts >= $MAX_TMPFILE_CREATE_ATTEMPTS ) {
            die Cpanel::Exception::create_raw( 'IO::FileCreateError', "Too many ($MAX_TMPFILE_CREATE_ATTEMPTS) failed attempts to create a temp file as EUID $> and GID $) based on “$filename”! The last tried file was “$tmpfile”, and the last error was: $!" );
        }
    }

    my $finally = Cpanel::Finally->new(
        sub {
            if ( !$tmpfile_is_renamed ) {
                Cpanel::Autodie::unlink_if_exists($tmpfile);

            }
            return;
        }
    );

    if ( my $ref = ref $_[1] ) {
        if ( $ref eq 'SCALAR' ) {
            _write_fh( $fh, ${ $_[1] } );
        }
        else {
            die Cpanel::Exception::create( 'InvalidParameter', 'Invalid content type “[_1]”, expect a scalar.', [$ref] );
        }
    }
    else {
        _write_fh( $fh, $_[1] );
    }

    $callback_cr->($fh) if $callback_cr;

    $tmpfile_is_renamed = $finish_cr->( $tmpfile, $filename );

    if ( !$tmpfile_is_renamed ) {
        Cpanel::Autodie::unlink_if_exists($tmpfile);
    }

    # No need to do the finally
    # since everything was successful
    $finally->skip();

    return $fh;
}

# overwritten in tests
*_syswrite = *Cpanel::Autodie::syswrite_sigguard;

our $DEBUG_WRITE;

sub _write_fh {
    if ( length $_[1] ) {
        my $pos = 0;

        # When a user’s disk quota fills up, write(2) doesn’t error unless
        # no bytes are written. So we need to detect partial writes and then
        # loop until we get an error.
        do {

            # SIGXFSZ is thrown when a write operation on a file
            # fails because of EFBIG. (cf. man 2 setrlimit)
            # We don’t want that to happen because we’re already
            # going to throw an exception. This is a similar situation
            # as with SIGPIPE and EPIPE.
            local $SIG{'XFSZ'} = 'IGNORE' if $pos;

            $pos += _syswrite( $_[0], $_[1], length( $_[1] ), $pos ) || do {

                # It’s not entirely clear from write(2)’s man page that a
                # nonerror zero-write can’t happen (return of undef). Just in case.
                die "Zero bytes written, non-error!";
            };
        } while $pos < length( $_[1] );
    }

    return;
}

sub _write_finish {

    # my ( $tmpfile, $filename ) = @_;
    Cpanel::Autodie::link(@_);
    return 0;
}

*_overwrite_finish = *Cpanel::Autodie::rename;

1;
