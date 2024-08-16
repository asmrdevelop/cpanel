package Cpanel::Session::Temp::Active;

# cpanel - Cpanel/Session/Temp/Active.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Session::Constants ();
use constant { _ENOENT => 2 };

=encoding utf-8

=head1 NAME

Cpanel::Session::Temp::Active - Fetch active temp sessions.

=head1 SYNOPSIS

    use Cpanel::Session::Temp::Active;

    my $session_ar = Cpanel::Session::Temp::Active::get_all_active_user_temp_sessions();

=head2 get_all_active_user_temp_sessions($user)

Returns an arrayref of arrayref of all currently
active temp session users.

Example:
        [
            ['cpses555533'],
            ['cpses555534']
        ]

=cut

sub get_all_active_user_temp_sessions {
    my ($user) = @_;

    my @temp_users;
    local $!;
    if ( opendir( my $session_dh, $Cpanel::Session::Constants::CPSES_KEYS_DIR ) ) {
        my @sessions_to_check = grep { index( $_, "$user:" ) == 0 } readdir($session_dh);
        foreach my $session (@sessions_to_check) {
            push @temp_users, [ ( split( ':', $session, 2 ) )[1] ];
        }
    }
    elsif ( $! != _ENOENT() ) {
        die "Failed to open “$Cpanel::Session::Constants::CPSES_KEYS_DIR” because of an error: $!";
    }

    return \@temp_users;
}

1;
