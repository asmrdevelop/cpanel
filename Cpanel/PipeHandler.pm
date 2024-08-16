package Cpanel::PipeHandler;

# cpanel - Cpanel/PipeHandler.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::LoadModule ();

my @FDLIST;
my $hasPIPE  = 0;
my $lastpipe = 0;
my $pipetime = 0;

sub register_fds {
    push( @FDLIST, @_ );
}

sub pipeBGMgr {
    $hasPIPE++;

    $pipetime = time();
    if ( $hasPIPE == 1 ) {
        $0 .= " - running in background (disconnected)";
        foreach my $fd (@FDLIST) {
            if ( fileno($fd) != 1 ) {
                close($fd);
            }
        }
        print STDERR "$0 [$$]: " . _carp_longmess('SIGPIPE received, process going into background');
        open( STDOUT, ">", "/dev/null" );
        $lastpipe = time();
    }
    elsif ( $pipetime > $lastpipe + 1 ) {
        print STDERR "$0 [$$]: " . _carp_longmess('Fatal SIGPIPE received');
        die "$$";
    }

    return;
}

sub pipeMgr {
    $hasPIPE++;

    if ( $hasPIPE > 2 ) { die "$$"; }

    print STDERR "$0 [$$]: " . _carp_longmess('SIGPIPE received');

    if ( $hasPIPE > 1 ) { die "$$"; }

    return;
}

sub _carp_longmess {
    Cpanel::LoadModule::load_perl_module('Cpanel::Carp') if !$INC{'Cpanel/Carp.pm'};
    goto \&Cpanel::Carp::safe_longmess;
}

1;
