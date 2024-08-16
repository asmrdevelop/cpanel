package Cpanel::FileLookup;

# cpanel - Cpanel/FileLookup.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception          ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::SV                 ();

use constant _ENOENT => 2;

# A 4MiB max buffer size was choosen
# because this is the size of /etc/userdomainsdomains
# see on systems with a large number of domains.
#
# We do not want to choose a larger number since this
# means we will consume 4MiB of memory doing the lookup
#
# A larger buffer will minimize the number of sysread
# calls and tends to be much faster when
# restoring a large number of domains.  We must
# balance the buffer size with the memory requirements
#
my $max_buffer_size = 4194304;

sub filelookup {
    my ( $file, %OPTS ) = @_;
    my $key = $OPTS{'key'};

    # We use :stdio to avoid the slowness of PerlIO
    # since we will control the FH and only use
    # sysread this is safe.
    open my $file_fh, '<:stdio', $file or do {
        if ( $! != _ENOENT() ) {
            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $file, mode => '<', error => $! ] );
        }

        return;
    };

    #  When we are just looking for a single key we do a linear search by
    #  reading in blocks and checking it for the data we want
    #  Since we are only looking for a single key here we don't want to
    #  load the entire file in memory.
    #
    my $length = -f $file_fh && -s _;

    die "“$key” may not contain a “:”" if index( $key, ':' ) > -1;
    Cpanel::SV::untaint($key);
    substr( $key, 0, 4, '' ) if index( $key, 'www.' ) == 0;

    my $match         = "\n$key:";
    my $wwwmatch      = "\nwww.$key:";
    my $match_either  = "$key:";
    my $capture_match = qr/\n((?:www\.)?\Q$key\E:[^\n]*)/s;

    # if $bytes_read is smaller than $togo because read()
    # can be interrupted by a signal, this is not an error!
    #
    # See read(2) for more details.
    my $togo = $length;
    my $final_newline_position;
    my $bytes_read;
    my $final_newline_and_remainder;
    my $data = "\n";
    while ( $togo && ( $bytes_read = Cpanel::LoadFile::ReadFast::read_fast( $file_fh, $data, $togo > $max_buffer_size ? $max_buffer_size : $togo, length $data ) ) ) {
        $togo -= $bytes_read;
        $final_newline_position = rindex( $data, "\n" );

        $final_newline_and_remainder = ( $togo && $final_newline_position != -1 ) ? substr( $data, $final_newline_position, length $data, '' ) : "\n";

        # The index() checks here are optimizations to avoid the regexp
        # unless it’s needed.
        if ( index( $data, $match_either ) > -1 && ( index( $data, $match ) > -1 || index( $data, $wwwmatch ) > -1 ) && $data =~ $capture_match ) {
            my $line = $1;

            next if $line =~ m/^\s*#/;    # handle beginning of line comments

            my $val = ( split( /:/, $line, 2 ) )[1];

            $val =~ s/[\r\n]//g;
            $val =~ s/\s+#.*$//g;         # handle end of line comments
            $val =~ s/^\s+//;
            $val =~ s/\s+$//;

            return $val;
        }
        $data = $final_newline_and_remainder if $togo;
    }

    return;
}

1;
