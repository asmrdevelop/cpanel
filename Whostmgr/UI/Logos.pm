package Whostmgr::UI::Logos;

# cpanel - Whostmgr/UI/Logos.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::UI::Logos

=head1 SYNOPSIS

    my %logo_name_path = %Whostmgr::UI::Logos::NAME_PATH;

=head1 DESCRIPTION

This module stores logo data for WHM’s UI.

=cut

#----------------------------------------------------------------------

=head1 GLOBALS

=head2 %NAME_PATH

Correlates a code-name for the logo with its path
relative to WHM’s document root.

B<IMPORTANT:> As with all such resources, be sure you apply
MagicRevision (cf. L<Cpanel::MagicRevision>) to these paths
before putting them into an HTML document.

=cut

our %NAME_PATH = (

    # NB: These values get altered below!
    WhmWhiteLg => "whm-logo-white.svg",
    WhmDarkLg  => "whm-logo-dark.svg",
);

substr( $_, 0, 0, '/core/web-components/dist/assets/' ) for values %NAME_PATH;

1;
