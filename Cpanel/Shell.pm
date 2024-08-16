package Cpanel::Shell;

# cpanel - Cpanel/Shell.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::FileUtils::Read ();
use Cpanel::PwCache::Get    ();

our $SHELLS_FILE = '/etc/shells';

#These are in order of preference as default shell.
our @BASE_SHELLS = qw(
  /bin/bash
  /bin/tcsh
  /bin/csh
  /bin/sh
);

our $JAIL_SHELL = '/usr/local/cpanel/bin/jailshell';
our $NO_SHELL   = '/usr/local/cpanel/bin/noshell';
our $DEMO_SHELL = '/usr/local/cpanel/bin/demoshell';

#Setting the shell to /bin/false is common on non-cPanel servers.
#This is here to simplify account transfers from those environments.
our $BIN_FALSE = '/bin/false';

#TODO: Once we are ready to do so, transition to reading this from
#cpuser rather than from pw.
{
    no warnings 'once';
    *get_shell = \&Cpanel::PwCache::Get::getshell;
}

#This is the preferred way of determining whether a given
#shell is a valid shell on this system.
sub is_valid_shell {
    my ($shell_in_question) = @_;

    for ( $JAIL_SHELL, $NO_SHELL, $DEMO_SHELL, $BIN_FALSE ) {
        return 1 if $_ eq $shell_in_question;
    }

    my $is_valid = 0;

    Cpanel::FileUtils::Read::for_each_line(
        $SHELLS_FILE,
        sub {
            return if !m{\A\Q$shell_in_question\E\s*\z};
            $is_valid = 1;
            (shift)->stop();
        },
    );

    return $is_valid;
}

sub is_usable_shell {
    my ($shell_in_question) = @_;

    return 0 if $shell_in_question eq $NO_SHELL;
    return 0 if $shell_in_question eq $BIN_FALSE;

    return is_valid_shell($shell_in_question);
}

#For set_shell, see Whostmgr::Accounts::Shell.

1;
