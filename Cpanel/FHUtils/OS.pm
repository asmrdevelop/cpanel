package Cpanel::FHUtils::OS;

# cpanel - Cpanel/FHUtils/OS.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FHUtils::OS - check a filehandle’s OS-ness

=head1 SYNOPSIS

    my $is_os_fh = is_os_filehandle($fh);

=head1 FUNCTIONS

=head2 $yn = is_os_filehandle( FILEHANDLE )

Returns a boolean that indicates whether the given FILEHANDLE
has an underlying OS file descriptor or is a Perl abstraction
(e.g., C<open()> to a string reference, L<IO::Callback>, etc.).

=cut

my $fileno;

sub is_os_filehandle {
    local $@;
    $fileno = eval { fileno $_[0] };
    return ( defined $fileno ) && ( $fileno != -1 );
}

1;
