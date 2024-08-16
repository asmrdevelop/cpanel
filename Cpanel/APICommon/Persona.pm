package Cpanel::APICommon::Persona;

# cpanel - Cpanel/APICommon/Persona.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::APICommon::Persona

=head1 DESCRIPTION

This module stores constants and other reusable bits for API persona
logic.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::App ();

use constant {
    PARENT => 'parent',

    _ERROR_TYPE => 'SendToParent',
};

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 PARENT

The persona to send in API requests to indicate that the caller is the
account’s parent node.

=cut

=head1 FUNCTIONS

=head2 ($string, $struct) = get_expect_parent_error_pieces( $PERSONA )

B<THIS> B<IS> B<NOT> B<A> B<SECURITY> B<CONTROL!> Its purpose is to
discourage, rather than prevent, misuse of the API.

If $PERSONA indicates a call from the parent node, this returns empty.

Otherwise, this returns two pieces:

=over

=item * A human-readable string that tells the caller
to send the request to the parent node instead.

=item * An API error payload (cf. L<Cpanel::APICommon::Error>’s
C<convert_to_payload()>) that indicates the same condition.

=back

This function assumes it’s called from within cPanel; see
C<get_whm_expect_parent_error_pieces()> for a WHM equivalent.

=cut

# If an API call calls another API call, that call to the 2nd API call
# is unlikely to pass along the persona argument given to the first
# call. It may not even be the same API version. So let’s assume that,
# once a single API call has passed this persona check, any subsequent
# ones in the same interpreter run should also pass that check.
our $VERIFIED_ONCE;

sub get_expect_parent_error_pieces ($caller_persona) {

    # The handling of $VERIFIED_ONCE here is a bit funny because
    # we want to avoid creating a block.
    return if $VERIFIED_ONCE;

    # Setting this here allows us to do a simple return
    # in the success cases.
    $VERIFIED_ONCE = 1;

    # Unlike cPanel, Webmail *does* need to service API calls
    # for child accounts.
    return if Cpanel::App::is_webmail();

    return _get_expect_parent_error_pieces( $caller_persona, \&_str_cpanel );
}

=head2 ($string, $struct) = get_whm_expect_parent_error_pieces( $PERSONA, $USERNAME )

Like C<get_expect_parent_error_pieces()> but for WHM. It requires
an additional $USERNAME to be submitted and will return empty if the
indicated account is I<not> a child account.

=cut

sub get_whm_expect_parent_error_pieces ( $caller_persona, $username ) {

    # “root” is never distributed.
    return if $username && $username eq 'root';

    return _get_expect_parent_error_pieces( $caller_persona, \&_str_whm, \$username );
}

#----------------------------------------------------------------------

sub _get_expect_parent_error_pieces ( $caller_persona, $strfn, $username_sr = undef ) {
    return if $caller_persona && $caller_persona eq PARENT;

    #------------------------------

    $VERIFIED_ONCE = 0;

    local ( $@, $! );

    if ($username_sr) {

        # If no username was given, then we let the API decide
        # whether that’s legitimate or not.
        return if !length $$username_sr;

        require Cpanel::Config::LoadCpUserFile;
        my $cpuser_obj = eval { Cpanel::Config::LoadCpUserFile::load_or_die($$username_sr) };
        my $exception  = $@;
        if ( !$cpuser_obj ) {
            require Cpanel::Reseller;
            return if Cpanel::Reseller::isreseller($$username_sr);
        }
        die $exception if $exception;

        return if !$cpuser_obj->child_workloads();
    }

    require Cpanel::APICommon::Error;

    return (
        $strfn->( $username_sr ? $$username_sr : () ),
        Cpanel::APICommon::Error::convert_to_payload(_ERROR_TYPE),
    );
}

sub _str_cpanel () {
    return locale()->maketext('Do not send API requests to this node. Send this request to your account’s parent node.');
}

sub _str_whm ($username) {
    require Whostmgr::API::1::Utils::Persona;
    return Whostmgr::API::1::Utils::Persona::get_send_to_parent_string($username);
}

1;
