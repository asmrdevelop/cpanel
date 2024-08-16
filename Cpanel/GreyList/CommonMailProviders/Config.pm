package Cpanel::GreyList::CommonMailProviders::Config;

# cpanel - Cpanel/GreyList/CommonMailProviders/Config.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::GreyList::CommonMailProviders::Config

=cut

#----------------------------------------------------------------------

use Cpanel::GreyList::Config  ();
use Cpanel::GreyList::Handler ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $config_hr = load()

Aggregates the different properties for common
mail providers into a single data structure.

The return is a hashref with the following members:

=over

=item * C<autotrust_new_common_mail_providers> - boolean

=item * C<provider_properties> - A hashref whose keys are the provider
“code” name and whose values are hashrefs of:

=over

=item * C<display_name> - string

=item * C<is_trusted> - boolean

=item * C<autoupdate> - boolean

=back

=back

=cut

sub load {

    # NB: Not Cpanel::GreyList::Config because that module bails out if
    # the service is disabled. We want this to grab the configuration
    # regardless of whether the service is enabled or not.
    my $providers_in_db  = Cpanel::GreyList::Handler->new()->get_common_mail_providers();
    my %providers_lookup = map { ( $_ => 1 ) } keys %$providers_in_db;

    my $commmon_mail_providers_config = Cpanel::GreyList::Config::load_common_mail_providers_config( \%providers_lookup );

    my %output;

    $output{'autotrust_new_common_mail_providers'} = delete $commmon_mail_providers_config->{'autotrust_new_common_mail_providers'};

    foreach my $mail_provider ( keys %{$commmon_mail_providers_config} ) {
        next if not exists $providers_in_db->{$mail_provider};

        $output{'provider_properties'}{$mail_provider} = {
            %{ $providers_in_db->{$mail_provider} }{ 'display_name', 'is_trusted' },
            'autoupdate' => $commmon_mail_providers_config->{$mail_provider},
        };
    }

    return \%output;
}

1;
