package Cpanel::LoadModule::Name;

# cpanel - Cpanel/LoadModule/Name.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::LinkTest ();
use Cpanel::Exception           ();

sub get_module_names_from_directory {
    my ($dir) = @_;

    die "List context only!" if !wantarray;

    my @names;

    if ( Cpanel::FileUtils::LinkTest::get_type($dir) ) {
        local $!;

        opendir( my $dh, $dir ) or die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $dir, error => $! ] );

        @names = map { length $_ > 3 && substr( $_, -3, 3, '' ) eq '.pm' ? $_ : () } readdir $dh;    ## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $dir, error => $! ] ) if $!;

        closedir $dh or warn "Failed to close directory $dir: $!";
    }

    return @names;
}

1;
