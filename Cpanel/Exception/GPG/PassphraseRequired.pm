package Cpanel::Exception::GPG::PassphraseRequired;

# cpanel - Cpanel/Exception/GPG/PassphraseRequired.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::GPG::PassphraseRequired

=head1 SYNOPSIS

    Cpanel::Exception::create('GPG::PassphraseRequired', 'The secret key requires a passphrase.' );

=head1 DESCRIPTION

This exception indicates that a secret GPG key requires a passphrase.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
