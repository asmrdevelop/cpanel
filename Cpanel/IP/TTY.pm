package Cpanel::IP::TTY;

# cpanel - Cpanel/IP/TTY.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Try::Tiny;

sub lookup_ipdata_from_tty {
    my ($tty) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Utmp');

    #utmp strips /dev from any entry
    my $search_tty = $tty;
    $search_tty =~ s{^/dev\/?}{};
    my ( $searched_utmp, $utmp_ipdata, $err );

    try {
        my $utmp   = Cpanel::Utmp->new();
        my $record = $utmp->find_most_recent( 'ut_line' => qr<\A\Q$search_tty\E\z> );
        $utmp_ipdata   = $record && $record->ip_address();
        $searched_utmp = 1;
    }
    catch {
        $err = $_;
    };

    if ($err) {
        return ( 0, "Error mapping TTY “$tty” to IP address: " . Cpanel::Exception::get_string($err) );
    }
    elsif ( $searched_utmp && !$utmp_ipdata ) {
        return ( 0, "No entry in utmp for TTY “$tty”." );
    }

    return ( 1, $utmp_ipdata );
}

my $_cached_current_tty_ip_address;

sub get_current_tty_ip_address {
    return ''                              if !-t STDIN;
    return $_cached_current_tty_ip_address if defined $_cached_current_tty_ip_address;

    my $stdin_fileno = fileno( \*STDIN );
    if ( my $tty = readlink("/proc/self/fd/$stdin_fileno") ) {
        my ( $lookup_ok, $ipdata_or_error ) = lookup_ipdata_from_tty($tty);

        if ($lookup_ok) {
            return ( $_cached_current_tty_ip_address = $ipdata_or_error );
        }
    }
    return '';
}

1;
