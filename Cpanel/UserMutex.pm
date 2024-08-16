package Cpanel::UserMutex;

# cpanel - Cpanel/UserMutex.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::Mutex

=head1 SYNOPSIS

    package MyUserMutex;

    use parent 'Cpanel::UserMutex';

    package main;

    my $mutex = MyUserMutex->new('bob');

=head1 DESCRIPTION

This class defines an advisory mutex for a given user. The pattern is
meant to be broadly reusable.

This class B<MUST> be subclassed in order to be used.

=head1 LIMITATIONS

This class implements the semantics of L<Cpanel::SafeFile>, which means
it always waits to acquire the lock. There’s no useful means
of attempting just once to get the lock then reporting back that the lock
is already in use. For that, see L<Cpanel::UserMutex::Privileged>.

=cut

#----------------------------------------------------------------------

use Cpanel::PwCache                ();
use Cpanel::Mkdir                  ();
use Cpanel::Transaction::File::Raw ();

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 FILES_PER_OBJECT

The number of file handles that each instance of this class keeps open.

=cut

use constant FILES_PER_OBJECT => 2;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj I<CLASS>->new( [ $USERNAME ] )

Instantiates this class. $USERNAME is optional if run unprivileged
but required otherwise.

=cut

sub new ( $class, $username = undef ) {
    die "Must subclass $class!" if $class eq __PACKAGE__;

    my $relpath = $class->_RELATIVE_PATH();

    my %selfhash = ( _un => $username );
    my $self     = bless \%selfhash, $class;

    my $privs = $self->_get_priv_drop_if_needed();

    my $homedir = Cpanel::PwCache::gethomedir();
    chop($homedir) if substr( $homedir, -1 ) eq '/';

    # safeguard
    if ( !$homedir ) {
        $username ||= Cpanel::PwCache::getusername();
        die "“$username” has no home directory!";
    }

    Cpanel::Mkdir::ensure_directory_existence_and_mode( "$homedir/.cpanel", 0700 );

    # XXX Do NOT create references to this object from outside $self,
    # or else the privilege-dropping logic in DESTROY will fail to
    # prevent unlink() as root.
    $self->{'_x'} = Cpanel::Transaction::File::Raw->new(
        path => "$homedir/$relpath",
    );

    return $self;
}

#----------------------------------------------------------------------

sub DESTROY ($self) {

    # This ensures that when we unlock (i.e., when we delete the .lock file)
    # we are privilege-dropped so that we don’t unlink() as root what we
    # created as a user.
    if ( $self->{'_x'} ) {
        my $privs = $self->_get_priv_drop_if_needed();

        delete $self->{'_x'};
    }

    return;
}

# Called from tests
sub _RELATIVE_PATH ($class) {
    my $mutex_name = $class =~ s<::><_>gr;
    return ".cpanel/$mutex_name";
}

sub _get_priv_drop_if_needed ($self) {
    return $> || do {
        die 'Need username when root!' if !$self->{'_un'};

        require Cpanel::AccessIds::ReducedPrivileges;
        Cpanel::AccessIds::ReducedPrivileges->new( $self->{'_un'} );
    };
}

1;
