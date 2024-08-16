package Whostmgr::Resellers;

# cpanel - Whostmgr/Resellers.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::AcctUtils::Account      ();
use Cpanel::AcctUtils::Domain       ();
use Cpanel::ConfigFiles             ();
use Cpanel::FileUtils::TouchFile    ();
use Cpanel::Debug                   ();
use Cpanel::PwCache::Clear          ();
use Cpanel::Reseller                ();
use Cpanel::Reseller::Cache         ();
use Cpanel::SafeFile                ();
use Cpanel::SafeRun::Errors         ();
use Cpanel::Validate::NameServer    ();
use Whostmgr::AcctInfo              ();
use Whostmgr::Limits::PackageLimits ();
use Whostmgr::Limits::Resellers     ();
use Whostmgr::Resellers::Check      ();
use Whostmgr::Resellers::Parse      ();
use Whostmgr::Resellers::Ips        ();

*get_reseller_ips    = *Whostmgr::Resellers::Ips::get_reseller_ips;
*set_reseller_ips    = *Whostmgr::Resellers::Ips::set_reseller_ips;
*get_reseller_mainip = *Whostmgr::Resellers::Ips::get_reseller_mainip;
*set_reseller_mainip = *Whostmgr::Resellers::Ips::set_reseller_mainip;

*is_reseller = *Whostmgr::Resellers::Check::is_reseller;

sub remove_acls_from_all_resellers {
    my (@toremove) = @_;

    return unless scalar @toremove;

    my $reseller_file = $Cpanel::ConfigFiles::RESELLERS_FILE;

    return unless -e $reseller_file;

    my $fh;
    my $lock = Cpanel::SafeFile::safeopen( $fh, '+<', $reseller_file );

    return unless $lock;

    my $resellers = Whostmgr::Resellers::Parse::_parse_reseller_fh($fh);

    my %skip = map { $_ => 1 } @toremove;

    return unless defined $resellers;
    foreach my $reseller ( sort keys %$resellers ) {
        $resellers->{$reseller} = [ grep { !defined $skip{$_} } @{ $resellers->{$reseller} } ];
    }

    _save_and_close_reseller( $fh, $lock, $resellers );

    return 1;
}

sub _save_and_close_reseller {
    my ( $fh, $lock, $data ) = @_;

    seek $fh, 0, 0;
    foreach my $reseller ( sort keys %$data ) {
        print {$fh} $reseller . ':' . join( ',', sort @{ $data->{$reseller} } ) . "\n";
    }
    truncate $fh, tell($fh);

    Cpanel::SafeFile::safeclose( $fh, $lock );

    return;
}

sub add_pkg_permission {
    my $user     = shift;
    my $pkg_name = shift;

    my $reseller_limits = Whostmgr::Limits::Resellers::load_resellers_limits();

    if ( $reseller_limits->{'limits'}->{'preassigned_packages'}->{'enabled'} ) { return; }    #do not auto grant the permission

    {
        my $package_limits = Whostmgr::Limits::PackageLimits->load(1);
        $package_limits->create_for_reseller( $pkg_name, $user, 1 );
        $package_limits->save();
    }
}

