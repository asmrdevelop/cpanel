package Whostmgr::API::1::Utils::Metadata;

# cpanel - Whostmgr/API/1/Utils/Metadata.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Metadata - convenience methods on metadata hashrefs

=head1 SYNOPSIS

    sub my_whm_api1_func ($args, $metadata, @) {
        # …

        $metadata->set_ok();

        return $whatever;
    }

=head1 DESCRIPTION

This class gives API authors a more convenient syntax for indicating that
an API call is successful than having to call L<Whostmgr::API::1::Utils>
directly. (And it preserves that module’s consistency in reporting.)

=cut

#----------------------------------------------------------------------

use Whostmgr::API::1::Utils ();

#----------------------------------------------------------------------

=head1 METHODS

This class omits a constructor B<BY DESIGN>. To use this class,
C<bless()> a hash reference. Then you can use the following methods:

=head2 $obj = I<OBJ>->set_ok()

Wraps L<Whostmgr::API::1::Utils>’s C<set_metadata_ok()> function.

=cut

sub set_ok ($self) {
    Whostmgr::API::1::Utils::set_metadata_ok($self);

    return $self;
}

=head2 $obj = I<OBJ>->set_not_ok( $REASON )

Wraps L<Whostmgr::API::1::Utils>’s C<set_metadata_not_ok()> function.

=cut

sub set_not_ok ( $self, $reason ) {
    Whostmgr::API::1::Utils::set_metadata_not_ok( $self, $reason );

    return $self;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->add_warning( $TEXT )

Adds a warning to the API output.

=cut

sub add_warning ( $self, $text ) {
    return $self->_add_output( 'warnings', $text );
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->add_message( $TEXT )

Adds an informational message to the API output.

=cut

sub add_message ( $self, $text ) {
    return $self->_add_output( 'messages', $text );
}

#----------------------------------------------------------------------

=head2 $hr = I<OBJ>->TO_JSON()

cf. L<JSON>

=cut

sub TO_JSON ($self) {
    return {%$self};
}

#----------------------------------------------------------------------

sub _add_output ( $self, $type, $text ) {
    push @{ $self->{'output'}{$type} }, $text;

    return $self;
}

1;
