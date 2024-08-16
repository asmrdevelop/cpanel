package Cpanel::Template::Plugin::Ports;

# cpanel - Cpanel/Template/Plugin/Ports.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::DAV::Ports ();

=head1 FUNCTIONS

=head2 get_ports

Gets the important ports used in WebDAV, CalDAV and CardDAV.

Arguments

  $type - String - Type of ports to return. Currently supports any of:

    dav - dav related ports.

Returns

  - Hash Ref - Ports in name/value pairs. SSL ports always contain the string "SSL" in key.
  Non-ssl pors always contain the string "NO_SSL".

=cut

sub _get_ports {
    my ($type) = @_;
    $type //= '';

    my %ports;

    if ( $type =~ /^dav$/i ) {
        my $dav_ports = Cpanel::DAV::Ports::get_ports();
        %ports = ( %ports, %$dav_ports );
    }

    return \%ports;
}

sub new {
    my ($class) = @_;
    my $plugin = { 'get_ports' => \&_get_ports };

    return bless $plugin, $class;
}

1;
