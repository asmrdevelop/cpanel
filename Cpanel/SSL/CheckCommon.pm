package Cpanel::SSL::CheckCommon;

# cpanel - Cpanel/SSL/CheckCommon.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::CheckCommon

=head1 DESCRIPTION

This module houses logic that’s useful in multiple “check” modules.
Currently that means L<Cpanel::SSL::VhostCheck> and
L<Cpanel::SSL::DynamicDNSCheck>.

=cut

#----------------------------------------------------------------------

use Cpanel::OpenSSL::Verify ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @problems = get_expiration_problems( $CERT_OBJ, $DAYS_ALLOWANCE )

Returns a list of problem strings that relate to certificate expiration.
Note that that list will B<NOT> include an I<actual> expiration because
C<get_problems_from_verify_result()> handles that.

Accepts arguments:

=over

=item *  a L<Cpanel::SSL::Objects::Certificate> instance. This object
B<SHOULD> have its entire certificate chain stored.

=item * however many days’ “allowance” should be considered before a
certificate is C<ALMOST_EXPIRED>. For example, if this value is 5, then
during the 5-day window prior to expiration this function will give
C<ALMOST_EXPIRED> as part of its returned list. The higher this number,
the more likely it is that the return will be nonempty.

=back

=cut

sub get_expiration_problems ( $cert_obj, $days_allowance ) {
    my $now = time;

    my $time_limit = $now + 86400 * $days_allowance;

    my @problems;

    if ( !$cert_obj->expired() && $cert_obj->is_expired_at($time_limit) ) {
        push @problems, 'ALMOST_EXPIRED';
    }

    my $ca_chain_is_valid = !$cert_obj->is_any_extra_certificate_expired_at($now);
    if ( $ca_chain_is_valid && $cert_obj->is_any_extra_certificate_expired_at($time_limit) ) {
        push @problems, 'CA_CERTIFICATE_ALMOST_EXPIRED';
    }

    return @problems;
}

=head2 @problems = get_problems_from_verify_result( $RESULT )

Returns a list of problem strings from a given $RESULT,
which is a L<Cpanel::SSL::Verify::Result> instance.

=cut

sub get_problems_from_verify_result ($verify) {
    my @problems;

    for my $depth ( 0 .. $verify->get_max_depth() ) {
        for my $err ( $verify->get_errors_at_depth($depth) ) {
            my $code = Cpanel::OpenSSL::Verify::error_name_to_code($err);

            #For legacy reasons, include the error number here.
            my $str = join(
                ':',
                'OPENSSL_VERIFY',
                $depth,
                $code,
                $err,
            );
            push @problems, $str;
        }
    }

    return @problems;
}

1;
