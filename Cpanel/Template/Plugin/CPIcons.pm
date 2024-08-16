package Cpanel::Template::Plugin::CPIcons;

# cpanel - Cpanel/Template/Plugin/CPIcons.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Template::Plugin::CPIcons

=cut

use Cpanel::Locale ();

use strict;

use base 'Template::Plugin';

my $locale;
my $common_icons;

sub load {
    my ($class) = @_;

    # Fetch the locale from the stash if it exists
    $locale ||= Cpanel::Locale->get_handle();

    # Providing full urls to the icons that we want to manage with this component
    # Note: /cPanel_magic_revision_0 implies that the images will never ever expire.
    $common_icons = {
        'error' => {
            path  => '/cPanel_magic_revision_0/cjt/images/icons/error.png',
            title => $locale->maketext('Error'),
        },
        'success' => {
            path  => '/cPanel_magic_revision_0/cjt/images/icons/success.png',
            title => $locale->maketext('Success'),
        },
        'unknown' => {
            path  => '/cPanel_magic_revision_0/cjt/images/icons/unknown.png',
            title => $locale->maketext('Unknown'),
        },
        'warning' => {
            path  => '/cPanel_magic_revision_0/cjt/images/icons/warning.png',
            title => $locale->maketext('Warning'),
        },
    };

    return $class;
}

sub get_common_icon_path {
    my ( $plugin, $name, $size ) = @_;

    return _get_common_icon_path( $name, $size );
}

sub _get_common_icon_path {
    my ( $name, $size ) = @_;

    # assume that we want the 16 x 16 which are not decorated.
    my $path = $common_icons->{$name}->{'path'};

    # presently we only support 16 x 16 and 24 x 24
    if ( $path && $size && $size == 24 ) {
        $path =~ s/\.png/24.png/g;
    }

    return $path;
}

=head2 Function: get_common_icon_markup

Retrieves the markup for images based on the passed in rules.

Arguments:

=over

=item $plugin

=item $name

One of "error", "warning", "success", "unknown". If not in this set or undefined, the function
will return an empty string.

=item $size

One of 16 or 24.  16 represents the 16 x 16 pixel icons and 24 represents the 24 x 24 pixel
icon. Any other pixel sizes result in the routine returning an empty string.

=back

Returns:

Return markup for the <img> tag for the specific icon or an empty string if any parameters are
out of the predefined list as defined in the parameters above.

=cut

sub get_common_icon_markup {

    my ( $plugin, $name, $size ) = @_;

    # validate the inputs
    return '' if ( !defined $name );
    return '' if ( defined $size && ( $size != 16 && $size != 24 ) );

    my $path  = _get_common_icon_path( $name, $size );
    my $title = $common_icons->{$name}->{'title'};

    if ($path) {

        # we only support 16 x 16 and 24 x 24 at this time. 16 x 16 is the default if no size passed.
        if ( !$size || $size == 16 ) {
            return "<img class=\"status status16\" src=\"$path\" alt=\"$title\" title=\"$title\" width=\"16\" height=\"16\" />";
        }
        elsif ( $size == 24 ) {
            return "<img class=\"status status24\" src=\"$path\" alt=\"$title\" title=\"$title\" width=\"24\" height=\"24\" />";
        }
    }

    return "";
}

1;
