package Cpanel::Themes::Utils;

# cpanel - Cpanel/Themes/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

##
# Cpanel::Themes::Utils
#
# This module provides static methods intended for various operations around themes & theme management
###

use strict;
use Cpanel::Validate::FilesystemNodeName ();

our $CPANEL_THEMES_DOCROOT  = '/usr/local/cpanel/base/frontend';
our $WEBMAIL_THEMES_DOCROOT = '/usr/local/cpanel/base/webmail';

*get_theme_root = \&get_cpanel_theme_root;

sub get_cpanel_theme_root {
    my ($theme) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($theme);
    return "$CPANEL_THEMES_DOCROOT/$theme/";
}

sub get_webmail_theme_root {
    my ($theme) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($theme);
    return "$WEBMAIL_THEMES_DOCROOT/$theme/";
}

sub get_theme_from_theme_root {
    my ($docroot) = @_;

    $docroot =~ s{/+}{/}g;

    if ( $docroot =~ m{^\Q$CPANEL_THEMES_DOCROOT\E/([^/]+)} ) {
        return $1;
    }
    elsif ( $docroot =~ m{^\Q$WEBMAIL_THEMES_DOCROOT\E/([^/]+)} ) {
        return $1;
    }

    require Cpanel::Exception;
    die Cpanel::Exception::create( 'InvalidParameter', 'The path “[_1]” is not a valid cPanel theme document root.', [$docroot] );
}

sub theme_is_valid {
    my ($theme) = @_;

    my $theme_root = get_cpanel_theme_root($theme);
    return ( -d $theme_root ) ? 1 : 0;
}

1;
