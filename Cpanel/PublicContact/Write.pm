package Cpanel::PublicContact::Write;

# cpanel - Cpanel/PublicContact/Write.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PublicContact::Write - writer for the PublicContact datastore

=head1 SYNOPSIS

    my $contact_hr = Cpanel::PublicContact::Write->set(
        'reseller_name',
        name => 'Bob’s Hosting',
        url => 'http://bobshosting.net',
    );

    Cpanel::PublicContact::Write->unset('reseller_name');

=head1 DESCRIPTION

See L<Cpanel::PublicContact> for a description of this datastore.

=cut

use Cpanel::Autodie   ();
use Cpanel::Exception ();

use parent qw( Cpanel::PublicContact );

#Files are world-readable because contact_details.cgi runs unprivileged.
use constant {
    _dir_mode  => 0711,
    _node_mode => 0644,

    MAX_LENGTH => 1024,
};

=head1 METHODS

=head2 I<CLASS>->set( RESELLER_USERNAME, %OPTS )

Sets values in the datastore. %OPTS currently can be:

=over

=item * C<name> - An arbitrary name.

=item * C<url> - A contact URL. For now, no validation is done;
this is just free text. However, we will tack 'http://' on to the
start of the supplied string if the string does not start with
either http:// or https:// or mailto:

=back

Note that undef values are ignored—i.e., the value is left unchanged.
To set a value to empty, send in the empty string.

=cut

sub set {
    my ( $class, $username, %parts ) = @_;

    die 'Need username!' if !$username;

    if ( !grep { defined $parts{$_} } $class->PARTS ) {
        die( 'Need at least one of: ' . join( ', ', $class->PARTS ) . " when setting public contact\n" );
    }

    if ( length $parts{'url'} && $parts{'url'} !~ m{^http[s]?://|^mailto:} ) {
        $parts{'url'} = 'http://' . $parts{'url'};
    }

    require Cpanel::Set;
    my @extra = Cpanel::Set::difference(
        [ keys %parts ],
        [ $class->PARTS() ],
    );
    if (@extra) {
        die "Unrecognized argument(s): @extra";
    }

    $class->_init();

    # Check before the transaction is created so we don't end up with an empty file
    for my $part ( $class->PARTS ) {
        if ( defined $parts{$part} && length( $parts{$part} ) > MAX_LENGTH ) {
            die Cpanel::Exception::create( 'TooManyBytes', [ key => $part, value => $parts{$part}, maxlength => MAX_LENGTH ] );
        }
    }

    require Cpanel::Transaction::File::JSON;
    my $xaction = Cpanel::Transaction::File::JSON->new(
        path        => $class->_get_user_path($username),
        permissions => $class->_node_mode(),
    );

    my $data = $xaction->get_data();
    if ( 'SCALAR' eq ref $data ) {
        $data = {};
    }

    for my $part ( $class->PARTS ) {
        if ( defined $parts{$part} ) {
            $data->{$part} = $parts{$part};
        }

        $data->{$part} //= q<>;
    }

    $xaction->set_data($data);    #No-op if the datastore already existed.

    $xaction->save_and_close_or_die();

    return;
}

=head2 I<CLASS>->unset( RESELLER_USERNAME )

Removes an entry from the datastore. Returns 1 if an entry was deleted
or 0 if no entry was deleted.

=cut

sub unset {
    my ( $class, $username ) = @_;

    return 0 if $class->_init();

    return Cpanel::Autodie::unlink_if_exists( $class->_get_user_path($username) );
}

=head2 I<CLASS>->rename( OLD_RESELLER_USERNAME, NEW_RESELLER_USERNAME )

Renames an entry (for when, e.g., a reseller is renamed). Returns 1
if an entry was renamed, or 0 if no entry named OLD_RESELLER_USERNAME
was there.

=cut

sub rename {
    my ( $class, $old_username, $new_username ) = @_;

    return 0 if $class->_init();

    return Cpanel::Autodie::rename_if_exists( $class->_get_user_path($old_username), $class->_get_user_path($new_username) );
}

#----------------------------------------------------------------------

#returns 1 if the directory is created
sub _init {
    my ($class) = @_;

    if ( Cpanel::Autodie::exists( $class->_BASEDIR() ) ) {
        if ( ( ( stat _ )[2] & 0777 ) != $class->_dir_mode() ) {
            require Cpanel::Autodie;
            Cpanel::Autodie::chmod( $class->_dir_mode(), $class->_BASEDIR() );
        }
    }
    else {
        require Cpanel::Autodie;
        Cpanel::Autodie::mkdir( $class->_BASEDIR(), $class->_dir_mode() );
        return 1;
    }

    return 0;
}

1;
