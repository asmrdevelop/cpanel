package Cpanel::Template::Plugin::Net;

# cpanel - Cpanel/Template/Plugin/Net.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Sort::Utils ();

use base 'Template::Plugin';

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'scalar', 'inet_aton', \&inet_aton );

    $context->define_vmethod( 'list', 'ipsort', \&Cpanel::Sort::Utils::sort_ip_list );

    return $class;
}

#SO WE DON'T HAVE TO BRING IN Socket
sub inet_aton {
    my $first_parm = shift;
    my @ip_split   = split /\./, ( ref $first_parm ? shift : $first_parm );
    return ( $ip_split[0] << 24 ) + ( $ip_split[1] << 16 ) + ( $ip_split[2] << 8 ) + $ip_split[3];
}

1;
