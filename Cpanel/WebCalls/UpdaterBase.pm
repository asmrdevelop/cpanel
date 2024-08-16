package Cpanel::WebCalls::UpdaterBase;

# cpanel - Cpanel/WebCalls/UpdaterBase.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::UpdaterBase

=head1 SYNOPSIS

    my $updater = Cpanel::WebCalls::Type::SomeType::Updater->new();

    $updater->remove( \@old_entries );

    $updater->add( \@new_entries );

    $updater->update( $old_entry => $new_entry );

    $updater->finish();

=head1 DESCRIPTION

This base class allows ancillary actions to take place whenever an entry
is added, removed, or modified from the webcalls datastore.

=head1 REQUIRED SUBCLASS METHODS:

=over

=item * C<_INIT( @ARGS )>: Runs during C<new()>, receives arguments given
to that method.

=item * C<_REMOVE( \@ENTRIES )>: Implements C<remove()> below.

=item * C<_ADD( \@ENTRIES )>: Implements C<add()> below.

=item * C<_UPDATE( $OLD_ENTRY, $NEW_ENTRY )>: Implements C<update()> below.

=item * C<_FINISH( @ARGS )>: Implements C<finish()> below.

=back

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( @ARGS )

Instantiates I<CLASS> then calls C<_INIT(@ARGS)>.

=cut

sub new ( $class, @args ) {
    my $self = bless {}, $class;
    $self->_INIT(@args);

    return $self;
}

=head2 I<OBJ>->remove( \@IDS_AND_ENTRIES )

Runs when 1 or more entries are removed. @IDS_AND_ENTRIES are
pairs of (ID, L<Cpanel::WebCalls::Entry> instance).

=cut

sub remove ( $self, $entries_ar ) {
    $self->_REMOVE($entries_ar);

    return;
}

=head2 I<OBJ>->add( \@ENTRIES )

Runs when 1 or more entries are added. @IDS_AND_ENTRIES are
pairs of (ID, L<Cpanel::WebCalls::Entry> instance).

=cut

sub add ( $self, $entries_ar ) {
    $self->_ADD($entries_ar);

    return;
}

=head2 I<OBJ>->update( $OLD_ID, $OLD_ENTRY, $NEW_ID, $NEW_ENTRY )

Runs when an entry is updated. Receives two
distinct L<Cpanel::WebCalls::Entry> instances.

=cut

sub update ( $self, $old_id, $old_entry, $new_id, $new_entry ) {    ## no critic qw(ManyArgs) - mis-parse
    $self->_UPDATE( $old_id, $old_entry, $new_id, $new_entry );

    return;
}

=head2 I<OBJ>->finish( @ARGS )

Runs when the operation is finished.

=cut

sub finish ( $self, @args ) {
    $self->_FINISH(@args);

    return;
}

1;
