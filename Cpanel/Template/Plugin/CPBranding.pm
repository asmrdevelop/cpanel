# cpanel - Cpanel/Template/Plugin/CPBranding.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::CPBranding;

=head1 NAME

Cpanel::Template::Plugin::CPBranding

=head1 SYNOPSIS

    USE CPBranding;
    SET available_apps = CPBranding.get_application_from_available_applications(varcache.available_applications, "app_name");
    SET applications = CPBranding.flatten_available_applications(available_apps);
    SET customizations = CPBranding.get_customizations("logo-dark.svg", "logo-light.svg"))

=head1 DESCRIPTION

A Template Toolkit plugin that exposes Branding functionality.

=cut

use cPstrict;

use base 'Template::Plugin';
use Cpanel::Encoder::Tiny    ();
use Cpanel::StringFunc::Trim ();
use Cpanel::Themes::Get();

=head1 METHODS

=head2 $uri = file($FILENAME)

Returns a URI for a given file.

=cut

sub file {
    require Cpanel::Branding::Lite;
    return Cpanel::Branding::Lite::_file( $_[1], 1 );
}

=head2 $image_uri = image($FILENAME)

Returns a URI for a given image.

=cut

sub image {
    require Cpanel::Branding::Lite;
    return Cpanel::Branding::Lite::_image( $_[1], 1 );
}

=head2 flatten_available_applications ($APPLICATIONS)

Exposes this function from Cpanel::DynamicUI::App.

=cut

sub flatten_available_applications {
    require Cpanel::DynamicUI::App;
    return Cpanel::DynamicUI::App::flatten_available_applications( $_[1] );
}

=head2 get_application_from_available_applications ($APPLICATIONS, $APPLICATION_NAME)

Exposes this function from Cpanel::DynamicUI::App.

=cut

