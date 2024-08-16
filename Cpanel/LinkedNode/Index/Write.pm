package Cpanel::LinkedNode::Index::Write;

# cpanel - Cpanel/LinkedNode/Index/Write.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Index::Write

=head1 DESCRIPTION

See L<Cpanel::LinkedNode::Index> for more information about this
datastore.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie                 ();
use Cpanel::LinkedNode::Index       ();
use Cpanel::Transaction::File::JSON ();

use constant {
    _FILE_PERMS => 0600,
    _DIR_PERMS  => 0700,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless [ _get_rw_transaction() ], $class;
}

=head2 $hr = I<OBJ>->get_data()

Similar to L<Cpanel::LinkedNode::Index::Read>’s C<get()> function,
except this returns the current in-memory state of the datastore
rather than rereading the data afresh.

Note that what this returns is a transformed copy of the internal
data. Don’t alter the returned hashref and expect that to affect
the in-memory datastore.

=cut

sub get_data ($self) {
    my $raw_hr = $self->[0]->get_data();

    if ( 'HASH' ne ref $raw_hr ) {
        return {};
    }

    my %resp = %$raw_hr;
    Cpanel::LinkedNode::Index::objectify_contents( \%resp );

    return \%resp;
}

use constant _REQUIRED_PROPERTIES => (
    'username',
    'hostname',
    'api_token',
    'worker_capabilities',
);

use constant _OPTIONAL_PROPERTIES => (
    'version',
    'enabled_services',
    'tls_verified',
    'system_settings',
    'remote_node_linkages',
);

=head2 $obj = I<OBJ>->set( $ALIAS, %ATTRS )

Creates or updates the entry for $ALIAS in memory. This does I<not> save
the data to disk; you’ll need to C<save_or_die()> for that to happen.

%ATTRS are:

=over

=item * C<username> (required)

=item * C<hostname> (required)

=item * C<api_token> (required)

=item * C<worker_capabilities> (required)

=item * C<version> (optional)

=item * C<enabled_services> (optional)

=item * C<tls_verified> (optional)

=item * C<system_settings> (optional)

=item * C<remote_node_linkages> (optional)

=back

Returns I<OBJ>.

=cut

sub set ( $self, $alias, %attrs ) {
    my @missing = grep { !exists $attrs{$_} } _REQUIRED_PROPERTIES();
    die( __PACKAGE__ . ": missing: [@missing]" ) if @missing;

    my %properties = (
        %attrs{ _REQUIRED_PROPERTIES(), _OPTIONAL_PROPERTIES() },
        last_check => time(),
    );

    my $data_hr = $self->[0]->get_data();

    if ( 'SCALAR' eq ref $data_hr ) {
        $self->[0]->set_data( { $alias => \%properties } );
    }
    else {
        $data_hr->{$alias} = \%properties;
    }

    return $self;
}

=head2 $what = I<OBJ>->remove( $ALIAS )

Removes $ALIAS from the in-memory datastore if it exists. Does not
save to disk, so call C<save_or_die()> afterward to make changes permanent.

The return is undef if $ALIAS wasn’t in the datastore anyway; otherwise
it’s a L<Cpanel::LinkedNode::Privileged::Configuration> instance.

=cut

sub remove ( $self, $alias ) {
    my $data_hr = $self->[0]->get_data();

    my $removed;

    if ( 'SCALAR' ne ref $data_hr ) {
        $removed = delete $data_hr->{$alias};

        if ($removed) {
            my %dummy = ( $alias => $removed );
            Cpanel::LinkedNode::Index::objectify_contents( \%dummy );
            $removed = $dummy{$alias};
        }
    }

    return $removed;
}

=head2 $obj = I<OBJ>->save_or_die()

Writes I<OBJ>’s contents to disk. This does I<NOT> release the lock
on the datastore, so you can call this method multiple times over
I<OBJ>’s lifetime.

Returns I<OBJ>.

=cut

sub save_or_die ($self) {
    $self->[0]->save_or_die();

    return $self;
}

=head2 $obj = I<OBJ>->close_or_die()

Closes the datastore. This releases the lock
on the datastore, so you can only call this method once during I<OBJ>’s
lifetime.

Returns nothing.

=cut

sub close_or_die ($self) {
    $self->[0]->close_or_die();

    return;
}

sub _get_rw_transaction {
    my $dirpath = Cpanel::LinkedNode::Index::dir();

    Cpanel::Autodie::mkdir_if_not_exists( $dirpath, _DIR_PERMS() ) or do {
        Cpanel::Autodie::chmod( _DIR_PERMS(), $dirpath );
    };

    return Cpanel::Transaction::File::JSON->new(
        path        => Cpanel::LinkedNode::Index::file(),
        permissions => _FILE_PERMS(),
    );
}

1;
