package Cpanel::KernelCare::Suggest;

# cpanel - Cpanel/KernelCare/Suggest.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                    ();
use Cpanel::LoadModule               ();
use Cpanel::Locale                   ();
use Cpanel::KernelCare::Availability ();
use Cpanel::KernelCare               ();
use Cpanel::Exception                ();

=encoding utf-8

=head1 NAME

Cpanel::KernelCare::Suggest - Suggest KernelCare when relevant to avoid reboots

=head1 SYNOPSIS

    use Cpanel::KernelCare::Suggest;

    my $ref = Cpanel::KernelCare::Suggest::get_suggestion();

=head2 get_suggestion()

Return a suggested promotion for kernel care if it available based on the
servers advertising preferences.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<HASHREF>

    A hashref with preformatted text and suggestion in the following
    format:

    {
     'text' => 'Promotion Header',
     'suggestion' => 'Promotion Body'
    }

=back

=back

=cut

sub get_suggestion {
    my $kernelcare_state = Cpanel::KernelCare::get_kernelcare_state();
    if ( $kernelcare_state == $Cpanel::KernelCare::KC_UNKNOWN_PATCH_SET ) {

        return {
            'title'   => Cpanel::Locale::lh()->maketext('[asis,KernelCare] is installed, but it uses an unknown patch set.'),
            'details' => Cpanel::Locale::lh()->maketext('[asis,KernelCare] was found, but it is not currently active. The system cannot determine the patch set that [asis,KernelCare] uses. Please visit [asis,KernelCare] support to resolve this issue.'),
            'link'    => {
                'label'  => Cpanel::Locale::lh()->maketext('Visit [asis,KernelCare] Support'),
                'url'    => 'https://www.kernelcare.com/support/',
                'target' => '_blank'
            }
        };

    }
    elsif ( $kernelcare_state == $Cpanel::KernelCare::KC_MISSING || !_has_kc_default_patch_set($kernelcare_state) ) {

        # Abort if the customer requested we don't advertise - applies only to alert to pay for a license.
        my $advertising_preference = _get_advertising_preference();
        return if !$advertising_preference || $advertising_preference->{disabled};

        if ( $kernelcare_state == $Cpanel::KernelCare::KC_MISSING ) {

            # Alert that this IP has a valid KernelCare license, but the RPM is not installed (offer link to install it)
            my $promotion = Cpanel::Locale::lh()->maketext('KernelCare provides an easy and effortless way to ensure that your operating system uses the most up-to-date kernel without the need to reboot your server.');

            return {
                'title'   => Cpanel::Locale::lh()->maketext('Valid KernelCare License Found, but KernelCare is Not Installed.'),
                'details' => $promotion,
                'link'    => {
                    'label'  => Cpanel::Locale::lh()->maketext('Click to install'),
                    'url'    => '../scripts13/purchase_kernelcare_completion?order_status=success',
                    'target' => '_parent'
                }
            };
        }

        # Offer KernelCare upgrade to a paid license if KernelCare is either not installed or if KernelCare is installed and just the free patch set is applied
        #TODO - successful purchase flow handler needs to be updated to look for KC RPM/free patch set and merely apply default patch set if kernelcare is already installed
        elsif ( !_has_kc_default_patch_set($kernelcare_state) ) {
            my $link;
            if ( $advertising_preference->{'url'} ) {
                $link = {
                    'label'  => Cpanel::Locale::lh()->maketext('Upgrade to KernelCare'),
                    'url'    => $advertising_preference->{'url'},
                    'target' => '_parent'
                };
            }
            elsif ( $advertising_preference->{'email'} ) {
                $link = {
                    'label'  => Cpanel::Locale::lh()->maketext('For more information, contact your hosting provider.'),
                    'url'    => 'mailto:' . $advertising_preference->{'email'},
                    'target' => '_blank'
                };
            }
            else {
                Cpanel::LoadModule::load_perl_module('Whostmgr::KernelCare');
                my $price             = eval { Whostmgr::KernelCare->get_kernelcare_product_price() };
                my $get_kc_price_text = ( defined $price ) ? Cpanel::Locale::lh()->maketext( 'Get KernelCare for $[_1] per month.', $price ) : Cpanel::Locale::lh()->maketext('Get KernelCare.');
                $link = {
                    'label'  => $get_kc_price_text,
                    'url'    => '../scripts13/purchase_kernelcare_init',
                    'target' => '_parent'
                };
            }

            my $promotion = Cpanel::Locale::lh()->maketext('KernelCare provides an easy and effortless way to ensure that your operating system uses the most up-to-date kernel without the need to reboot your server.');
            my $note      = Cpanel::Locale::lh()->maketext(q{After you purchase and install KernelCare, you can then obtain and install the KernelCare “Extra” Patchset, which includes symlink protection.});

            return {
                'title'   => Cpanel::Locale::lh()->maketext('Use KernelCare to automate kernel security updates without reboots.'),
                'details' => $promotion,
                'link'    => $link,
                'note'    => $note
            };
        }
    }
    return;
}

sub _get_advertising_preference {
    my $advertising_preference = eval { Cpanel::KernelCare::Availability::get_company_advertising_preferences() };
    if ( my $err = $@ ) {
        if ( ref $err && $err->isa('Cpanel::Exception::HTTP::Network') ) {    # If we can't get the network, assume connections to cPanel are blocked.
            $advertising_preference = { disabled => 0, url => '', email => '' };
        }
        elsif ( ref $err && $err->isa('Cpanel::Exception::HTTP::Server') ) {    # If cPanel gives an error code, give customers the benefit of the doubt.
            return;                                                             # No advertising.
        }
        else {
            my $error_as_string = Cpanel::Exception::get_string_no_id($err);
            Cpanel::Debug::log_warn("The system cannot check the KernelCare promotion preferences because of an error: $error_as_string");
            return;
        }
    }

    return $advertising_preference;
}

# default patch set is included in the extra patch set
sub _has_kc_default_patch_set {
    my $state = shift;
    return $state == $Cpanel::KernelCare::KC_DEFAULT_PATCH_SET || $state == $Cpanel::KernelCare::KC_EXTRA_PATCH_SET;
}

1;
