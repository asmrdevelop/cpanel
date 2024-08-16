package Cpanel::WebCalls::Type;

# cpanel - Cpanel/WebCalls/Type.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Type

=head1 SYNOPSIS

    my $why_bad = Cpanel::WebCalls::Type::MySubclass->why_entry_data_invalid(
        'bob',
        \%entry_data,
    );

    my $why_bad = Cpanel::WebCalls::Type::MySubclass->why_run_arguments_invalid(
        @arguments,
    );

    my $why_bad = Cpanel::WebCalls::Type::MySubclass->why_update_data_invalid(
        @arguments,
    );

    my $out = Cpanel::WebCalls::Type::MySubclass->run(
        $id, $entry_obj, @arguments,
    );

=head1 DESCRIPTION

This is a base class for modules that define a cPanel WebCall type.

=head1 HOW TO CREATE A NEW TYPE MODULE

All type modules live in the C<Cpanel::WebCalls::Type::> namespace.

Each type module B<MUST> implement:

=over

=item * C<_WHY_ENTRY_DATA_INVALID( $username, $data )>

This is the backend to C<why_entry_data_invalid()> below.

=item * C<_WHY_ARE_RUN_ARGUMENTS_INVALID( @arguments )>

This is the backend to C<why_are_run_arguments_invalid()> below.

=item * C<_RUN( $ID, $ENTRY_OBJ, @ARGUMENTS )>

This is the backend to C<run()> below.

It B<MUST> return two arguments:

=over

=item * Either the C<_UPDATE()> or C<_RUN()> constant of this
class. The former indicates that an update happened; the latter
indicates otherwise. This tells the base class whether to mark the
webcall as having been I<updated>, or merely run.

=item * The actual text output of the webcall. This will be given
to the caller.

=back

=back

Each type module B<MAY> implement:

=over

=item * C<_ON_POST_DELETE($class, $entry_obj)> - Implements
C<on_post_delete()> (described below).

=back

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->why_entry_data_invalid( $USERNAME, $DATA_REF )

Returns a string that indicates why $DATA_REF is invalid
for an entry for $USERNAME.

If there’s no invalidity, undef is returned.

=cut

sub why_entry_data_invalid ( $class, $username, $data_ref ) {
    return $class->_WHY_ENTRY_DATA_INVALID( $username, $data_ref );
}

