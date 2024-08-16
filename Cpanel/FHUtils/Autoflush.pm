package Cpanel::FHUtils::Autoflush;

# cpanel - Cpanel/FHUtils/Autoflush.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::FHUtils::Autoflush

=head1 SYNOPSIS

    Cpanel::FHUtils::Autoflush::enable( $os_filehandle );

=head1 DESCRIPTION

This module contains logic to enable autoflush on a filehandle without
importing L<IO::Handle>.

=head1 FUNCTIONS

=head2 enable( FILEHANDLE )

Same as a call to C<FILEHANDLE-E<gt>autoflush(1)>, just without
the L<IO::Handle> flab.

=cut

use strict;
use warnings;

sub enable {
    select( ( select( $_[0] ), $| = 1 )[0] );    ## no critic qw(InputOutput::ProhibitOneArgSelect Variables::RequireLocalizedPunctuationVars) - aka $socket->autoflush(1) without importing IO::Socket

    return;
}

1;
