package Cpanel::NSCD;

# cpanel - Cpanel/NSCD.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Binaries            ();
use Cpanel::NSCD::Constants     ();
use Cpanel::Socket::Constants   ();
use Cpanel::Socket::UNIX::Micro ();
use Cpanel::Pack                ();
use Cpanel::LoadFile::ReadFast  ();
use Cpanel::Autodie             ();

use Try::Tiny;

our $VERSION = '1.4';

my $nscd_binary_missing = 0;
my $nscd_binary;

use constant NSCD_VERSION => 2;
use constant INVALIDATE   => 10;

my @ALL_CACHES = ( 'group', 'passwd' );

# reqdata from nscd/nscd.c
my @REQUEST_TEMPLATE = (

    # request_header from nscd/nscd-client.h
    'version' => 'L',    #int32_t version;  /* Version number of the daemon interface.  */
    'type'    => 'L',    #request_type type;  /* Service requested.  */
    'key_len' => 'L',    #int32_t key_len;  /* Key length.  */

    # added into reqdata in nscd/nscd.c
    'dbname' => 'Z*',
);

sub clear_cache {
    my @CACHES = @_;

    if ( !@CACHES ) {
        @CACHES = @ALL_CACHES;
    }
    local $SIG{'PIPE'} = 'IGNORE';
    foreach my $cache (@CACHES) {
        next if !$cache;

        my $socket;
        socket( $socket, $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM, 0 );
        my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($Cpanel::NSCD::Constants::NSCD_SOCKET);
        my $err;
        my $pack = Cpanel::Pack->new( \@REQUEST_TEMPLATE );
        try {

            #connect() failure is nonfatal; it basically means that
            #NSCD is not running, so we have nothing to do in this function.
            if ( connect( $socket, $usock ) ) {
                my $msg = $pack->pack_from_hashref(
                    {
                        'version' => NSCD_VERSION,
                        'type'    => INVALIDATE,
                        'key_len' => 1 + length $cache,    #1 for the null byte
                        'dbname'  => $cache,
                    }
                );
                Cpanel::Autodie::syswrite_sigguard( $socket, $msg );
                my $buffer = -1;
                Cpanel::LoadFile::ReadFast::read_fast( $socket, $buffer, 16 );
                my $status = unpack( 'L', $buffer );
                if ($status) {
                    die "NSCD invalidate returned non-zero status: [$status]";
                }
            }
        }
        catch {
            $err = $_;

            local $@ = $err;
            warn;
        };

        if ($err) {
            my $nscd_binary = _get_nscd_binary_path() or return;
            nscd_is_running()                         or return;

            my $err;
            try {
                require Cpanel::SafeRun::Object;
                Cpanel::SafeRun::Object->new_or_die(
                    program => $nscd_binary,
                    args    => [ '--invalidate' => $cache ],
                );
            }
            catch {
                $err = $_;
                local $@ = $err;
                warn;
            };

            return 0 if $err;
        }
    }
    return 1;
}

sub _get_nscd_binary_path {
    if ( !$nscd_binary ) {
        return if $nscd_binary_missing;

        $nscd_binary = Cpanel::Binaries::path('nscd');
        unless ( -x $nscd_binary ) {
            $nscd_binary_missing = 1;
            return;
        }
    }
    return $nscd_binary;
}

1;
