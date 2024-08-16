package Cpanel::FHUtils::FDFlags;

# cpanel - Cpanel/FHUtils/FDFlags.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Fcntl::Constants ();
use Cpanel::Autodie          ();

=encoding utf-8

=head1 NAME

Cpanel::FHUtils::FDFlags - Set FD flags on underly FDs attached to a perl file handle.

=head1 SYNOPSIS

    use Cpanel::FHUtils::FDFlags;

    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($fh);

    Cpanel::FHUtils::FDFlags::set_CLOEXEC($fh);

=head1 DESCRIPTION

See the system fcntl(2) man page for additional details.

=head2 set_non_CLOEXEC($fh)

Removes the FD_CLOEXEC flag from a perl file handle

Throws an exception on failure.

=cut

sub set_non_CLOEXEC {

    # $fh = $_[0]
    _unset_fd_flag( $_[0], $Cpanel::Fcntl::Constants::FD_CLOEXEC );
    return 1;
}

=head2 set_non_CLOEXEC($fh)

Adds the FD_CLOEXEC flag from a perl file handle

Throws an exception on failure.

=cut

sub set_CLOEXEC {

    # $fh = $_[0]
    _set_fd_flag( $_[0], $Cpanel::Fcntl::Constants::FD_CLOEXEC );
    return 1;
}

#----------------------------------------------------------------------

sub _set_fd_flag {

    # $fh = $_[0]
    # $flags = $_[1]

    return Cpanel::Autodie::fcntl(
        $_[0],
        $Cpanel::Fcntl::Constants::F_SETFD,
        _get_fd_flags( $_[0] ) | $_[1],
    );
}

sub _unset_fd_flag {

    # $fh = $_[0]
    # $flags = $_[1]

    return Cpanel::Autodie::fcntl(
        $_[0],
        $Cpanel::Fcntl::Constants::F_SETFD,
        _get_fd_flags( $_[0] ) & ~$_[1],
    );
}

sub _get_fd_flags {

    # $fh = $_[0]
    # force numeric context
    return int Cpanel::Autodie::fcntl( $_[0], $Cpanel::Fcntl::Constants::F_GETFD, 0 );
}

1;
