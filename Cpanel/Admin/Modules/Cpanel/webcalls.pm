package Cpanel::Admin::Modules::Cpanel::webcalls;

# cpanel - Cpanel/Admin/Modules/Cpanel/webcalls.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::webcalls

=head1 DESCRIPTION

This module contains privilege-escalation logic for user code that needs
to access the webcalls datastore.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Admin::Base';

use Cpanel::Exception ();

sub _actions {
    return (
        'CREATE',
        'DELETE',
        'GET_ENTRIES',
        'RECREATE',
        'UPDATE_DATA',
    );
}

# This has to be open because Pkgacct calls it,
# and we distribute an uncompiled scripts/pkgacct.
use constant _allowed_parents => '*';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 CREATE($TYPE, $DATA)

A wrapper around L<Cpanel::WebCalls::Datastore::Write>’s C<create_for_user()>.

=cut

sub CREATE ( $self, $type, $data ) {

    my $username = $self->get_caller_username();

    my $why_invalid;
    my $ns = _validate_type($type) or do {
        $why_invalid = "Bad type: $type";
    };

    #
    # Normalize the data before validating it.
    # This gives us an opportunity to ensure
    # domains do not have things such as uppercase
    # letters in them before validating the domain
    #
    $ns->normalize_entry_data( $username, $data ) unless $why_invalid;

    #
    # why_entry_data_invalid is a security control.
    # Users must only be allowed to create entries for
    # domains/objects that they control.
    #
    $why_invalid ||= $ns->why_entry_data_invalid( $username, $data );

    if ($why_invalid) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                class   => 'Cpanel::Exception::InvalidParameter',
                message => $why_invalid,
            ],
        );
    }

    my $writer = _get_writer();

    my @r = $writer->create_for_user( $username, $type, $data );

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['SSLTasks'], "autossl_check $username" );

    return @r;
}

sub _validate_type ($type) {
    my $type_is_valid = length $type;
    $type_is_valid &&= ( $type !~ tr<a-zA-Z0-9_><>c );

    $type_is_valid &&= do {
        require Cpanel::LoadModule;
        require Cpanel::Try;

        Cpanel::Try::try(
            sub {
                Cpanel::LoadModule::load_perl_module("Cpanel::WebCalls::Type::$type");
            },
            'Cpanel::Exception::ModuleLoadError' => sub ($err) {
                return undef if $err->is_not_found();

                die $err;
            },
        );
    };

    return $type_is_valid;
}

#----------------------------------------------------------------------

=head2 DELETE($ID)

A wrapper around L<Cpanel::WebCalls::Datastore::Write>’s C<delete_for_user()>.

=cut

sub DELETE ( $self, $id ) {

    require Cpanel::WebCalls::ID;
    if ( !Cpanel::WebCalls::ID::is_valid($id) ) {
        $self->whitelist_exceptions(
            ['Cpanel::Exception::InvalidParameter'],
            sub {
                die Cpanel::Exception::create_raw(
                    'InvalidParameter',
                    "bad ID: $id",
                );

            },
        );
    }

    my $writer = _get_writer();

    my $username = $self->get_caller_username();

    require Cpanel::WebCalls::Datastore::Read;
    if ( Cpanel::WebCalls::Datastore::Read->user_owns_id( $username, $id ) ) {
        $writer->delete_for_user( $username, $id );
        return 1;
    }

    return 0;
}

sub _verify_user_ownership_of_id ( $self, $id ) {
    my $username = $self->get_caller_username();

    require Cpanel::WebCalls::ID;
    my $owns = Cpanel::WebCalls::ID::is_valid($id);

    $owns &&= do {
        require Cpanel::WebCalls::Datastore::Read;
        Cpanel::WebCalls::Datastore::Read->user_owns_id( $username, $id );
    };

    if ( !$owns ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Unknown ID: $id" );
    }

    return;
}

#----------------------------------------------------------------------

=head2 GET_ENTRIES()

A wrapper around L<Cpanel::WebCalls::Datastore::Read>’s C<read_for_user()>.

=cut

sub GET_ENTRIES ($self) {
    require Cpanel::WebCalls::Datastore::Read;
    return Cpanel::WebCalls::Datastore::Read->read_for_user( $self->get_caller_username() );
}

#----------------------------------------------------------------------

=head2 RECREATE( $ID )

Recreate the entry that $ID refers to. Useful if an old ID gets
compromised.

=cut

sub RECREATE ( $self, $id ) {
    my $username = $self->get_caller_username();

    require Cpanel::WebCalls::Datastore::Read;

    my $writer = _get_writer();

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            $self->_verify_user_ownership_of_id($id);
        },
    );

    return $writer->recreate_for_user( $username, $id );
}

=head2 UPDATE_DATA( $TYPE, $ID, $ORIGINAL_DATA, $NEW_DATA )

Updates the entry that $ID refers to such that it will contain
$NEW_DATA. As a protection against race conditions, $ORIGINAL_DATA
must match the entry prior to the update; if that’s not the case,
an exception is thrown.

=cut

sub UPDATE_DATA ( $self, $id, $original_data, $new_data ) {    ## no critic qw(Subroutines::ProhibitManyArgs) adding prohibit due to bug with signatures

    $self->whitelist_exceptions(
        ['Cpanel::Exception::InvalidParameter'],
        sub {
            $self->_verify_user_ownership_of_id($id);
        },
    );

    my $entry = Cpanel::WebCalls::Datastore::Read->read_if_exists($id);
    my $type  = $entry->{type};

    my $why_invalid;
    my $ns = _validate_type($type) or do {
        $why_invalid = "Bad type: $type";
    };

    my $username = $self->get_caller_username();

    $why_invalid ||= $ns->why_update_data_invalid( $username, $new_data );

    if ($why_invalid) {
        die Cpanel::Exception::create(
            'AdminError',
            [
                class   => 'Cpanel::Exception::InvalidParameter',
                message => $why_invalid,
            ],
        );
    }

    my $writer = _get_writer();

    return $writer->update_data( $username, $id, $original_data, $new_data );
}

#----------------------------------------------------------------------

sub _get_writer () {
    require Cpanel::WebCalls::Datastore::Write;
    require Cpanel::PromiseUtils;

    my $writer_p = Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30 );
    return Cpanel::PromiseUtils::wait_anyevent($writer_p)->get();
}

1;
