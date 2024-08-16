package Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/DeliveryForSuspendedAccounts/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::DeliveryForSuspendedAccounts::META

=head1 DESCRIPTION

Feature Showcase metadata for DeliveryForSuspendedAccounts

=cut

use parent                                   qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
use Cpanel::Email::Config::SuspendedDelivery ();

our $VERSION = '1.0';

=head1 FUNCTIONS

=head2 get_driver_name

Returns the driver name. This name is used as the filename for the touchfile
put in the C</var/cpanel/activate/features/> directory.

=cut

use constant get_driver_name => 'delivery_for_suspended_accounts';

=head2 content

Defines the content used in the Feature Showcase entry

=cut

sub content {
    my ($locale) = @_;

    unless ($locale) {
        require Cpanel::Locale;
        $locale = Cpanel::Locale->get_handle();
    }

    my $name = $locale->maketext('Delivery behavior for suspended cPanel accounts');

    my $current_setting     = Cpanel::Email::Config::SuspendedDelivery::current_setting();
    my $recommended_setting = Cpanel::Email::Config::SuspendedDelivery::recommended_setting();

    my $abstract = '<p>' . $locale->maketext('Administrators can now configure what action the server should perform when an email message is sent to a suspended account. You can configure this new feature below:') . "</p>\n";

    foreach my $option_ar (
        [ Cpanel::Email::Config::SuspendedDelivery::DELIVER() => $locale->maketext( Cpanel::Email::Config::SuspendedDelivery::LABEL_DELIVER() ) ],
        [ Cpanel::Email::Config::SuspendedDelivery::DISCARD() => $locale->maketext( Cpanel::Email::Config::SuspendedDelivery::LABEL_DISCARD() ) ],
        [ Cpanel::Email::Config::SuspendedDelivery::BLOCK()   => $locale->maketext( Cpanel::Email::Config::SuspendedDelivery::LABEL_BLOCK() ) ],
        [ Cpanel::Email::Config::SuspendedDelivery::QUEUE()   => $locale->maketext( Cpanel::Email::Config::SuspendedDelivery::LABEL_QUEUE() ) ]
    ) {
        $abstract .= qq{<p><label style="width:auto"><input type="radio" value="$option_ar->[0]" name="suspended_account_deliveries"} . ( $option_ar->[0] eq $current_setting ? ' checked' : '' ) . "> $option_ar->[1] " . ( $option_ar->[0] eq $recommended_setting ? $locale->maketext('(recommended)') : '' ) . "</label></p>\n";
    }

    $abstract .= '<br><p>' . $locale->maketext( 'Set this configuration in WHM’s “[output,url,_1,Exim Configuration Manager,target,_blank]” interface (WHM » Home » Server Configuration » Exim Configuration Manager).', '[% CP_SECURITY_TOKEN %]/scripts2/basic_exim_editor?find=suspended_account_deliveries' ) . '</p>';

    return {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/suspended_account_deliveries',
        'name'   => {
            'long'   => $name,
            'short'  => $name,
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'version'  => $VERSION,
        'readonly' => 1,
        'abstract' => $abstract,
    };

}

=head2 showcase()

Determine how and if an item should appear in the showcase

=cut

sub showcase {
    return { 'is_recommended' => 1, 'is_spotlight_feature' => 0 };
}

1;
