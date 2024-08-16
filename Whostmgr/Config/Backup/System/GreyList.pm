package Whostmgr::Config::Backup::System::GreyList;

# cpanel - Whostmgr/Config/Backup/System/GreyList.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::System::GreyList

=head1 DESCRIPTION

This module implements GreyList backups for inter-server configuration
transfers.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Backup::Base::JSON );

use Cpanel::GreyList::Config                      ();
use Cpanel::GreyList::Handler                     ();
use Cpanel::GreyList::CommonMailProviders::Config ();

#----------------------------------------------------------------------

sub _get_backup_structure ($self) {
    my $providers_conf_hr = Cpanel::GreyList::CommonMailProviders::Config::load();
    $providers_conf_hr->{'provider_config'} = delete $providers_conf_hr->{'common_mail_providers'};
    delete $_->{'display_name'} for values %{ $providers_conf_hr->{'provider_config'} };

    my $general_hr = Cpanel::GreyList::Config::loadconfig();

    # First argument is unused (internally, even).
    # 2nd means to return data rather than a JSON string.
    my $trusted        = Cpanel::GreyList::Handler->new()->read_trusted_hosts( undef, 1 );
    my @trusted_backup = map {
        { %{$_}{ 'host_ip', 'comment' } }
    } @$trusted;

    my %config = (
        is_enabled => delete $general_hr->{'is_enabled'},

        general => $general_hr,

        common_mail_providers => $providers_conf_hr,

        trusted_hosts => \@trusted_backup,
    );

    return \%config;
}

1;
