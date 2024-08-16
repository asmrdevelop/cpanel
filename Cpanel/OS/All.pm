package Cpanel::OS::All;

# cpanel - Cpanel/OS/All.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use utf8;

use Cpanel::OS::Almalinux8  ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Almalinux9  ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Cloudlinux8 ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Cloudlinux9 ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Rocky8      ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Rocky9      ();    # PPI USE OK - fatpack usage
use Cpanel::OS::Ubuntu22    ();    # PPI USE OK - fatpack usage

# This test is mostly for unit testing.
sub supported_distros() {
    return (
        [ Almalinux  => 8 ],
        [ Almalinux  => 9 ],
        [ Cloudlinux => 8 ],
        [ Cloudlinux => 9 ],
        [ Rocky      => 8 ],
        [ Rocky      => 9 ],
        [ Ubuntu     => 22 ],
    );
}

sub advertise_supported_distros() {

    my $current_name;
    my $current_versions = [];

    my $advertise = '';

    my $map_os_display_name = {
        'Almalinux'  => 'AlmaLinux',
        'Rhel'       => 'Red Hat Enterprise Linux',
        'Cloudlinux' => 'CloudLinux&reg;',
        'Rocky'      => 'Rocky Linux&trade;',
    };

    foreach my $d ( supported_distros() ) {
        my ( $name, $version ) = $d->@*;

        if ( !defined $current_name ) {
            $current_name = $name;
            push $current_versions->@*, $version;
            next;
        }

        if ( $current_name eq $name ) {
            push $current_versions->@*, $version;
        }
        else {
            my $display_name = $map_os_display_name->{$current_name} // $current_name;
            $advertise .= $display_name . ' ' . join( '/', $current_versions->@* ) . ', ';
            $current_name     = $name;
            $current_versions = [$version];
        }
    }

    if ( defined $current_name ) {
        my $display_name = $map_os_display_name->{$current_name} // $current_name;
        $advertise .= $display_name . ' ' . join( '/', $current_versions->@* );
    }

    return $advertise;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::All - Load all Cpanel::OS supported distributions

=head1 SYNOPSIS

    use Cpanel::OS::All;

    foreach my $supported ( Cpanel::OS::All::supported_distros() ) {
        my ( $distro_name, $distro_major ) = $supported->@*;
        ...
    }

=head1 DESCRIPTION

This module is used to load all Cpanel::OS supported distributions.
So we can use to fatpack all Cpanel::OS::* with a single package.

=head1 FUNCTIONS

=head2 supported_distros()

Returns a list with all supported distribution.

=head2 advertise_supported_distros()

Return a string with the list of the supported distribution we can use
to display to customers.