sub set_reseller_acls {
    my $reseller  = shift;
    my $racls     = shift;
    my $matchonly = shift;
    my @NEWACLL;
    my $root_priv     = 0;
    my $had_root_priv = 0;

    if ( !Cpanel::Reseller::isreseller($reseller) ) {
        return 0, 'Not a reseller.';
    }

    foreach my $acl ( keys %{$racls} ) {
        next if ( $acl !~ /^acl-/ );
        if ( $matchonly && !$racls->{$acl} ) { next; }
        $acl =~ s/^acl-//g;
        if ( $acl eq 'all' ) {
            $root_priv = 1;
        }
        push @NEWACLL, $acl;
    }
    if ( !-e $Cpanel::ConfigFiles::RESELLERS_FILE ) {
        Cpanel::FileUtils::TouchFile::touchfile($Cpanel::ConfigFiles::RESELLERS_FILE);
    }

    my $res_fh;
    my $acllock = Cpanel::SafeFile::safeopen( $res_fh, '+<', $Cpanel::ConfigFiles::RESELLERS_FILE );
    if ( !$acllock ) {
        Cpanel::Debug::log_warn("Could not edit $Cpanel::ConfigFiles::RESELLERS_FILE: $!");
        return 0;
    }

    {
        my $acls = Whostmgr::Resellers::Parse::_parse_reseller_fh($res_fh);
        $acls->{$reseller} = \@NEWACLL;
        _save_and_close_reseller( $res_fh, $acllock, $acls );
    }

    if ( $root_priv != $had_root_priv ) {
        my $type   = $root_priv ? 'GRANTROOT' : 'REVOKEROOT';
        my $domain = Cpanel::AcctUtils::Domain::getdomain($reseller);
        $domain = '' unless defined $domain;
        my $acct_fh;
        my $acctlog = Cpanel::SafeFile::safeopen( $acct_fh, ">>", $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );
        if ( !$acctlog ) {
            Cpanel::Debug::log_warn("Could not write to $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE: $!");
            return;
        }
        chmod 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE;
        my $localtime = localtime();

        my $env_remote_user = $ENV{'REMOTE_USER'} || 'unknown';
        my $env_user        = $ENV{'USER'}        || 'unknown';

        print {$acct_fh} "$localtime:$type:$env_remote_user:$env_user:$domain:$reseller\n";
        Cpanel::SafeFile::safeclose( $acct_fh, $acctlog );
    }

    # need to reset the cache and dnsadmin cache for that user
    Cpanel::Reseller::Cache::reset_cache($reseller);

    return ( 1, "Reseller Acls Saved" );
}

sub apply_acl_list {
    my $reseller = shift;
    my $acl_list = shift;

    if ( !length $reseller ) {
        return 0, 'apply_acl_list requires a reseller.';
    }

    $acl_list =~ s/\///g;
    my %ACLS;

    if ( !$reseller || !$acl_list ) { return; }

    open( my $acl_fh, '<', "$Cpanel::ConfigFiles::ACL_LISTS_DIR/$acl_list" );
    while ( readline($acl_fh) ) {
        chomp();
        next if (/^\s*$/);
        my ( $name, $value ) = split( /=/, $_, 2 );
        $ACLS{ 'acl-' . $name } = $value;
    }
    close($acl_fh);
    return set_reseller_acls( $reseller, \%ACLS, 1 );
}

sub _set_if_exists {
    my $source_href = shift;
    my $source_key  = shift;
    my $target_href = shift;
    my $target_key  = shift;
    my $value       = shift;

    if ( !defined $target_key ) {
        $target_key = $source_key;
    }

    if ( !defined $value ) {
        $value = $source_href->{$source_key};
    }

    if ( exists $source_href->{$source_key} ) {
        $target_href->{$target_key} = $value;
    }
    return;
}

