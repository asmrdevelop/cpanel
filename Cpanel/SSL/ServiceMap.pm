package Cpanel::SSL::ServiceMap;

# cpanel - Cpanel/SSL/ServiceMap.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Logger ();

my %SRVMAP = (
    'dovecot_imap' => 'dovecot',
    'dovecot_pop3' => 'dovecot',
    'smtp'         => 'exim',
    'dav'          => 'cpanel',
    'cpanel'       => 'cpanel'
);

my $logger;

=head1 NAME

Cpanel::SSL::ServiceMap

=head1 DESCRIPTION

Map system to lookup the name of the service group the service belongs. Services that share
a set of ssl certificate lookup rules will map to the same group name.

=head2 lookup_service_group

=head3 Purpose

From the service name, look up the SSL lookup rules group name.

=head3 Arguments

  service - name of the services

=head3 Returns

  string - name of the group of ssl certificate lookup rules.

=cut

sub lookup_service_group {

    my ($service) = @_;

    if ( !$service || !exists $SRVMAP{$service} ) {
        $logger = Cpanel::Logger->new() if !$logger;
        $service ||= '';
        $logger->warn("Failed to provide valid service argument: $service");
        return;
    }

    return $SRVMAP{$service};
}

1;
