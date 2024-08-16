package Cpanel::Memfd;

# cpanel - Cpanel/Memfd.pm                          Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Memfd - memfd in cPanel

=head1 SYNOPSIS

    my $fh = Cpanel::Memfd::create();

=head1 DESCRIPTION

B<STOP!> As long as CentOS 6 is supported, you probably want
L<Cpanel::TempFH> instead of this module..

This creates a Perl filehandle to a nameless
L<memfd|http://man7.org/linux/man-pages/man2/memfd_create.2.html> instance.

=head1 OS SUPPORT

Support for this Linux feature is new in CentOS 7. In prior versions
L<File::Temp> facilitates a similar effect via the filesystem:

    require File::Temp;
    $fh = File::Temp::tempfile();

L<Cpanel::TempFH> abstracts over the difference.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

use constant {
    NR_memfd_create => 319,

    _ENOSYS => 38,
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $fh = create()

Creates a memfd instance and returns an open filehandle to it.

=cut

sub create {
    my $name = q<>;

    local $!;

    my $fd = syscall( NR_memfd_create(), $name, 0 );

    if ( $fd < 0 ) {
        if ( $! == _ENOSYS() ) {
            die Cpanel::Exception::create( 'SystemCall::Unsupported', [ name => 'memfd_create' ] );
        }

        die Cpanel::Exception::create( 'SystemCall', [ name => 'memfd_create', error => $! ] );
    }

    open my $fh, '+<&=', $fd or die "dup2(memfd): $!";

    return bless $fh, __PACKAGE__;
}

1;
