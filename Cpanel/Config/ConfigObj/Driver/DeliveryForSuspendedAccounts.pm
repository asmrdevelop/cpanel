package Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts;

# cpanel - Cpanel/Config/ConfigObj/Driver/DeliveryForSuspendedAccounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::META ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts - Feature showcase for Delivery behavior for suspended cPanel accounts

=head1 DESCRIPTION

Feature Showcase driver for DeliveryForSuspendedAccounts

=cut

=head1 SYNOPSIS

    use Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts;

    Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::VERSION;

=cut

=head2 VERSION

alias to value of the $Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::META::VERSION

=cut

*VERSION = \$Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::META::VERSION;

=head2 handle_showcase_submission( FORMREF )

Saves the showcase submission.

=cut

# mocked in tests
our $_LOCALOPTS_PATH = '/etc/exim.conf.localopts';

sub handle_showcase_submission {
    my ( $self, $formref ) = @_;

    require Cpanel::Email::Config::SuspendedDelivery;
    require Cpanel::Transaction::File::LoadConfig;

    if ( Cpanel::Email::Config::SuspendedDelivery::set_value( $formref->{'suspended_account_deliveries'} ) ) {

        # Update exim.conf.localopts
        my $config = Cpanel::Transaction::File::LoadConfig->new(
            'path'               => $_LOCALOPTS_PATH,
            'delimiter'          => '=',
            'permissions'        => 0644,
            'allow_undef_values' => 1,
        );

        $config->set_entry( 'suspended_account_deliveries' => $formref->{'suspended_account_deliveries'} );
        () = $config->save_and_close( do_sort => 1 );
    }

    return;
}

1;