sub set_reseller_limits {
    my %args = @_;
    my $user = $args{'user'};

    # TODO:
    #if ( !length $user ) {
    #    return 0, 'set_reseller_limits requires a user to set the limits for.';
    #}
    if ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }

    my $enable_overselling_bandwidth = int $args{'enable_overselling_bandwidth'} ? 1 : 0;
    my $enable_overselling_diskspace = int $args{'enable_overselling_diskspace'} ? 1 : 0;
    my $enable_overselling;

    if ( !exists $args{'enable_overselling'} ) {
        $enable_overselling = int $args{'enable_overselling'} ? 1 : 0;
    }

    my $enable_resource_limits       = int $args{'enable_resource_limits'} ? 1 : 0;
    my $bandwidth_limit              = abs int $args{'bandwidth_limit'};
    my $diskspace_limit              = abs int $args{'diskspace_limit'};
    my $enable_package_limits        = int $args{'enable_package_limits'}        ? 1 : 0;
    my $enable_package_limit_numbers = int $args{'enable_package_limit_numbers'} ? 1 : 0;
    my $enable_account_limit         = int $args{'enable_account_limit'}         ? 1 : 0;
    my $account_limit                = abs int $args{'account_limit'};

    my $limits  = Whostmgr::Limits::Resellers::load_all_reseller_limits(1);
    my $rlimits = $limits->{'data'}->{$user}->{'limits'};
    if ( !defined $rlimits ) {
        $rlimits = {};
        $limits->{'data'}->{$user}->{'limits'} = $rlimits;
    }

    if ( !exists $rlimits->{'resources'} ) {
        $rlimits->{'resources'} = {};
    }
    _set_if_exists(
        \%args,                  'enable_resource_limits',
        $rlimits->{'resources'}, 'enabled',
        $enable_resource_limits,
    );

    if ( !exists $rlimits->{'resources'}->{'type'} ) {
        $rlimits->{'resources'}->{'type'} = {};
    }
    _set_if_exists(
        \%args,                            'bandwidth_limit',
        $rlimits->{'resources'}->{'type'}, 'bw',
        $bandwidth_limit,
    );
    _set_if_exists(
        \%args,                            'diskspace_limit',
        $rlimits->{'resources'}->{'type'}, 'disk',
        $diskspace_limit,
    );

    if ( !exists $rlimits->{'resources'}->{'overselling'} ) {
        $rlimits->{'resources'}->{'overselling'} = {};
    }
    _set_if_exists(
        \%args,                                   'enable_overselling',
        $rlimits->{'resources'}->{'overselling'}, 'enabled',
        $enable_overselling,
    );

    if ( !exists $rlimits->{'resources'}->{'overselling'}->{'type'} ) {
        $rlimits->{'resources'}->{'overselling'}->{'type'} = {};
    }
    _set_if_exists(
        \%args,                                             'enable_overselling_bandwidth',
        $rlimits->{'resources'}->{'overselling'}->{'type'}, 'bw',
        $enable_overselling_bandwidth,
    );
    _set_if_exists(
        \%args,                                             'enable_overselling_diskspace',
        $rlimits->{'resources'}->{'overselling'}->{'type'}, 'disk',
        $enable_overselling_diskspace,
    );

    if ( !exists $rlimits->{'number_of_accounts'} ) {
        $rlimits->{'number_of_accounts'} = {};
    }
    _set_if_exists(
        \%args,                           'enable_account_limit',
        $rlimits->{'number_of_accounts'}, 'enabled',
        $enable_account_limit,
    );
    _set_if_exists(
        \%args,                           'account_limit',
        $rlimits->{'number_of_accounts'}, 'accounts',
        $account_limit,
    );

    if ( !exists $rlimits->{'preassigned_packages'} ) {
        $rlimits->{'preassigned_packages'} = {};
    }
    _set_if_exists(
        \%args,                             'enable_package_limits',
        $rlimits->{'preassigned_packages'}, 'enabled',
        $enable_package_limits,
    );

    if ( !exists $rlimits->{'number_of_packages'} ) {
        $rlimits->{'number_of_packages'} = {};
    }
    _set_if_exists(
        \%args,                           'enable_package_limit_numbers',
        $rlimits->{'number_of_packages'}, 'enabled',
        $enable_package_limit_numbers,
    );

    Whostmgr::Limits::Resellers::saveresellerlimits($limits);

    return 1, 'Successfully set reseller account creation limits.';
}

## via Whostmgr/XMLUI/Resellers.pm's 'setresellerpackagelimit' call
sub set_reseller_package_limit {
    my ( $user, $no_limit, $pkg_name, $allowed, $number ) = @_;

    # TODO:
    #if ( !length $user ) {
    #    return 0, 'set_reseller_package_limit requires a user to set the package limit for';
    #}

    if ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }

    if ( defined $allowed ) {
        $allowed = int $allowed ? 1 : 0;
    }

    if ( defined $number ) {
        $number = abs int $number;
    }

    my $package_limits = Whostmgr::Limits::PackageLimits->load(1);

    if ($no_limit) {
        my $ar_pkg_names = $package_limits->list_packages();
        foreach my $pkg_name (@$ar_pkg_names) {
            $package_limits->delete_reseller( $pkg_name, $user );
        }
    }
    elsif ( !-e "$Cpanel::ConfigFiles::PACKAGES_DIR/$pkg_name" ) {
        return 0, 'Selected package does not exist.  Limits can not be set.';
    }
    else {
        if ( defined $allowed ) {
            $package_limits->create_for_reseller( $pkg_name, $user, $allowed );
        }
        if ( defined $number ) {
            $package_limits->number_for_reseller( $pkg_name, $user, $number );
        }
    }

    $package_limits->save();

    return 1, 'Successfully set reseller package limit.';
}

