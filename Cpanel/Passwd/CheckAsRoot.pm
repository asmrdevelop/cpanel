package Cpanel::Passwd::CheckAsRoot;

# cpanel - Cpanel/Passwd/CheckAsRoot.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Passwd::CheckAsRoot

=head1 SYNOPSIS

    my $is_valid = Cpanel::Passwd::CheckAsRoot::is_correct(
        'bob', '$ekr1t', 'TheCallingAppName',
    );

=head1 DESCRIPTION

This module implements logic for checking a user’s submitted password
when that submission comes B<from> a session. This is useful for any
case where the user needs to re-authenticate, e.g., to update
contact email addresses.

=head1 SECURITY

This interface serves the use case of checking, from the admin side,
whether a user-supplied password is the account’s password. In this
context we I<always> disregard $PASSWORD’s validity if the check is
rate-limited. If you think you have a good reason to deviate from
that behavior, B<PLEASE> B<confirm> B<with> B<cPanel’s> B<security>
B<team> before proceeding!

=cut

#----------------------------------------------------------------------

use Cpanel::CheckPass::UNIX       ();
use Cpanel::Exception             ();
use Cpanel::Passwd::Check::CpHulk ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $is_valid = is_correct( $USERNAME, $PASSWORD, $CONTEXT )

Returns a booleans that indicates whether $PASSWORD is $USERNAME’s
system-account password.

$CONTEXT is given to cphulkd as C<auth_service>. (It needn’t be a
service’s name.)

Throws an exception if that information can’t be discerned B<or> if the
user is rate-limited. In the latter case, a
L<Cpanel::Exception::RateLimited> instance is thrown.

=cut

sub is_correct ( $username, $password, $context ) {
    my $crypt_pass = ( getpwnam $username )[1];
    die "Failed to get $username’s password hash: $!" if !$crypt_pass;

    # For the sake of being able to log password-correctness in tandem
    # with the access check we check the password *before* talking to
    # cphulkd. But we’ll throw the validity check away if cphulkd says
    # we’re rate-limited.
    #
    my $password_valid = Cpanel::CheckPass::UNIX::checkpassword( $password, $crypt_pass ) ? 1 : 0;

    my $rate_limited = Cpanel::Passwd::Check::CpHulk::user_is_rate_limited(
        username    => $username,
        password    => $password,
        password_ok => $password_valid,
        context     => $context,
    );

    die Cpanel::Exception::create_raw('RateLimited') if $rate_limited;

    return $password_valid;
}

sub is_correct_team_user ( $username, $password ) {
    require Cpanel::Team::Config;
    my $crypt_pass = Cpanel::Team::Config::get_team_user($username)->{password};
    die "Failed to get $username’s password hash" if !$crypt_pass;

    my $password_valid = Cpanel::CheckPass::UNIX::checkpassword( $password, $crypt_pass ) ? 1 : 0;
    return $password_valid;
}
1;
