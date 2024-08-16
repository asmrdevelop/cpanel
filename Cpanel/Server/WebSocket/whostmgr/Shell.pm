package Cpanel::Server::WebSocket::whostmgr::Shell;

# cpanel - Cpanel/Server/WebSocket/whostmgr/Shell.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::Shell - Terminal in WHM

=cut

use parent qw(
  Cpanel::Server::WebSocket::AppBase::Shell
  Cpanel::Server::WebSocket::whostmgr
);

use Cpanel::Server::WebSocket::App::Shell::WHMDisable ();

use constant _ACCEPTED_ACLS => ('all');

# Require:
#   - root privileges
#   - no disable flag
#   - no “cptkt” username
#
sub _can_access ( $class, $server_obj ) {
    my $ok = $class->SUPER::_can_access($server_obj);

    $ok &&= !Cpanel::Server::WebSocket::App::Shell::WHMDisable->is_on();

    # cPanel technicians should not have access to this.
    $ok &&= ( 0 != index( $ENV{'REMOTE_USER'}, 'cptkt' ) );

    return $ok;
}

# If we run as root, then the shell process’s
# rlimits are raised to their maximum values first.
sub _get_before_exec_cr ( $self, $server_obj ) {
    if ( my $limits_hr = $server_obj->get_saved_pam_limits() ) {
        return sub {
            $limits_hr->restore();
        };
    }

    # NOTE: If we ever allow non-root resellers to use the shell from WHM,
    # we will need to ensure that such resellers don’t get root escalation!
    return \&_raise_rlimits;
}

sub _raise_rlimits {
    require Cpanel::Rlimit;
    Cpanel::Rlimit::set_rlimit_to_infinity();

    return;
}

1;
