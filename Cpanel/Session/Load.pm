package Cpanel::Session::Load;

# cpanel - Cpanel/Session/Load.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Session::Encoder     ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Config::Session      ();

=encoding utf-8

=head1 NAME

Cpanel::Session::Load - Tools for loading and checking for the existance of cPanel sessions

=head1 SYNOPSIS

    use Cpanel::Session::Load ();

    my $session_ref = Cpanel::Session::Load::loadSession('sessionid');

    my $exists = Cpanel::Sesison::Load::session_exists('sessionid');

=cut

use constant _ENOENT => 2;

sub loadSession {
    my ($session) = @_;

    my $ob = get_ob_part( \$session );

    return {} if !is_valid_session_name($session);

    my $session_file  = get_session_file_path($session);
    my $session_cache = $Cpanel::Config::Session::SESSION_DIR . '/cache/' . $session;
    my $session_ref;
    my $mtime;

    my $session_fh;
    my $session_cache_fh;

    # Load from Cpanel::AdminBin::Serializer  cache
    if ( $session_cache_fh = _open_if_exists_or_warn($session_cache) ) {

        # we do not want to lock here since Cpanel::AdminBin::Serializer will not load a half written file anyways
        # the lock can slow down cpsrvd by 200+%
        # we will fall back to reading the nonCpanel::AdminBin::Serializer version below if there is a problem
        eval {
            local $SIG{__DIE__};
            $session_ref = Cpanel::AdminBin::Serializer::LoadFile($session_cache_fh);    # pretrieve does not have to be AUTOLOADER
            $mtime       = ( stat($session_cache_fh) )[9];
        };
    }

    if ( !keys %$session_ref ) {
        if ( $session_fh = _open_if_exists_or_warn($session_file) ) {
            require Cpanel::Config::LoadConfig;
            $session_ref = Cpanel::Config::LoadConfig::parse_from_filehandle(
                $session_fh,
                delimiter => '=',
            );

            $mtime = ( stat($session_fh) )[9];
        }
    }

    if ( keys %$session_ref ) {
        $mtime ||= 0;
        my $time = $main::now || time();
        if ( ( $mtime + $Cpanel::Config::Session::SESSION_EXPIRE_TIME ) > $time ) {

            # Update mtime to prevent expiration if it is not already expired.
            # Perl allows us to do this in a single statement, but the kernel
            # does them one at a time, so to have proper error checking we also
            # do them one at a time.

            utime( $time, $time, $session_fh || $session_file ) or warn "utime($session_file): $!";

            if ($session_cache_fh) {
                utime( $time, $time, $session_cache_fh ) or warn "utime($session_cache): $!";
            }
        }
        else {
            $session_ref->{'expired'} = 1;
        }

        my $encoder = $ob && Cpanel::Session::Encoder->new( 'secret' => $ob );

        $session_ref->{'pass'} = $encoder->decode_data( $session_ref->{'pass'} ) if $encoder && length $session_ref->{'pass'};
    }

    return $session_ref;
}

sub _open_if_exists_or_warn {
    my $rfh;

    open $rfh, '<:stdio', $_[0] or do {
        undef $rfh;

        if ( $! != _ENOENT() ) {
            warn "open($_[0]): $!";
        }
    };

    return $rfh;
}

sub get_ob_part {
    my ($session_name_ref) = @_;

    # Skip if string is empty.
    $$session_name_ref or return undef;

    my $ob;
    if ( $$session_name_ref =~ s/,([0-9a-f]{1,64})$// ) {
        $ob = $1;
    }
    return $ob;
}

sub get_session_file_path {
    return $Cpanel::Config::Session::SESSION_DIR . '/raw/' . $_[0];
}

sub is_valid_session_name {
    my ($session_name) = @_;
    return 0 if ( !defined $session_name );                                            # Prevent the regex from parsing undef.
    return $session_name !~ tr{:A-Za-z0-9_\+\%\@\.\-\!\#\$\=\?\^\{\}\~}{}c ? 1 : 0;    # this list of chars must not include '/'
}

# session_exist must guarantee _ will stat the session file
sub session_exists {
    my ($session) = @_;
    get_ob_part( \$session );
    return is_valid_session_name($session) && -f get_session_file_path($session) ? 1 : 0;
}

sub session_exists_and_is_current {
    my ( $session, $now ) = @_;
    $now ||= time();
    return ( session_exists($session) && ( ( stat(_) )[9] + $Cpanel::Config::Session::SESSION_EXPIRE_TIME ) >= $now );
}

1;