sub _WHY_ENTRY_DATA_INVALID {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 $obj = I<CLASS>->why_update_data_invalid( $USERNAME, $DATA_REF )

Returns a string that indicates why $DATA_REF is invalid
for an update to an existing entry for $USERNAME.

If there’s no invalidity, undef is returned.

=cut

sub why_update_data_invalid ( $class, $username, $data_ref ) {
    return $class->_WHY_UPDATE_DATA_INVALID( $username, $data_ref );
}

sub _WHY_UPDATE_DATA_INVALID {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 $obj = I<CLASS>->normalize_entry_data( $USERNAME, $DATA_REF )

Updates $DATA_REF if in order to normalize any data as necessary.

Returns a string that indicates why $DATA_REF is invalid to
normalize for an entry for $USERNAME.

If it is normalized successfully, undef is returned.

=cut

sub normalize_entry_data ( $class, $username, $data_ref ) {
    return $class->_NORMALIZE_ENTRY_DATA( $username, $data_ref );
}

sub _NORMALIZE_ENTRY_DATA {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->why_run_arguments_invalid( @ARGUMENTS )

Returns a string that indicates to the caller why @ARGUMENTS are
invalid for running the webcall. (If @ARGUMENTS are valid, then
this returns undef.)

=cut

sub why_run_arguments_invalid ( $class, @args ) {

    # Validations that apply to any webcall call:
    for my $specimen (@args) {
        if ( !length $specimen ) {
            return 'Empty arguments are prohibited.';
        }

        if ( $specimen =~ tr<\0-\x1f\x7f><> ) {
            return 'Control characters are prohibited.';
        }

        if ( $specimen =~ tr<\x80-\xff><> ) {
            return 'Wide characters are prohibited.';
        }
    }

    return $class->_WHY_RUN_ARGUMENTS_INVALID(@args);
}

sub _WHY_RUN_ARGUMENTS_INVALID {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->run( $ID, $ENTRY_OBJ, @ARGUMENTS )

Runs the webcall. This wraps the subclass’s C<_run()> method.

By this point @ARGUMENTS are validated.

=cut

use constant {
    _UPDATED => '_updated',
    _RAN     => '_ran',
};

sub run ( $class, $id, $entry_obj, @args ) {

    # To prevent race conditions we have to lock the datastore prior to
    # reading. But to optimize for performance we minimize the amount of
    # time we spend under an exclusive lock by first acquiring a shared
    # lock, then upgrading it to an exclusive lock.
    my $lock = $class->_get_shared_lock();

    my ( $rettype, $out ) = $class->_RUN( $id, $entry_obj, @args );

    local $@;
    warn if !eval {
        my $writer = $class->_get_writer($lock);

        my $fn;

        if ( $rettype eq _UPDATED ) {
            $fn = 'save_update_time';
        }
        elsif ( $rettype eq _RAN ) {
            $fn = 'save_run_time';
        }
        else {
            die "bad rettype: $rettype";
        }

        $writer->$fn($id);

        1;
    };

    return $out;
}

=head2 I<CLASS>->is_data_equal( $DATA1, $DATA2 )

Compares two data values for equality.

Since the data for a specific type is implementation-specific it’s
up to the concrete type to determine what equality means for itself.

Returns truthy if the values are equal, falsy otherwise.

=cut

sub is_data_equal ( $class, $data1, $data2 ) {
    return $class->_IS_DATA_EQUAL( $data1, $data2 );
}

sub _IS_DATA_EQUAL {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

=head2 I<CLASS>->create_data_copy( $ORIGINAL_DATA )

Takes a data value and returns a copy of that data.

By default this method performs a simple JSON clone of the data.

Concrete types can override the underlying implmentation if a more
complex implementation is required.

=cut

sub create_data_copy ( $class, $original_data ) {
    return $class->_CREATE_DATA_COPY($original_data);
}

sub _CREATE_DATA_COPY ( $class, $original_data ) {
    require Cpanel::JSON;
    return Cpanel::JSON::Load( Cpanel::JSON::Dump($original_data) );
}

=head2 I<CLASS>->merge_data( $STARTING_DATA, $NEW_DATA )

Takes two data values and merges them applying any updated values from the
second data value to the first.

Since the data for a specific type is implementation-specific it’s
up to the concrete type to determine what equality means for itself.

=cut

sub merge_data ( $class, $starting_data, $new_data ) {
    return $class->_MERGE_DATA( $starting_data, $new_data );
}

sub _MERGE_DATA {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

#----------------------------------------------------------------------

=head2 I<CLASS>->create_updater( @ARGS )

Returns an instance of I<CLASS>’s C<::Updater> class, if such exists.
Otherwise, returns undef.

=cut

sub create_updater ( $class, @args ) {
    require Cpanel::LoadModule::IfExists;

    my $updater_pkg = "${class}::Updater";

    my $ns = Cpanel::LoadModule::IfExists::load_if_exists($updater_pkg);

    return $ns && $ns->new(@args);
}

#----------------------------------------------------------------------

=head2 I<CLASS>->on_post_delete( $ENTRY_OBJ )

To be called immediately after an entry is deleted from the datastore.
Exceptions are trapped and turned into warnings.

Nothing is returned.

=cut

sub on_post_delete ( $class, $entry_obj ) {
    local $@;
    warn if !eval { $class->_ON_POST_DELETE($entry_obj); 1 };

    return;
}

use constant _ON_POST_DELETE => ();

#----------------------------------------------------------------------

# Returns a L<Cpanel::FileUtils::Flock> instance that contains a
# shared lock of the webcalls datastore.
#
sub _get_shared_lock ($) {
    require Cpanel::WebCalls::Datastore::Read;

    return _wait_p(
        Cpanel::WebCalls::Datastore::Read->lock_p(
            timeout => 30,
        ),
    );
}

# Returns a L<Cpanel::WebCalls::Datastore::Write> instance.
# $LOCK is a L<Cpanel::FileUtils::Flock> instance, probably
# what C<_Get_shared_lock()> returns.
#
sub _get_writer ( $, $fh ) {
    require Cpanel::WebCalls::Datastore::Write;

    return _wait_p(
        Cpanel::WebCalls::Datastore::Write->new_p(
            timeout => 30,
            fh      => $fh,
        ),
    );
}

#----------------------------------------------------------------------

sub _run_preprocess { return }

sub _wait_p ($p) {
    require Cpanel::PromiseUtils;
    return Cpanel::PromiseUtils::wait_anyevent($p)->get();
}

1;
