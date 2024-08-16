package Cpanel::Services::Running;

# cpanel - Cpanel/Services/Running.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Autodie                      ();

=encoding utf-8

=head1 NAME

Cpanel::Services::Running - Determine is a service is running or online.

=head1 SYNOPSIS

    use Cpanel::Services::Running;

    if ( Cpanel::Services::Running::is_online('tailwatchd') ) {
        # do something with tailwatchd
    }

=head2 is_online($service)

Returns 1 if $service is online or 0 if it is not.

This function throws an exception is a unknown or invalid
service name is passed.

=cut

sub is_online {
    my ($service) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($service);

    my $restartsrv_binary = "/usr/local/cpanel/scripts/restartsrv_$service";

    if ( !Cpanel::Autodie::exists($restartsrv_binary) ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'Services::Unknown', [ service => $service ] );
    }

    my $run = Cpanel::SafeRun::Object->new(
        'program' => $restartsrv_binary,
        'args'    => ['--check'],
    );

    # If error_code is not 0 $service is not running
    if ( $run->CHILD_ERROR() && $run->error_code ) {
        return 0;
    }

    return 1;
}

1;
