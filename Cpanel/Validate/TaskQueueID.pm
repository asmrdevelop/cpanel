package Cpanel::Validate::TaskQueueID;

# cpanel - Cpanel/Validate/TaskQueueID.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::Validate::TaskQueueID

=head1 SYNOPSIS

    Cpanel::Validate::TaskQueueID::valid( "TQ:TaskQueue:16547" )

    or Cpanel::Validate::TaskQueueID::validate_or_die( "TQ:TaskQueue:16547" )

=head1 DESCRIPTION

This module implements TaskQueueID validation.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 is_valid( $str )

Returns a boolean that indicates validity.

=cut

sub is_valid ($id) {
    return unless defined $id;

    return $id =~ qr{^TQ:TaskQueue:\d+$}a;
}

=head2 validate_or_die( $str )

Throw an exception if the provided $STR is not a valid TaskQueueID.

=cut

sub validate_or_die ($id) {

    return 1 if is_valid($id);

    die Cpanel::Exception::create_raw( 'MissingParameter', 'Empty TaskQueueID' ) unless length $id;
    die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,TaskQueueID].', [$id] );

    return;
}

1;
