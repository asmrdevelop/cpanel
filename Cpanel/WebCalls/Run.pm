package Cpanel::WebCalls::Run;

# cpanel - Cpanel/WebCalls/Run.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Run

=head1 SYNOPSIS

    my $out = Cpanel::WebCalls::Run::run( $id, $entry, foo => 'bar' );

=head1 DESCRIPTION



=cut

#----------------------------------------------------------------------

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

use constant _RETURN_OK => q[OK];

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $ret = validate_and_run( $ID, $ENTRY_OBJ, @ARGUMENTS )

Validates @ARGUMENTS and (if successful) runs a webcall.

$ID is the webcall’s ID; $ENTRY_OBJ is a L<Cpanel::WebCalls::Entry> instance
that refers to the webcall. @ARGUMENTS are given to the webcall.

If the @ARGUMENTS fail validation, a L<Cpanel::Exception::InvalidParameter>
that explains why is thrown.

The return is the response
from the type module’s C<run()>, or C<OK> if no such response was given.

=cut

sub validate_and_run ( $id, $entry_obj, @args ) {
    my $type = $entry_obj->type();

    my $ns = Cpanel::LoadModule::load_perl_module("Cpanel::WebCalls::Type::$type");

    if ( my $why_bad = $ns->why_run_arguments_invalid(@args) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', $why_bad );
    }

    my $resp = $ns->run( $id, $entry_obj, @args );
    $resp = _RETURN_OK if !length $resp;

    return $resp;
}

1;
