package Whostmgr::Customization::Files;

# cpanel - Whostmgr/Customization/Files.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Customization::Files - Utility functions to work with files related to
customization, including data storage and css templates.

=head1 DESCRIPTION

This module provides file system support for the Customization system.
It provides authoritative locations for each applicable resource, such as the
css files and customization profiles.

=cut

use strict;
use warnings;

use Cpanel::JSON             ();
use Cpanel::LoadFile         ();
use Cpanel::Reseller         ();
use Cpanel::Themes::Fallback ();

=head1 METHODS

=cut

=head2 get_customization_file ($USER, $APPLICATION, $THEME)

Get the customization path for a reseller or root.

=head3 Arguments

=over 4

=item * $USER

Name of the reseller, required.

=item * $APPLICATION

Application for which the customization is intended, defaults to cpanel

=item * $THEME

Theme for which the customization is intended, defaults to jupiter

=back

=head3 Returns

Full path to the data file. Note: the path will be returned even if it may
not actually exist on disk.  Returns undef if the user is not a reseller.

=cut

sub get_customization_file {
    my ( $user, $application, $theme ) = @_;

    if ( !Cpanel::Reseller::isreseller($user) ) {
        return undef;
    }

    $application ||= 'cpanel';
    $theme       ||= 'jupiter';

    my $path;

    if ( $user eq 'root' ) {
        $path = Cpanel::Themes::Fallback::get_global_directory('/brand');
    }
    else {
        $path = Cpanel::Themes::Fallback::get_global_directory("/resellers/$user");
    }

    my $file = $application . '_' . $theme . '.json';

    return $path . '/' . $file;
}

=head2 get_css_template ($USER, $APPLICATION, $THEME)

Get location of the css template used for customization

=head3 Arguments

=over 4

=item application

Application for which the customization is intended, defaults to cpanel

=item theme

Theme for which the customization is intended, defaults to jupiter

=back

=head3 Returns

Full path to the template file.

=cut

sub get_css_template {
    my ( $application, $theme ) = @_;

    $application ||= 'cpanel';
    $theme       ||= 'jupiter';
    my $base = $application eq 'webmail' ? '/usr/local/cpanel/base/webmail' : '/usr/local/cpanel/base/frontend';
    my $tt   = $base . '/' . $theme . '/theme_configurations/customizations/styles_template.tt';

    return $tt;
}

=head2 get_customization_data

Load customization information from data storage

=head3 Arguments

=over 4

=item file

Full path to the file where customization data is stored.

=back

=head3 Returns

Hash reference that contains customization data. Returns undef if file
does not exist or load fails.

=cut

sub get_customization_data {
    my ($file) = @_;

    my $json = Cpanel::LoadFile::load_if_exists($file);
    if ($json) {
        my $default_customization_data = Cpanel::JSON::Load($json);
        return $default_customization_data->{'default'};
    }

    return undef;
}

1;
