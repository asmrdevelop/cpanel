package Cpanel::Security::Authn::APITokens::whostmgr;

# cpanel - Cpanel/Security/Authn/APITokens/whostmgr.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Security::Authn::APITokens::cpanel

=head1 DESCRIPTION

An end class of L<Cpanel::Security::Authn::APITokens> for WHM.

=cut

use parent qw( Cpanel::Security::Authn::APITokens );

use constant _SERVICE_NAME => 'whostmgr';

1;
