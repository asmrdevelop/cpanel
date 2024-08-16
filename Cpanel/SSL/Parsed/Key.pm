package Cpanel::SSL::Parsed::Key;

# cpanel - Cpanel/SSL/Parsed/Key.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Parsed::Key

=head1 SYNOPSIS

    $parsed->modulus()
    $parsed->ecdsa_curve_name();
    $parsed->ecdsa_public();
    $parsed->key_algorithm();

=head1 DESCRIPTION

This class provides accessors for the members of the hashes that
L<Cpanel::SSL::Utils>’s C<parse_key_text()> returns.

It subclasses L<Cpanel::SSL::Parsed::Base>. As of now it provides
no accessors that that base class does not.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::SSL::Parsed::Base';

1;
