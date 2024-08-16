package Cpanel::Quota::Cache;

# cpanel - Cpanel/Quota/Cache.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Alarm                        ();
use Cpanel::Debug                        ();
use Cpanel::Exception                    ();
use Cpanel::SysQuota                     ();
use Cpanel::Quota::Cache::QuotasDisabled ();
use Cpanel::Quota::Cache::QuotasBroken   ();
use Cpanel::Quota::OverCache             ();
use Cpanel::PIDFile                      ();
use Try::Tiny;

use constant QUOTA_CACHE_PID_FILE => '/var/cpanel/quota_cache_running';
use constant QUOTA_CACHE_TIMEOUT  => 5 * 60;                              # 5 minutes

sub update_quota_cache_dir {
    my ($quiet) = @_;
    my $result;

    $quiet //= 0;

    try {
        $result = Cpanel::PIDFile->do(
            QUOTA_CACHE_PID_FILE,
            sub { return _do_update_quota_cache_dir($quiet); }
        );
    }
    catch {
        my $exception = $_;
        my $msg       = Cpanel::Exception::get_string($exception);

        # Logging of other exceptions is handled elsewhere(?)
        if ( $exception->isa('Cpanel::Exception::CommandAlreadyRunning') ) {
            Cpanel::Debug::log_info($msg) if !$quiet;
            $result = 0;
        }
        else {
            die $exception;    # Does this really need to re-throw the exception? All users ignore it.
        }
    };

    return $result;
}

sub _do_update_quota_cache_dir {
    my ($quiet) = @_;

    my $alarm = Cpanel::Alarm->new(
        QUOTA_CACHE_TIMEOUT,
        sub {
            my $exception = Cpanel::Exception::create_raw( 'Timeout', 'Timeout while trying to update quota cache' );
            Cpanel::Debug::log_warn( $exception->to_string() ) if !$quiet;
            die $exception;
        }
    );

    my ($repquota) = Cpanel::SysQuota::fetch_system_repquota();

    if ( !defined($repquota) ) {
        create_disabled_quotas_flag();
        if ( !$quiet ) {
            my $msg = 'Failed to fetch quota information. Please make sure quotas are enabled.';
            Cpanel::Debug::log_warn($msg);
            die $msg;
        }
        return 0;
    }

    remove_disabled_quotas_flag() if disabled_quotas_flag_exists();

    # Check if it looks like quotas may be broken for one or more homedir mounts
    # If they are, we need to do things like not tell dovecot to check quotas temporarily
    # so that users can at least auth and read their mail, see case CPANEL-26002
    if ( Cpanel::SysQuota::userquota_probably_broken() ) {
        create_broken_userquota_flag() unless broken_userquota_flag_exists();
    }
    else {
        remove_broken_userquota_flag() if broken_userquota_flag_exists();
    }

    my ( $qrused, $qrlimit ) = Cpanel::SysQuota::analyzerepquotadata();

    if ( !defined $qrused || !scalar keys %{$qrused} ) {
        Cpanel::Debug::log_info('No quota information retrieved ()') if !$quiet;
        return 0;
    }

    my %overquota;
    foreach my $quota_user ( keys %{$qrused} ) {
        my $used  = $qrused->{$quota_user};
        my $limit = $qrlimit->{$quota_user};
        unless ( !$limit || $limit eq 'unlimited' ) {
            if ( $used >= $limit ) {
                $overquota{$quota_user} = 1;
            }
        }
    }

    for my $quota_user ( Cpanel::Quota::OverCache::get_users_at_blocks_quota() ) {
        if ( !exists $overquota{$quota_user} ) {
            Cpanel::Quota::OverCache::unset_user_at_blocks_quota($quota_user);
        }
        else {
            delete $overquota{$quota_user};
        }
    }

    foreach my $quota_user ( keys %overquota ) {
        try {
            Cpanel::Quota::OverCache::set_user_at_blocks_quota(
                $quota_user,
                $qrused->{$quota_user},
                $qrlimit->{$quota_user},
            );
        }
        catch { warn $_ };
    }

    # Make sure the permissions on the maildirsize files is correct for our email users
    # For each homedir we need to find all the maildirsize files there and check they are 0600
    # If they aren't sending mails will be broken due to quota
    Cpanel::SysQuota::correct_user_maildirsize_permissions();

    return 1;
}

sub create_disabled_quotas_flag {
    return Cpanel::Quota::Cache::QuotasDisabled->set_on();
}

sub remove_disabled_quotas_flag {
    return Cpanel::Quota::Cache::QuotasDisabled->set_off();
}

sub disabled_quotas_flag_exists {
    return Cpanel::Quota::Cache::QuotasDisabled->is_on();
}

sub create_broken_userquota_flag {
    return Cpanel::Quota::Cache::QuotasBroken->set_on();
}

sub remove_broken_userquota_flag {
    return Cpanel::Quota::Cache::QuotasBroken->set_off();
}

sub broken_userquota_flag_exists {
    return Cpanel::Quota::Cache::QuotasBroken->is_on();
}

# For tests
sub _localtime {
    return localtime();
}

1;
