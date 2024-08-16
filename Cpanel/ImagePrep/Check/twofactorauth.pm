
# cpanel - Cpanel/ImagePrep/Check/twofactorauth.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check::twofactorauth;

use cPstrict;
use parent 'Cpanel::ImagePrep::Check';

use Cpanel::Config::userdata::TwoFactorAuth::Secrets ();

=head1 NAME

Cpanel::ImagePrep::Check::twofactorauth - A subclass of C<Cpanel::ImagePrep::Check>.

=cut

sub _description {
    return <<EOF;
Check whether Two-Factor Authentication is set up.
EOF
}

sub _check ($self) {

    # The only user we should realistically expect to find here is root. An earlier check would have aborted the run if cPanel accounts were found.
    my $users_with_2fa = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } )->read_userdata();
    if ( ref $users_with_2fa eq 'HASH' && %$users_with_2fa ) {
        die <<EOF;
You have Two-Factor Authentication configured. This is not a supported configuration for template VMs.

Users with 2FA data:
@{[join "\n", map { "  - $_" } sort keys %$users_with_2fa]}
EOF
    }
    $self->loginfo('No 2FA');
    return;
}

1;
