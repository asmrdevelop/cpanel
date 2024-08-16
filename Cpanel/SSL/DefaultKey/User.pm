package Cpanel::SSL::DefaultKey::User;

# cpanel - Cpanel/SSL/DefaultKey/User.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DefaultKey::User

=head1 SYNOPSIS

    my $setting = Cpanel::SSL::DefaultKey::User::get('suzie');

=head1 DESCRIPTION

This module stores the logic for fetching a user’s default SSL key type,
with fallback to the system setting if that’s how the user’s account is
configured.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::LoadCpConf         ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::SSL::DefaultKey::Constants ();    # PPI NO PARSE - mis-parse

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 get( $USERNAME )

Returns the user’s default SSL key type.

=cut

sub get ($username) {

    my $key_type;

    if ( $username ne 'root' ) {

        # Use the reseller’s key-type preference.
        my $cpuser = Cpanel::Config::LoadCpUserFile::load_or_die($username);
        $key_type = $cpuser->{'SSL_DEFAULT_KEY_TYPE'};

        if ( !$key_type ) {
            warn "$username: no SSL_DEFAULT_KEY_TYPE; using system default";
        }
        elsif ( $key_type eq Cpanel::SSL::DefaultKey::Constants::USER_SYSTEM ) {
            undef $key_type;
        }
    }

    $key_type ||= do {
        require Cpanel::Config::LoadCpConf;
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

        $cpconf->{'ssl_default_key_type'};
    };

    return $key_type;
}

1;
