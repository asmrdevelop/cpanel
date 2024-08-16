package Cpanel::Validate::Component::Domain::HasDnsEntry;

# cpanel - Cpanel/Validate/Component/Domain/HasDnsEntry.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::Exception             ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ($domain) = @{$self}{ $self->get_validation_arguments() };

    if ( Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'ZONEEXISTS', $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL, $domain ) ) {
        die Cpanel::Exception::create(
            'DnsEntryAlreadyExists',
            'A DNS entry for “[_1]” already exists. You must remove this DNS entry from this server or all servers in the DNS cluster to proceed.',
            [$domain],
        );
    }

    return;
}

1;
