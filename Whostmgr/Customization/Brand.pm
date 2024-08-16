package Whostmgr::Customization::Brand;

# cpanel - Whostmgr/Customization/Brand.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Customization::Brand - Utility functions to help with creating
customized colors and logos for cPanel interfaces.

=head1 SYNOPSIS

    use Whostmgr::Customization::Brand ();

    Whostmgr::Customization::Brand::process_customization();

=cut

use strict;
use warnings;

use Template;

use Cpanel::Reseller ();

use Whostmgr::Customization::Files ();
use Whostmgr::Customization::Utils ();

=head1 METHODS

=cut

=head2 process_customization

Process user customization data and returns them as hash.

=head3 Arguments

=over 4

=item user

Name of the reseller. Defaults to root

=item application

Defaults to cpanel

=item theme

Defaults to jupiter

=back

=head3 Returns

Hash that contains customization data. If either style sheet template or customization
data is not available, returns empty hash.

=cut

sub process_customization {
    my %params = @_;

    my $user = $params{'user'};
    $user ||= 'root';

    my $application = $params{'application'};
    $application ||= 'cpanel';

    my $theme = $params{'theme'};
    $theme ||= 'jupiter';

    return {} unless Cpanel::Reseller::isreseller($user);

    my $customization_file = Whostmgr::Customization::Files::get_customization_file( $user, $application, $theme );
    my $customization_data = Whostmgr::Customization::Files::get_customization_data($customization_file);

    # if we can't find any customization data for the reseller, try system customization
    if ( $user eq 'root' ) {
        return {} unless $customization_data->{'brand'};
    }
    elsif ( !defined $customization_data->{'brand'} ) {
        $customization_file = Whostmgr::Customization::Files::get_customization_file( 'root', $application, $theme );
        $customization_data = Whostmgr::Customization::Files::get_customization_data($customization_file);
        return {} unless $customization_data->{'brand'};
    }

    my $css_template    = Whostmgr::Customization::Files::get_css_template( $application, $theme );
    my $calculated_data = _calculate_rgb($customization_data);

    # Generate styles using style template.
    my %style_vars = (
        'primary' => {
            'rgb'            => $calculated_data->{'primary-rgb'},
            'contrast_color' => { 'rgb' => $calculated_data->{'contrast-rgb'} },
        },
        'accent' => { 'rgb' => $calculated_data->{'accent-rgb'} },
    );

    my $tt = Template->new( { 'ABSOLUTE' => 1 } );
    my $generated_styles;

    if ( -f $css_template ) {
        $tt->process(
            $css_template,
            \%style_vars,
            \$generated_styles,
        ) or die $tt->error;
    }

    my $custom_data = {};

    if ( $customization_data->{'brand'}->{'logo'} ) {
        $custom_data->{'custom_logo_data'} = $customization_data->{'brand'}->{'logo'};
    }

    if ( $customization_data->{'brand'}{'favicon'} ) {
        $custom_data->{'favicon'} = $customization_data->{'brand'}{'favicon'};
    }

    if ( $calculated_data->{'primary-rgb'} ) {
        $custom_data->{'stylesheet'}            = $generated_styles;
        $custom_data->{'primary_color_is_dark'} = $calculated_data->{'primary-color-is-dark'};
    }

    # Set documentation and help URLs
    $custom_data->{'documentation_url'} = $customization_data->{'documentation'}{'url'};

    if ( $customization_data->{'help'}{'url'} ) {
        $custom_data->{'help_url'} = $customization_data->{'help'}{'url'};
    }

    return $custom_data;
}

sub _calculate_rgb {
    my ($data) = @_;
    my $calculated_data = {};
    if ( $data->{'brand'}->{'colors'}->{'primary'} ) {
        my $rgb         = {};
        my @primary_rgb = Whostmgr::Customization::Utils::hex2rgb( $data->{'brand'}->{'colors'}->{'primary'} );
        @{$rgb}{qw/r g b/} = @primary_rgb;
        $calculated_data->{'primary-rgb'} = $rgb;

        my $white = [ 255, 255, 255 ];
        my $black = [ 0,   0,   0 ];

        my $contrast_black = Whostmgr::Customization::Utils::contrast( $black, \@primary_rgb );
        my $contrast_white = Whostmgr::Customization::Utils::contrast( $white, \@primary_rgb );

        my $primary_color_is_dark = ( $contrast_black < $contrast_white ) ? 1      : 0;
        my $contrast              = $primary_color_is_dark                ? $white : $black;

        my $contrast_rgb = {};
        @{$contrast_rgb}{qw/r g b/} = @{$contrast};
        $calculated_data->{'contrast-rgb'}          = $contrast_rgb;
        $calculated_data->{'primary-color-is-dark'} = $primary_color_is_dark;
    }

    if ( $data->{'brand'}->{'colors'}->{'accent'} ) {
        my $rgb = {};
        @{$rgb}{qw/r g b/} = Whostmgr::Customization::Utils::hex2rgb( $data->{'brand'}->{'colors'}->{'accent'} );
        $calculated_data->{'accent-rgb'} = $rgb;
    }

    return $calculated_data;
}

1;
