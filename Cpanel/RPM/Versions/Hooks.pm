package Cpanel::RPM::Versions::Hooks;

# cpanel - Cpanel/RPM/Versions/Hooks.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hooks::Manage ();

# This module  used to optimize based on /var/cpanel/legacy_hooks having a
# certain version number in it. This actually causes all legacy hooks to never
# get re-registered in case of deletion. As such I've moved all this code
# over into bin/register_hooks, as it is just yet another "legacy" hook to
# ensure is installed as as a "standardized hook".

our $hooks_dir               = '/usr/local/cpanel/scripts';
our %legacy_hook_scripts_map = (
    'dovecot' => {
        'pre'  => ['predovecotup'],
        'post' => [qw/postdovecotup/],
    },
    'exim' => {
        'pre'  => ['preeximup'],
        'post' => [qw/posteximup/],
    },
    'proftpd' => {
        'pre'  => ['preftpup'],
        'post' => [qw/postftpinstall postftpup/],
    },
    'pure-ftpd' => {
        'pre'  => ['preftpup'],
        'post' => [qw/postftpinstall postftpup/],
    },
    'MySQL55-server' => {
        'pre'  => ['premysqlup'],
        'post' => [qw/postmysqlinstall postmysqlup/],
    },
    'MySQL56-server' => {
        'pre'  => ['premysqlup'],
        'post' => [qw/postmysqlinstall postmysqlup/],
    },
    'MariaDB-server' => {
        'pre'  => ['premysqlup'],
        'post' => [qw/postmysqlinstall postmysqlup/],
    },
);

sub setup_legacy_hooks {
    my $num_registered = 0;
    foreach my $rpm ( sort keys %legacy_hook_scripts_map ) {
        foreach my $stage (qw{pre post}) {
            my $scripts = $legacy_hook_scripts_map{$rpm}->{$stage};
            foreach my $script ( sort @$scripts ) {
                my $script_path = "$hooks_dir/$script";

                # Let's trick the hook system for legacy hooks
                #   [ preserve an error if the file exists and is not executable ]
                my $todo = '/usr/local/cpanel/scripts/run_if_exists ' . $script_path;

                my %OPTS = (
                    'hook'     => $todo,
                    'event'    => $rpm,
                    'exectype' => 'script',
                    'category' => 'RPM::Versions',
                    'stage'    => $stage,
                    'force'    => 1,
                );

                # This sub we're calling already won't register dupes, so we don't
                # have to do anything special to avoid dupe hooks.
                my $result = Cpanel::Hooks::Manage::add(%OPTS);

                if ( $result && $result eq 'OK' ) {
                    print "Registered standard hook for $OPTS{'category'}::$OPTS{'event'}\n";
                    $num_registered++;
                }
                elsif ($Cpanel::Hooks::Manage::ERRORMSG) {
                    warn $Cpanel::Hooks::Manage::ERRORMSG;
                    $Cpanel::Hooks::Manage::ERRORMSG = '';
                }
            }
        }
    }
    return $num_registered;
}

1;
