package Cpanel::Pkgacct::Components::Password;

# cpanel - Cpanel/Pkgacct/Components/Password.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Password

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('Password');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s password to the account archive.

=head1 METHODS

=cut

use parent qw( Cpanel::Pkgacct::Component );

use Cpanel::FileUtils::Write ();

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform {
    my ($self) = @_;

    my $username = $self->get_user();
    my $work_dir = $self->get_work_dir();

    my ($pw_hash);

    if ($>) {
        require Cpanel::AdminBin;
        ($pw_hash) = ( split /:/, Cpanel::AdminBin::adminrun( 'security', 'READPASSWD', $username ) )[ 1, 12 ];
    }
    else {
        require Cpanel::PwCache;
        ($pw_hash) = ( Cpanel::PwCache::getpwnam($username) )[ 1, 12 ];
    }

    if ( !$pw_hash || $pw_hash eq 'x' ) {
        die "No password hash!";
    }

    #We used to care about mtimes and such for incremental backups,
    #but this is such a small file that it shouldn’t make a difference.
    Cpanel::FileUtils::Write::overwrite(
        "$work_dir/shadow",
        $pw_hash,
        0600,
    );

    return;
}

1;
