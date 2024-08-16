package Cpanel::Server::Type::Profile::Constants;

# cpanel - Cpanel/Server/Type/Profile/Constants.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Profile::Constants - Constants needed for server profiles

=cut

use constant {
    DNSNODE      => "DNSNODE",
    DATABASENODE => "DATABASENODE",
    DNSONLY      => "DNSONLY",
    MAILNODE     => "MAILNODE",
    STANDARD     => "STANDARD"
};

our %PROFILE_CHILD_WORKLOADS = (
    MAILNODE() => ['Mail'],
);

1;
