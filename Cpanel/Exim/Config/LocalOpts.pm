package Cpanel::Exim::Config::LocalOpts;

# cpanel - Cpanel/Exim/Config/LocalOpts.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $EXIM_LOCALOPTS_CONFIG = '/etc/exim.conf.localopts';
our $_cached_config;

=encoding utf-8

=head1 NAME

Cpanel::Exim::Config::LocalOpts - Interface to /etc/exim.conf.localopts

=head1 SYNOPSIS

    use Cpanel::Exim::Config::LocalOpts;

    my $config_hr = Cpanel::Exim::Config::LocalOpts::get_exim_localopts_config();
    my $is_using_smart_host = Cpanel::Exim::Config::LocalOpts::is_using_smart_host();

=head1 DESCRIPTION

Provides access to the Exim configuration defined in /etc/exim.conf.localopts

=head1 FUNCTIONS

=cut

=head2 my $config_hr = get_exim_localopts_config()

Get the Exim localopts configuration

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<HASHREF>

Returns the key/value pairs from the /etc/exim.conf.localopts file

=back

=back

=cut

sub get_exim_localopts_config {

    # TODO: Implement a disk-based JSON cache with mtime checking
    return $_cached_config if $_cached_config;
    require Cpanel::Config::LoadConfig;
    $_cached_config = Cpanel::Config::LoadConfig::loadConfig($EXIM_LOCALOPTS_CONFIG) || {};
    return $_cached_config;
}

=head2 my $using_smart_host = is_using_smart_host()

Determines whether or not Exim is configured to use an external smart host

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

Returns truthy if there are smart host routes defined, falsey if not

=back

=back

=cut

sub is_using_smart_host {
    return !!get_exim_localopts_config()->{smarthost_routelist};
}

1;
