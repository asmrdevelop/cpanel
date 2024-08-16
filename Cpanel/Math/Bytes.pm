package Cpanel::Math::Bytes;

# cpanel - Cpanel/Math/Bytes.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Math::Bytes

=head1 SYNOPSIS

    my $mebibytes = Cpanel::Math::Bytes::to_mib($bytes);

=head1 DESCRIPTION

This module contains logic to convert byte counts into other units.

=cut

#----------------------------------------------------------------------

use Cpanel::Math ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $mib = to_mib($bytes)

Standardized logic to convert a bytes count to mebibytes.

=cut

sub to_mib ($bytes) {
    return Cpanel::Math::floatto( $bytes / 1024 / 1024, 2 );
}

1;