sub get_application_from_available_applications {
    require Cpanel::DynamicUI::App;
    return Cpanel::DynamicUI::App::get_application_from_available_applications( @_[ 1 .. $#_ ] );
}

=head2 get_implementer_from_available_applications ($APPLICATIONS, $IMPLEMENTER)

Exposes this function from Cpanel::DynamicUI::App.

=cut

sub get_implementer_from_available_applications {
    require Cpanel::DynamicUI::App;
    return Cpanel::DynamicUI::App::get_implementer_from_available_applications( @_[ 1 .. $#_ ] );
}

sub _process_customizations ( $app = "cpanel", $theme = Cpanel::Themes::Get::cpanel_default_theme() ) {
    require Whostmgr::Customization::Brand;
    my $branding_owner = $Cpanel::CPDATA{'OWNER'};

    unless ($branding_owner) {
        require Cpanel::AcctUtils::Owner;
        $branding_owner = Cpanel::AcctUtils::Owner::getowner($Cpanel::user);
    }

    my $result = Whostmgr::Customization::Brand::process_customization(
        'user'        => $branding_owner,
        'application' => $app,
        'theme'       => $theme
    );
    return $result;
}

=head2 get_customizations($logo_path_for_dark_background, $logo_path_for_light_background)

Get cPanel user customization data and return it as a hash.

=head3 Arguments

=over 2

=item * logo_path_for_dark_background

The path to the dark background logo.

=item * logo_path_for_light_background

The path to the light background logo.

=back

=head3 Returns

A hash reference that contains customization data.  The data consists of paths for
customization resources (such as logos or stylesheet).  Each path is in URI format,
giving their path relative to docroot, including a MagicRevision header.

    {
        'stylesheet'     => '/cPanel_magic_revision_##########/frontend/path/to/stylesheet',
        'header_logo'    => '/cPanel_magic_revision_##########/frontend/path/to/header_logo',
        'main_menu_logo' => '/cPanel_magic_revision_##########/frontend/path/to/main_menu_logo'
    }

=cut

sub get_customizations {
    my ( $self, $logo_path_for_dark_background, $logo_path_for_light_background, $favicon_path, $app, $theme ) = @_;

    require Cpanel::MagicRevision;
    my $logo_for_dark_background  = Cpanel::MagicRevision::calculate_theme_relative_magic_url($logo_path_for_dark_background);
    my $logo_for_light_background = Cpanel::MagicRevision::calculate_theme_relative_magic_url($logo_path_for_light_background);
    my $favicon                   = Cpanel::MagicRevision::calculate_theme_relative_magic_url($favicon_path);

    my $customizations = _process_customizations( $app, $theme );

    my $data = { 'stylesheet' => $customizations->{'stylesheet'} };

    my $custom_favicon = Cpanel::StringFunc::Trim::ws_trim( $customizations->{'favicon'} );
    $data->{'favicon'} = 'data:image/x-icon;base64,' . $custom_favicon if length $custom_favicon;

    my $imageType                    = 'data:image/svg+xml;base64,';
    my $use_default_logo_description = 0;

    my $custom_logo_for_light_background = Cpanel::StringFunc::Trim::ws_trim( $customizations->{'custom_logo_data'}->{'forLightBackground'} );
    $custom_logo_for_light_background = $imageType . $custom_logo_for_light_background if length $custom_logo_for_light_background;

    my $custom_logo_for_dark_background = Cpanel::StringFunc::Trim::ws_trim( $customizations->{'custom_logo_data'}->{'forDarkBackground'} );
    $custom_logo_for_dark_background = $imageType . $custom_logo_for_dark_background if length $custom_logo_for_dark_background;

    # If supplied custom logos use them
    if ( $custom_logo_for_dark_background && $custom_logo_for_light_background ) {

        # Always set the header logo to be logo for light background
        $data->{'header_logo'} = $custom_logo_for_light_background;

        # Always set the main menu logo to be logo for dark background if user has not provided a primary color
        $data->{'main_menu_logo'} = $custom_logo_for_dark_background;

        # Determine which logo to use based on the primary color supplied
        if ( defined( $customizations->{'primary_color_is_dark'} )
            && $customizations->{'primary_color_is_dark'} == 0 ) {
            $data->{'main_menu_logo'} = $custom_logo_for_light_background;
        }
    }
    elsif ($custom_logo_for_light_background) {

        # If only dark background logo is supplied, use it
        $data->{'header_logo'} = $data->{'main_menu_logo'} = $custom_logo_for_light_background;
    }
    elsif ($custom_logo_for_dark_background) {

        # If only light background logo is supplied, use it
        $data->{'header_logo'} = $data->{'main_menu_logo'} = $custom_logo_for_dark_background;
    }
    else {
        $use_default_logo_description = 1;

        # Use cPanel logos if none are supplied.
        $data->{'header_logo'}    = $logo_for_light_background;
        $data->{'main_menu_logo'} = $logo_for_dark_background;

        # Checks to make sure primary color is provided during customization
        # and its a light color
        if ( defined( $customizations->{'primary_color_is_dark'} )
            && $customizations->{'primary_color_is_dark'} == 0 ) {
            $data->{'main_menu_logo'} = $logo_for_light_background;
        }
    }

    if ( !$use_default_logo_description && defined( $customizations->{'custom_logo_data'}->{'description'} ) ) {
        $data->{'logo_description_html'} = Cpanel::Encoder::Tiny::safe_html_encode_str( $customizations->{'custom_logo_data'}->{'description'} );
    }

    # Add help and documentation links (if present)
    $data->{'documentation_url'} = $customizations->{'documentation_url'} || 'https://go.cpanel.net/cpaneldocsHome';
    $data->{'help_url'}          = $customizations->{'help_url'}          || '';

    # if ( $customizations->{'documentation_url'} ) {
    #     $data->{'documentation_url'} = 'documentation url';
    # }
    # else {
    #     $data->{'documentation_url'} = 'no documentation url';
    # }

    return $data;
}

1;
