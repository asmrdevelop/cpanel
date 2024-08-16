package Cpanel::Exception::GPG::IncorrectPassphrase;

# cpanel - Cpanel/Exception/GPG/IncorrectPassphrase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Exception::GPG::IncorrectPassphrase

=head1 SYNOPSIS

    Cpanel::Exception::create('GPG::IncorrectPassphrase', 'The passphrase was incorrect.' );

=head1 DESCRIPTION

This exception indicates that the passphrase provided was incorrect.

=cut

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