sub _suspend_account {
    my $user     = shift;
    my $reason   = shift;
    my $disallow = shift;

    if ( !length $user ) {
        return '_suspend_account requires a user to suspend';
    }

    my $set_gateway_interface = 0;
    my $old_gateway_interface;

    if ( exists $ENV{'GATEWAY_INTERFACE'} && defined $ENV{'GATEWAY_INTERFACE'} ) {
        $set_gateway_interface = 1;
        $old_gateway_interface = $ENV{'GATEWAY_INTERFACE'};
        delete $ENV{'GATEWAY_INTERFACE'};
    }

    my $msg;
    $msg = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/suspendacct', '--', $user, $reason, $disallow );

    if ($set_gateway_interface) {
        $ENV{'GATEWAY_INTERFACE'} = $old_gateway_interface;
    }

    return $msg;
}

sub _unsuspend_account {
    my $user = shift;

    my $set_gateway_interface = 0;
    my $old_gateway_interface;

    if ( exists $ENV{'GATEWAY_INTERFACE'} && defined $ENV{'GATEWAY_INTERFACE'} ) {
        $set_gateway_interface = 1;
        $old_gateway_interface = $ENV{'GATEWAY_INTERFACE'};
        delete $ENV{'GATEWAY_INTERFACE'};
    }

    my $msg;
    $msg = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/unsuspendacct', '--', $user );

    if ($set_gateway_interface) {
        $ENV{'GATEWAY_INTERFACE'} = $old_gateway_interface;
    }

    return $msg;
}

sub _account_suspended {
    my ( $user, $output ) = @_;

    return unless defined $output;

    if ( $output =~ m/Account Already Suspended/ ) {
        return 1;
    }

    return $output =~ m/\Q$user\E's account has been suspended/;
}

sub _account_unsuspended {
    my ( $user, $output ) = @_;

    return unless defined $output;
    return $output =~ m/\Q$user\E's account is now active/;
}

sub suspend_reseller {
    my $user          = shift;
    my $reason        = shift || 'No reason supplied.';
    my $disallow      = int( shift || 0 ) ? 1 : 0;
    my $reseller_only = int( shift || 0 ) ? 1 : 0;

    if ( !length $user ) {
        return 0, 'suspend_reseller requires a user to unsuspend';
    }
    elsif ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }

    my $msg = _suspend_account( $user, $reason, $disallow );

    if ( !_account_suspended( $user, $msg ) ) {
        return 0, 'Failed to suspend reseller.', $msg;
    }

    my @msgs;
    push @msgs, $msg;

    if ($reseller_only) {
        push( @msgs, "Accounts owned by $user were not suspended because the reseller-only parameter was set" );
    }
    else {
        my %accounts = Whostmgr::AcctInfo::getaccts($user);
        foreach my $account ( sort keys %accounts ) {
            next if ( $account eq $user );
            next if ( !Cpanel::AcctUtils::Account::accountexists($account) );

            $msg = _suspend_account( $account, $reason, $disallow );

            if ( !_account_suspended( $account, $msg ) ) {
                $msg = "Failed to suspend account: $account";
            }

            push @msgs, $msg;
        }
    }

    # we need to purge cache as the suspend information is based on the shadow password
    Cpanel::PwCache::Clear::clear_global_cache();

    return 1, 'Finished suspending reseller.', join( "\n", @msgs );
}

sub unsuspend_reseller {
    my $user          = shift;
    my $reseller_only = int( shift || 0 ) ? 1 : 0;

    if ( !length $user ) {
        return 0, 'unsuspend_reseller requires a user to unsuspend';
    }
    elsif ( !Cpanel::Reseller::isreseller($user) ) {
        return 0, 'Specified user is not a reseller.';
    }
    my $msg = _unsuspend_account($user);

    if ( !_account_unsuspended( $user, $msg ) ) {
        return 0, 'Failed to unsuspend reseller.', $msg;
    }

    my @msgs;
    push @msgs, $msg;

    if ($reseller_only) {
        push( @msgs, "Accounts owned by $user were not unsuspended because the reseller-only parameter was set" );
    }
    else {
        my %accounts = Whostmgr::AcctInfo::getaccts($user);
        foreach my $account ( sort keys %accounts ) {
            next if ( $account eq $user );
            next if ( !Cpanel::AcctUtils::Account::accountexists($account) );

            $msg = _unsuspend_account($account);

            if ( !_account_unsuspended( $account, $msg ) ) {
                $msg = "Failed to unsuspend account: $account";
            }

            push @msgs, $msg;
        }
    }

    # we need to purge cache as the suspend information is based on the shadow password
    Cpanel::PwCache::Clear::clear_global_cache();

    return 1, 'Finished unsuspending reseller.', join( "\n", @msgs );
}

