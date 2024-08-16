package Whostmgr::Accounts::Shell::Default;

# cpanel - Whostmgr/Accounts/Shell/Default.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Shell              ();
use Cpanel::Config::LoadCpConf ();

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Shell::Default - Get the default system shell.

=head1 SYNOPSIS

    use Whostmgr::Accounts::Shell::Default;

    my $default_shell = Whostmgr::Accounts::Shell::Default::get_default_shell();

=head2 get_default_shell()

Returns the default shell for the system based on the current
system configuration.

=cut

sub get_default_shell {
    my ($cpconf_ref) = @_;

    $cpconf_ref ||= Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( $cpconf_ref->{'jaildefaultshell'} ) {
        return $Cpanel::Shell::JAIL_SHELL;
    }
    elsif ( exists $cpconf_ref->{'defaultshell'} && -x $cpconf_ref->{'defaultshell'} ) {
        return $cpconf_ref->{'defaultshell'};
    }

    foreach my $shell (@Cpanel::Shell::BASE_SHELLS) {
        if ( -x $shell ) {
            return $shell;
        }
        elsif ( -x '/usr/local/' . $shell ) {
            return '/usr/local/' . $shell;
        }
    }

    return $Cpanel::Shell::JAIL_SHELL;
}

1;
