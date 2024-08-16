package Whostmgr::TweakSettings::Main::Setting::userdirprotect;

# cpanel - Whostmgr/TweakSettings/Main/Setting/userdirprotect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Main::Setting::userdirprotect

=head1 SYNOPSIS

n/a

=head1 DESCRIPTION

This module is just here to facilitate easy testing of this logic.

=cut

use strict;
use warnings;

use Try::Tiny;
use Cpanel::SafeFile    ();
use Cpanel::ServerTasks ();

#TODO: There should probably be a module that manages this
#datastore.
our $_MDD_FILE = '/var/cpanel/moddirdomains';

=head1 FUNCTIONS

=head2 action( VALUE, OLD_VALUE, FORCE )

VALUE is the new setting of the tweak setting.

OLD_VALUE is the old setting of the tweak setting.

FORCE is set if a forced update of tweak settings is happening.

Returns truthy for success and falsey for failure.

=cut

sub action {
    my ( $val, $oldval, $force ) = @_;

    # If they have a '/var/cpanel/moddirdomains', then assume
    # that they want to keep the values that are already there.
    # Otherwise create a default configuration
    # that sets the DefaultHost to excluded.

    if ( $val && !-e $_MDD_FILE ) {

        # Ensure that userdata for DefaultHost is present.

        _run_userdata_update();

        my $domainuser = _load_domain_user_hashref();
        $domainuser->{'DefaultHost'} = 'nobody';

        my %moddirdomains;

        for my $domain ( sort keys %{$domainuser} ) {
            if ( $domain =~ /\*/ ) { next; }
            $moddirdomains{$domain} = '';
        }

        $moddirdomains{'DefaultHost'} = '-1';

        my $mlock = Cpanel::SafeFile::safeopen( my $fh, '>', $_MDD_FILE );

        if ( !$mlock ) {
            print "Could not write to $_MDD_FILE!";
            return 0;
        }

        require Cpanel::WebVhosts::Owner;

        my %vhosts_updated;

        for my $domain ( sort keys %moddirdomains ) {
            print {$fh} $domain . ':' . $moddirdomains{$domain} . "\n" or warn "Failed to write to /var/cpanel/moddirdomains: $!";

            my $vhost_name = $domain;
            if ( $domain ne 'DefaultHost' ) {
                $vhost_name = Cpanel::WebVhosts::Owner::get_vhost_name_for_domain_or_undef($domain) or do {
                    undef $vhost_name;
                    warn "The system failed to determine a vhost for “$domainuser->{$domain}”’s domain “$domain”.";
                };
            }

            if ($vhost_name) {
                $vhosts_updated{$vhost_name} ||= do {
                    require Cpanel::Config::userdata;
                    Cpanel::Config::userdata::update_domain_userdirprotect_data( $domainuser->{$domain}, $vhost_name, $moddirdomains{$domain} );
                    1;
                };
            }
        }

        Cpanel::SafeFile::safeclose( $fh, $mlock );

        $force = 1;
    }

    if ( $force || $oldval ne $val ) {
        my $ok;

        try {
            _queue_task(
                [ 'ApacheTasks', 'TailwatchTasks' ],
                'build_apache_conf',
                'apache_restart --force',
                'reloadtailwatch'
            );
            $ok = 1;
        }
        catch {
            print $_;
        };
        return $ok || 0;
    }
    return 1;
}

#overridden in tests
sub _load_domain_user_hashref {
    require Cpanel::Config::LoadUserDomains;
    return scalar Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
}

#overridden in tests
sub _run_userdata_update {
    require Cpanel::SafeRun::Errors;
    Cpanel::SafeRun::Errors::saferunnoerror('/usr/local/cpanel/bin/userdata_update');
    return;
}

#overridden in tests
*_queue_task = \&Cpanel::ServerTasks::queue_task;

1;
