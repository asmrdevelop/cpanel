package Cpanel::API::ServerInformation;

# cpanel - Cpanel/API/ServerInformation.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::API::ServerInformation

=head1 DESCRIPTION

UAPI for getting information about this server

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Serverinfo ();

our %API = (
    _needs_feature => 'serverstatus',
    get_services   => { allow_demo => 1 }
);

=head2 get_information

Returns the name, status, state, and software version where available for all services listed by
C<Cpanel::Status::get_monitored_services>

=head3 ARGUMENTS

None

=head3 RETURNS

Returns a list of hashes, one for each service or device being monitored, were each hash contains the following information about a single service

=over

=item name - string

Name of the service, device or metric

=item type - string

One of: service, metric or device

=item status - string | number

When the status if for a service, indicates weather or not the service is monitored

When the status if for disk, memory or similar resource, the value will be one of the following:

=over

=item -1 - Usage is > 90%

=item 0 - Usage is > 80%

=item 1 - Usage is < 80%

=back

=item value - string | number

When a string and the status if for a service, the value is one of the following:

=over

=item up - Service is up

=item down - Service is down

=item unknown - Service information is not accessible

=back

Other status are commonly numbers measuring the percent used or similar metrics.

=item error - string

Only present when the service information can not be accessed.

=back

=head3 THROWS

This methid attempts to return service status without throwing exceptions other than
those propogated through the system in extreme cases. Always check the result::errors list.

=head3 EXAMPLES

A successful result will populate the data entry

=head4 COMMAND LINE USAGE

uapi --user=[user] ServerInformation get_information --output=jsonpretty

    "data" : [
             {
                "status" : 1,
                "service" : "cpanellogd",
                "value" : "up"
             },
             {
                "status" : 1,
                "service" : "cpdavd",
                "value" : "up"
             },
             {
                "service" : "cphulkd",
                "status" : 1,
                "value" : "up"
             },{
                "service" : "exim",
                "status" : 1,
                "value" : "up",
                "version" : "exim-4.92-3.cp1178.x86_64",
             },
     ...
     ]

=head4 Template Toolkit

 SET result = execute("ServerInformation", "get_information");

 [% FOREACH service IN result.data %]
     <tr>
         <td class="statuscell">[% service.value %] </td>
     </tr>
 [% END %]

=cut

sub get_information {

    my ( $args, $result ) = @_;

    $result->data( Cpanel::Serverinfo::get_status() );

    return 1;

}

1;
