package Cpanel::Passwd::Check::CpHulk;

# cpanel - Cpanel/Passwd/Check/CpHulk.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Passwd::Check::CpHulk

=head1 SYNOPSIS

    my $rate_limited_yn = user_is_rate_limited(
        username => 'bob',
        password => '$ekr1t',
        password_ok => 0,
        context => 'TheCallingAppName',
    );

=head1 DESCRIPTION

This module contains logic to implement the cphulk (i.e., brute-force
protection) component of password validation for user requests. In this
context a root process answers a request sent from a pre-authenticated
user process.

(Brute-force protection is important here so that a compromised
account can’t do things like change its own password.)

=cut

#----------------------------------------------------------------------

use Cpanel::Debug        ();
use Cpanel::IP::Remote   ();
use Cpanel::Hulk         ();
use Cpanel::Config::Hulk ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = user_is_rate_limited( %OPTS )

Returns a boolean that indicates whether cphulkd says to rate-limit
the indicated user in response to a password check. This B<MUST> occur
B<after> validating the password that the user gave.

%OPTS are:

=over

=item * C<username> - The user’s name.

=item * C<password> (i.e., the string that the user gave as the password,
which may or may not match the account’s password)

=item * C<password_ok> - whether C<password> matches the user

=item * C<context> - The context from which the password validation
originates.

=back

=cut

sub user_is_rate_limited (%opts) {
    my ( $auth_user, $password, $authok, $service ) = @opts{ 'username', 'password', 'password_ok', 'context' };

    return 0 if !Cpanel::Config::Hulk::is_enabled();

    my $cphulk = Cpanel::Hulk->new();
    if (   $cphulk->connect()
        && $cphulk->register( 'cpanelpasswd', Cpanel::Hulk::getkey('cpanelpasswd') ) ) {

        my $remote_ip = Cpanel::IP::Remote::get_current_remote_ip();

        my $cphulk_code = $cphulk->can_login(
            'user'         => $auth_user,
            'status'       => $authok,
            'service'      => 'system',
            'auth_service' => $service,
            'authtoken'    => $password,
            'deregister'   => 1,            #disconnect
            'remote_ip'    => $remote_ip,
        );

        if ( $cphulk_code == Cpanel::Hulk::HULK_INVALID ) {

            # cphulkd said our request is invalid.
            # That shouldn’t happen, so let’s throw:
            die "cphulkd indicated an invalid request: username=$auth_user, status=$authok, auth_service=$service, remote_ip=$remote_ip";
        }

        if ( $cphulk_code == Cpanel::Hulk::HULK_LOCKED || $cphulk_code == Cpanel::Hulk::HULK_PERM_LOCKED ) {
            return 1;
        }

        # At this point we know cphulkd didn’t say to rate-limit.
        # If that response indicated an internal failure we’ll warn about it
        # but otherwise treat the response as not-rate-limited.
        #
        if ( $cphulk_code != Cpanel::Hulk::HULK_OK && $cphulk_code != Cpanel::Hulk::HULK_HIT ) {
            my $code_name = Cpanel::Hulk::response_code_name($cphulk_code);

            Cpanel::Debug::log_warn(qq{Brute force checking was skipped because cphulkd failed to process “$auth_user” from “$remote_ip” for “$service”. ($code_name)});
        }
    }

    return 0;
}

1;
