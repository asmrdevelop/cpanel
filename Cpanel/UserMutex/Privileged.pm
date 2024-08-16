package Cpanel::UserMutex::Privileged;

# cpanel - Cpanel/UserMutex/Privileged.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UserMutex::Privileged

=head1 SYNOPSIS

    package MyUserMutex;

    use parent 'Cpanel::UserMutex::Privileged';

    package main;

    my $mutex = MyUserMutex->new('bob');

=head1 DESCRIPTION

This class implements a similar interface to L<Cpanel::UserMutex>
with the following differences:

=over

=item * It B<MUST> be run as administrator.

=item * It can query lock state without attempting to I<acquire> the lock.

=back

This can potentially replace L<Cpanel::SafeFile> as the backend for many
(most?) other root-level user mutexes.

=cut

#----------------------------------------------------------------------
# IMPLEMENTATION NOTES:
#
# This assumes that /var/cpanel will NOT be NFS-mounted.
#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Cpanel::Autodie             ();
use Cpanel::FileUtils::Flock    ();
use Cpanel::UserDatastore::Init ();

use constant _EAGAIN => 11;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new_if_not_exists( $USERNAME )

Attempts to acquire a lock for $USERNAME.
If the acquisition succeeds this returns an instance of I<CLASS>;
otherwise undef is returned.

=cut

sub new_if_not_exists ( $class, $username ) {
    die "Must subclass $class!" if $class eq __PACKAGE__;

    die "Bad username: $username" if -1 != index( $username, '/' );

    my $dir = Cpanel::UserDatastore::Init::initialize($username);

    my $fs_name = ( $class =~ tr<:><_>r );

    my $path = "$dir/$fs_name";

    # NB: This file is never deleted directly.
    Cpanel::Autodie::sysopen(
        my $fh, $path,
        $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_WRONLY,
    );

    Cpanel::FileUtils::Flock::flock( $fh, 'EX', 'NB' ) or do {
        return undef;
    };

    return bless [$fh], $class;
}

1;
