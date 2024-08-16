package Cpanel::Template::Plugin::SQM;

# cpanel - Cpanel/Template/Plugin/SQM.pm           Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base 'Template::Plugin';

use Cpanel::Imports;
use Cpanel::Plugins::RestApiClient ();
use Cpanel::JSON                   ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::SQM - Template Toolkit plugin for Site Quality Monitoring

=head1 SYNOPSIS

    [% use SQM %]

    [% SQM.health_check %]

=cut

=head2 new

Returns a 'Cpanel::Template::Plugin::SQM' object.

=cut

sub new {
    return bless {}, 'Cpanel::Template::Plugin::SQM';
}

=head2 health_check

This method will hit the health check Koality endpoint that returns data
on the health of the Koality service.

Returns a hash of the returned data from the health check endpoint.

=cut

sub health_check ($self) {

    my $health_status;
    eval {
        my $api = Cpanel::Plugins::RestApiClient->new();
        $api->base_url('https://auth.koalityengine.com/');
        $api->endpoint('health');
        my $response = $api->run();
        $health_status = Cpanel::JSON::Load($response);
    };
    if ( my $exception = $@ ) {
        logger()->error("There was a problem contacting the Koality health check: $exception");
    }

    return $health_status;
}

1;