sub set_nameservers {
    my $reseller = shift;
    my $nsref    = shift;

    if ( !Cpanel::Reseller::isreseller($reseller) ) {
        return 0, 'Specified user is not a reseller.';
    }

    foreach my $ns (@$nsref) {
        next if !length $ns;
        $ns = Cpanel::Validate::NameServer::normalize($ns);
        if ( !Cpanel::Validate::NameServer::is_valid($ns) ) {
            Cpanel::Debug::log_warn("Invalid nameserver supplied: $ns");
            return 0, 'Invalid nameserver supplied.';
        }
    }

    Cpanel::FileUtils::TouchFile::touchfile($Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE);
    my %RESELLER_NAMESERVERS;

    my $rlock = Cpanel::SafeFile::safeopen( \*RES, '+<', $Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE );
    if ( !$rlock ) {
        Cpanel::Debug::log_warn("Could not edit $Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE: $!");
        return 0, 'Unable to edit resellers nameservers file.';
    }

    my $msg = 'Set resellers nameservers.';

    while (<RES>) {
        my ( $reseller_name, $nameserverlist ) = split( /:/, $_, 2 );
        chomp $nameserverlist;
        $RESELLER_NAMESERVERS{$reseller_name} = [ split( /\,/, $nameserverlist ) ];
    }

    my $current_ns = $RESELLER_NAMESERVERS{$reseller};

    my $nameservers_changed = $#$current_ns != $#$nsref
      || grep { $nsref->[$_] ne $current_ns->[$_] } ( 0 .. $#$nsref );

    if ($nameservers_changed) {
        $RESELLER_NAMESERVERS{$reseller} = $nsref;

        seek( RES, 0, 0 );
        foreach my $reseller_name ( sort keys %RESELLER_NAMESERVERS ) {
            print RES join( ':', $reseller_name, join( ',', @{ $RESELLER_NAMESERVERS{$reseller_name} } ) ) . "\n";
        }
        truncate( RES, tell(RES) );
    }
    else {

        #if the nameservers didn't change, the return value ideally should reflect that
        #but, failing that, at least the message can describe it
        $msg = 'Not updating with identical nameserver values.';
    }

    Cpanel::SafeFile::safeclose( \*RES, $rlock );

    return 1, $msg;
}

sub get_account_counts {
    my $user = shift;
    my %counts;

    my $limits  = Whostmgr::Limits::Resellers::load_all_reseller_limits();
    my $rlimits = $limits->{$user}->{'limits'};

    if ( $rlimits->{'number_of_accounts'}->{'enabled'} ) {
        $counts{'limit'} = $rlimits->{'number_of_accounts'}->{'accounts'};
    }
    else {
        $counts{'limit'} = '';
    }

    $counts{'suspended'} = 0;

    my $suspended = Whostmgr::AcctInfo::suspendedlist();
    my %accounts  = Whostmgr::AcctInfo::getaccts($user);
    foreach my $account ( sort keys %accounts ) {
        if ( exists $suspended->{$account} ) {
            ++$counts{'suspended'};
        }
    }

    $counts{'active'} = ( scalar keys %accounts ) - $counts{'suspended'};

    return wantarray ? %counts : \%counts;
}

sub change_user_name {
    my ( $oldreseller, $newreseller ) = @_;

    foreach my $resfile ( $Cpanel::ConfigFiles::RESELLERS_FILE, $Cpanel::ConfigFiles::RESELLERS_NAMESERVERS_FILE ) {
        if ( -f $resfile ) {

            # make sure the file exists and if not create it -- fix for moving in new resellers
            if ( !-e $resfile ) {
                Cpanel::FileUtils::TouchFile::touchfile($resfile);
            }
            my $res_fh;
            my $dlock = Cpanel::SafeFile::safeopen( $res_fh, '+<', $resfile );
            if ( !$dlock ) {
                Cpanel::Debug::log_warn("Could not edit $resfile: $!");
                return;
            }
            my @DATA = <$res_fh>;
            seek( $res_fh, 0, 0 );
            print {$res_fh} join( '', map { s/^\Q$oldreseller\E:/$newreseller:/g; $_; } @DATA );
            truncate( $res_fh, tell($res_fh) );
            Cpanel::SafeFile::safeclose( $res_fh, $dlock );
        }
    }
    return;
}

1;
