package Whostmgr::API::1::Utils::Persona;

# cpanel - Whostmgr/API/1/Utils/Persona.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Persona

=head1 SYNOPSIS

    my $err_obj = Whostmgr::API::1::Utils::Persona::precheck_parent(
        $module, $funcname,
        $args, $metadata, $api_info_hr,
    );

    return $err_obj if $err_obj;

=head1 DESCRIPTION

This module contains logic for the interaction between WHM API v1
and C<persona> API metaarguments (i.e., C<api.persona>).

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::APICommon::Persona ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $struct_or_undef = precheck_parent( $MODULE, $FUNCNAME, \%ARGS, $METADATA_OBJ, \%API_INFO )

Performs a precheck on the arguments to the function to ensure that the
caller isn’t trying to alter a child account when that alteration needs
to happen on the parent account instead.

$MODULE is the full Perl namespace (e.g., C<Whostmgr::API::1::CoolStuff>),
$FUNCNAME is the API call’s name, and %ARGS, $METADATA_OBJ, and %API_INFO
are what are normally given to a WHM API v1 call.

If the precheck indicates that the API call should not be made, a
data structure is returned that should go in the response payload.
$METADATA_OBJ will also be updated appropriately.

If the precheck authorizes the API call, then undef is returned.

=cut

sub precheck_parent ( $module, $funcname, $args, $metadata, $api_info_hr ) {    ## no critic qw(ManyArgs) - mis-parse

    my $persona = $api_info_hr->{'persona'};

    # This shouldn’t strictly be necessary as a security controls since
    # the ACLs system should enforce proper authorization, but it’s at
    # least a convenience.
    if ( $persona && $persona eq Cpanel::APICommon::Persona::PARENT ) {
        local ( $@, $! );
        require Whostmgr::ACLS;

        if ( !Whostmgr::ACLS::hasroot() ) {

            # No error object for now …
            $metadata->set_not_ok( locale()->maketext( 'Only a system administrator may identify as “[_1]”.', $persona ) );

            require Cpanel::APICommon::Error;
            return Cpanel::APICommon::Error::convert_to_payload('PersonaForbidden');
        }
    }

    my $arg_parent_cr = $module && $module->can('ARGUMENT_NEEDS_PARENT');

    if ($arg_parent_cr) {
        if ( my $argname_raw = $arg_parent_cr->()->{$funcname} ) {

            my @argnames = ref($argname_raw) ? @$argname_raw : ($argname_raw);

            for my $argname (@argnames) {
                my ( $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $persona, $args->{$argname} );

                if ($str) {
                    $metadata->set_not_ok($str);
                    return $err_obj;
                }
            }
        }
    }

    return undef;
}

sub get_send_to_parent_string ($username) {
    return locale()->maketext( 'Do not send API requests for “[_1][comment,username]” to this node. Send this request to the account’s parent node.', $username );
}

1;
