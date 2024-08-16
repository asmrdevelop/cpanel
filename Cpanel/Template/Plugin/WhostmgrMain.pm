package Cpanel::Template::Plugin::WhostmgrMain;

# cpanel - Cpanel/Template/Plugin/WhostmgrMain.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::WhostmgrMain

=head1 SYNOPSIS

    SET href = WhostmgrMain.final_menu_url(maybe_absolute);

=head1 DESCRIPTION

This plugin implements logic for WHM’s main page.

=cut

#----------------------------------------------------------------------

use parent 'Template::Plugin';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $url = final_menu_url($input_url)

Outputs a URL that’s suitable for use as the C<href> argument to
a hyperlink.

=cut

sub final_menu_url ( $, $input_url ) {

    # Absolute URLs are good to go.
    return $input_url if -1 != index( $input_url, '://' );

    # Paths need the security token prefix.

    # First ensure that there’s a leading slash:
    substr( $input_url, 0, 0, q</> ) if 0 != rindex( $input_url, '/', 0 );

    return ( ( $ENV{'cp_security_token'} // '' ) . $input_url );
}

1;
