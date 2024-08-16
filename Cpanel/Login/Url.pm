
# cpanel - Cpanel/Login/Url.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Login::Url;

use strict;
use warnings;

use Cpanel::ProxyUtils      ();
use Cpanel::Services::Ports ();

=head1 NAME

Cpanel::Login::Url

=head2 generate_login_url

=head3 Purpose

    Generates the login url for a specific service

=head3 Arguments

    $service - string - One of: whostmgr, cpanel, webmail
    %opts    - hash   - Options including the following:
        trailing_separator_supplied_by_caller - boolean - if truthy suppresses the / after the port.

=head3 Returns

            boolean - whether the operation succeeded or failed
            string  - the reason for the success or failure

=cut

sub generate_login_url {

    my ( $service, %opts ) = @_;

    my $url;

    if ( Cpanel::ProxyUtils::proxied() ) {
        $url = Cpanel::ProxyUtils::proxyaddress( $service . 'd' );
    }
    elsif ( defined $ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on' ) {
        $url = 'https://' . $ENV{'HTTP_HOST'} . ':' . $Cpanel::Services::Ports::SERVICE{ $service . 's' };
    }
    else {
        $url = 'http://' . $ENV{'HTTP_HOST'} . ':' . $Cpanel::Services::Ports::SERVICE{$service};
    }

    if ( !$opts{trailing_separator_supplied_by_caller} ) {
        $url .= '/';
    }

    return $url;
}

1;
