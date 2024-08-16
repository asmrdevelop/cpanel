package Cpanel::TempFH;

# cpanel - Cpanel/TempFH.pm                         Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TempFH - temporary filehandle, however we may

=head1 SYNOPSIS

    $fh = Cpanel::TempFH::create();

=cut

#----------------------------------------------------------------------

use Cpanel::Memfd ();
use Cpanel::Try   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $fh = Cpanel::TempFH::create()

Returns a filehandle that may be written to and read from.

The filehandle is a memfd if the kernel is capable; otherwise
it’s an anonymous filesystem node.

=cut

sub create {
    local ( $@, $! );

    my $fh;

    Cpanel::Try::try(
        sub {
            $fh = Cpanel::Memfd::create();
        },
        'Cpanel::Exception::SystemCall::Unsupported' => sub {
            require File::Temp;

            # Scalar context makes the file be deleted on close.
            # (File::Temp unlink()s prior to returning the filehandle.)
            $fh = File::Temp::tempfile();
        },
    );

    return $fh;
}

1;
