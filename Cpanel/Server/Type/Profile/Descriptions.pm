package Cpanel::Server::Type::Profile::Descriptions;

# cpanel - Cpanel/Server/Type/Profile/Descriptions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LocaleString ();

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Profile::Descriptions - Provide locale away descriptions for Cpanel::Server::Type::Profile

=head1 DESCRIPTION

Do not use this module directly.  See Cpanel::Server::Type::Profile.

This module only provides descriptions for Cpanel::Server::Type::Profile
in order to avoid including Cpanel::LocaleString in the base module

=cut

our %_META = (
    STANDARD => {
        name        => Cpanel::LocaleString->new("Standard"),
        description => Cpanel::LocaleString->new("This profile provides all services and access to every [asis,cPanel] feature."),
    },
    MAILNODE => {
        name        => Cpanel::LocaleString->new("Mail"),
        description => Cpanel::LocaleString->new("This profile provides only services and [asis,cPanel] features that allow the system to serve mail."),
    },
    DNSNODE => {
        name        => Cpanel::LocaleString->new("[asis,DNS]"),
        description => Cpanel::LocaleString->new("This profile provides only services and [asis,cPanel] features that allow the system to serve Domain Name System zones."),
    },
    DATABASENODE => {
        name        => Cpanel::LocaleString->new("Database"),
        description => Cpanel::LocaleString->new("This profile provides only services and [asis,cPanel] features that allow the system to serve databases."),
    }
);

1;
