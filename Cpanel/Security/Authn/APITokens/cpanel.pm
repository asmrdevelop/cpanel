package Cpanel::Security::Authn::APITokens::cpanel;

# cpanel - Cpanel/Security/Authn/APITokens/cpanel.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::cpanel

=head1 DESCRIPTION

An end class of L<Cpanel::Security::Authn::APITokens> for cpanel.

=cut

use parent qw( Cpanel::Security::Authn::APITokens );

use constant _SERVICE_NAME => 'cpanel';

1;
