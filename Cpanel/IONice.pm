package Cpanel::IONice;

# cpanel - Cpanel/IONice.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use strict;
use warnings;
use Cpanel::Binaries        ();
use Cpanel::Debug           ();
use Cpanel::SafeRun::Simple ();

my $logger;
my %class_map = ( 'keep' => 0, 'idle' => 3, 'best-effort' => 2, 'real time' => 1 );

sub ionice {
    my ( $class, $class_data ) = @_;
    $class = $class_map{$class} if $class !~ /^[0-3]$/;

    if ( $class !~ /^[0-3]$/ ) {
        Cpanel::Debug::log_warn("ionice: class must be number from 0-3");
        return;
    }
    if ( $class_data !~ /^[0-7]$/ ) {
        Cpanel::Debug::log_warn("ionice: class_data must be number from 0-7");
        return;
    }
    my $ionice = Cpanel::Binaries::path('ionice');
    if ( -x $ionice ) {
        undef $class if $> != 0;

        # Putting $$ directly in the system statement means we change the ionice
        # process's PID.
        my $pid = $$;

        # If $class is 0 we explictly do not pass a class.
        Cpanel::SafeRun::Simple::saferun( $ionice, ( $class ? ( '-c', $class ) : () ), '-n', $class_data, '-p', $pid );
        return ( ( $? >> 8 ) == 0 ) ? 1 : 0;
    }
    else {

        # ionice is not installed, normal case for BSD.
        return;
    }
}

sub reset {
    my $ionice = Cpanel::Binaries::path('ionice');
    if ( -x $ionice ) {
        Cpanel::SafeRun::Simple::saferun( $ionice, '-c', 'none', '-p', $$ );
        return ( ( $? >> 8 ) == 0 ) ? 1 : 0;
    }
    return;
}

sub get_ionice {
    my $ionice = Cpanel::Binaries::path('ionice');
    if ( -x $ionice ) {
        my $ionice_current = Cpanel::SafeRun::Simple::saferun( $ionice, '-p', $$ );
        chomp($ionice_current);
        return $ionice_current;
    }
    else {

        # ionice not installed, normal case for BSD.
        # Don't fake a value, undef tells us this is unsupported.
        return;
    }
}

1;
