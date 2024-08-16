package Cpanel::Verify;

# cpanel - Cpanel/Verify.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::HTTP::Client ();
use Cpanel::JSON         ();

use Cpanel::Imports;

my $endpoint;

=head1 NAME

Cpanel::Verify - Calls the Verify service to get server licensing information.

=head1 SYNOPSIS

  # Get license data for the current box
  my $license_data = Cpanel::Verify::get_licenses();

  # Check if the box is eligible for a trial
  my $is_eligible = Cpanel::Verify::is_eligible_for_trial( $license_data );

=head1 METHODS

=head2 get_licenses( [$ip] )

Calls out to the Verify service to list all licenses for an ip.

=head3 Input:

=over

=item $ip (optional)

If an ip address is provided, the function will check the licenses for that
server. If no ip is provided it will use the current server's ip.

=back

=head3 Output:

Returns a hash ref of return data from Verify, containing both current and historic
license data. An undefined result means it connected, but cannot identify a data
block in the results.  It will throw an error on failure to connect or parse the
json results.

=cut

sub get_licenses {
    my ($ip) = @_;
    if ( !defined $ip ) { $ip = ""; }
    if ( $ip ne "" )    { $ip = "?ip=$ip"; }

    #Get the data
    local $@;
    my $response = eval {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
        $http->get( _get_endpoint() . $ip );
    };
    if ($@) {
        die locale()->maketext("Failure to reach [asis,Verify] service.");
    }

    #Parse the result.  If there's an exception or no valid data object, terminate.
    my $data = eval { Cpanel::JSON::Load( $response->{'content'} ); };

    if ( $@ || !defined $data ) {
        die locale()->maketext("Failure to parse response from [asis,Verify] service.");
    }

    #Check for the existence of "current" and "history" in the dataset.
    if ( !exists $data->{current} || !exists $data->{history} ) {
        die locale()->maketext("Missing data in response from [asis,Verify] service.");
    }

    #Ensure null fields are reported as empty arrays
    if ( !defined $data->{current} ) {
        $data->{current} = [];
    }
    if ( !defined $data->{history} ) {
        $data->{history} = [];
    }
    return $data;
}

=head2 is_eligible_for_trial( $license_data )

Parses license information from the Verify service to decide if a server is eligible
for a trial license.

=head3 Input:

=over

=item $license_data

This is a license data hash ref (as returned from get_licenses) that will be checked
for licenses that would make the given server ineligible for a trial license.

=back

=head3 Output:

Returns a boolean value. When true, the server is eligible for a trial license, based
on the provided license data.

=cut

sub is_eligible_for_trial {
    my ($license_data) = @_;

    if ( ref $license_data ne 'HASH' || !exists $license_data->{'current'} || !exists $license_data->{'history'} ) {
        die locale()->maketext("License data is invalid.");
    }

    for my $entry ( @{ $license_data->{'current'} }, @{ $license_data->{'history'} } ) {
        return 0 if $entry->{'basepkg'} == 1;
    }
    return 1;
}

sub _get_endpoint {
    if ( !$endpoint ) {
        require Cpanel::Config::Sources;
        $endpoint = Cpanel::Config::Sources::get_source('VERIFY_URL') . "/api/ipaddrs";
    }
    return $endpoint;
}

1;
