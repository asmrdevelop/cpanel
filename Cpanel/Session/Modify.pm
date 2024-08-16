package Cpanel::Session::Modify;

# cpanel - Cpanel/Session/Modify.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::SafeFile           ();
use Cpanel::Session            ();
use Cpanel::Session::Load      ();

=head1 NAME

Cpanel::Session::Modify

=head1 DESCRIPTION

Modify an existing Cpanel::Session while holding a lock.

=cut

=head1 SYNOPSIS

    use Cpanel::Session::Modify ();

    my $session_mod = Cpanel::Session::Modify->new($session);

    if ( !$session_mod->get('session_needs_temp_user') ) {
        $session_mod->abort();
        return 0;
    }

    ...

    my $session_temp_pass = $session_mod->get('session_temp_pass');

    ...

    $session_mod->set( 'created_session_temp_user', '1' );
    $session_mod->delete('session_needs_temp_user');
    $session_mod->save();


=cut

=head1 DESCRIPTION

=head2 new

=head3 Purpose

Create a Cpanel::Session::Modify object that can be used to modify
an existing Cpanel::Session

=head3 Arguments

=over

=item $session: string - The session to modify

=item $check_expiration - bool - Whether to verify the session timestamps before loading

=back

=head3 Returns

=over

=item A Cpanel::Session::Modify object

=back

If an error occurs, the function will throw an exception.

=cut

sub new {
    my ( $class, $session, $check_expiration ) = @_;

    if ( $check_expiration ? !Cpanel::Session::Load::session_exists_and_is_current($session) : !Cpanel::Session::Load::session_exists($session) ) {
        die "The session “$session” does not exist";
    }

    Cpanel::Session::Load::get_ob_part( \$session );    # strip ob_part

    my $session_file = Cpanel::Session::Load::get_session_file_path($session);

    # Cpanel::Transaction not available here due to memory constraints
    my ( $ref, $fh, $conflock ) = Cpanel::Config::LoadConfig::loadConfig(
        $session_file,
        undef,
        '=',
        undef,
        0,
        0,
        { 'skip_readable_check' => 1, 'nocache' => 1, 'keep_locked_open' => 1, 'rw' => 1 }
    );

    return bless {
        '_session' => $session,
        '_fh'      => $fh,
        '_lock'    => $conflock,
        '_data'    => Cpanel::Session::decode_origin($ref),
    }, $class;
}

=head2 delete

=head3 Purpose

Delete a key from the session

=head3 Arguments

$key: string - The key to delete

=head3 Returns

1

=cut

sub delete {
    my ( $self, $key ) = @_;
    delete $self->{'_data'}{$key};
    return 1;
}

=head2 set

=head3 Purpose

Set a key in the session.  This currently does not
support updating the 'pass' key because it does not
include Cpanel::Session::Encoder. The 'origin' key
with a hashref valyue should be used instead of
the 'origin_as_string' key with a string value.

Values supplied to C<set()> are not munged until
the session is serialized to disk with C<save()>.

=head3 Arguments

=over

=item $key: string - The key to set

=item $value: string - The value to set

=back

=head3 Returns

1

=cut

sub set {
    my ( $self, $key, $value ) = @_;
    if ( $key eq 'pass' || $key eq 'origin_as_string' ) { die "This module does not support updating $key"; }
    if ( $key eq 'origin' ) {

        # clone data to a separate ref
        $value = { %{$value} };
    }
    $self->{'_data'}{$key} = $value;
    return 1;
}

=head2 get

=head3 Purpose

Get a key from the session

=head3 Arguments

$key: string - The key to get

=head3 Returns

1

=cut

sub get {
    my ( $self, $key ) = @_;
    if ( $key eq 'origin' ) {

        # clone data to a separate ref
        return { %{ $self->{'_data'}{$key} } };
    }
    return $self->{'_data'}{$key};
}

=head2 save

=head3 Purpose

Save the session to disk and release the lock

=head3 Arguments

None

=head3 Returns

1

If an error occurs, the function will throw an exception.

=cut

sub save {
    my ($self) = @_;
    Cpanel::Session::filter_sessiondata( $self->{'_data'} );
    Cpanel::Session::encode_origin( $self->{'_data'} );
    local $!;
    Cpanel::Session::write_session( $self->{'_session'}, $self->{'_fh'}, $self->{'_data'} ) or die "Failed to write the session file: $!";
    return $self->_close_session();
}

=head2 abort

=head3 Purpose

Release the lock without saving the session to disk

=head3 Arguments

None

=head3 Returns

1. If an error occurs, the function will throw an exception.

=cut

sub abort {
    my ($self) = @_;
    return $self->_close_session();
}

=head2 get_data

=head3 Purpose

Returns the entires contents of the session data

=head3 Arguments

None

=head3 Returns

The session data hashref

=cut

sub get_data {
    my ($self) = @_;
    return $self->{'_data'};
}

sub _close_session {
    my ($self) = @_;
    local $!;
    Cpanel::SafeFile::safeclose( $self->{'_fh'}, $self->{'_lock'} ) or die "Failed to close the session file: $!";
    delete @{$self}{ '_fh', '_lock', '_data', '_session' };
    return 1;
}

sub DESTROY {
    my ($self) = @_;
    $self->abort() if $self->{'_session'};
    return;
}
1;
