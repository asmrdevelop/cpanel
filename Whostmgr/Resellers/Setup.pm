package Whostmgr::Resellers::Setup;

# cpanel - Whostmgr/Resellers/Setup.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Resellers::Setup - Setup and Unsetup cPanel accounts as resellers

=head1 SYNOPSIS

    use Whostmgr::Resellers::Setup;

    # Setup bob as a reseller owned by root
    Whostmgr::Resellers::Setup::setup_reseller_and_sync_web_vhosts('bob');

    # Setup bob as a reseller and make bob owned by bob
    Whostmgr::Resellers::Setup::setup_reseller_and_sync_web_vhosts('bob', 1);

    # Unsetup bob as a reseller and transfer all of his previously owned accounts to root ownership
    Whostmgr::Resellers::Setup::unsetup_reseller_and_sync_web_vhosts('bob');

    # Unsetup bob as a reseller but leave all of his accounts owned by bob
    Whostmgr::Resellers::Setup::unsetup_reseller_and_sync_web_vhosts('bob', 1);


=head1 DESCRIPTION

This module provides tools to setup (add) and unsetup (remove) privileges
from an existing cPanel user.

=cut

use Cpanel::Imports;

use Cpanel::AcctUtils::Account     ();
use Cpanel::AcctUtils::Domain      ();
use Cpanel::AcctUtils::Owner       ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::ConfigFiles            ();
use Cpanel::Finally                ();
use Cpanel::Debug                  ();
use Cpanel::OrDie                  ();
use Cpanel::PwCache                ();
use Cpanel::Reseller               ();
use Cpanel::Reseller::Cache        ();
use Cpanel::SafeFile               ();
use Cpanel::ServerTasks            ();
use Cpanel::Userdomains            ();
use Whostmgr::Limits::Resellers    ();

=head2 setup_reseller_and_sync_web_vhosts($user, $isowner)

Setup a cPanel account to be a reseller.

=over 2

=item Input

=over 3

=item $user C<SCALAR>

    The cPanel user to be setup as a reseller

=item $isowner C<SCALAR>

    A boolean value that determines if the
    ownership of $user will be changed to
    be $user.

=back

=item Output

Returns 1 on success, dies on failure

=back

=cut

sub setup_reseller_and_sync_web_vhosts {
    my ( $user, $isowner ) = @_;

    my $do_after_setup = _web_vhosts_sync_hook($user);

    return _setupreseller( $user, $isowner );
}

=head2 unsetup_reseller_and_sync_web_vhosts($user, $skip_migrate_yn)

Setup a cPanel account to remove reseller privileges from.

=over 2

=item Input

=over 3

=item $user C<SCALAR>

    The cPanel user to remove reseller privileges from.

=item $skip_migrate_yn C<SCALAR>

    A boolean value that determines if the
    ownership of accounts that are currently
    owned by $user will be reset to root.

=back

=item Output

Returns 1 on success, dies on failure

=back

=cut

sub unsetup_reseller_and_sync_web_vhosts {
    my ( $user, $skip_migrate_yn ) = @_;

    my $do_after_setup = _web_vhosts_sync_hook($user);

    return _unsetupreseller( $user, $skip_migrate_yn );
}

#----------------------------------------------------------------------
# _setupreseller and _unsetupreseller behave differently in list versus
# scalar context.
# We need to sync web vhosts after the “main” action.
# In order to allow setup_reseller_and_sync_web_vhosts and
# unsetup_reseller_and_sync_web_vhosts to replace _setupreseller
# and _unsetupreseller calls in some contexts, the
# functions use Cpanel::Finally to do a vhosts sync after the setup/unsetup
# of reseller privileges. This way we don’t have to twiddle with return
# contexts.
#----------------------------------------------------------------------

sub _web_vhosts_sync_hook {
    my ($user) = @_;

    require Cpanel::ConfigFiles::Apache::vhost;
    return Cpanel::Finally->new(
        sub {
            Cpanel::OrDie::multi_return(
                sub {
                    Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);
                }
            );
        },
    );
}

sub _fail_setupreseller ($error) {
    require Cpanel::Logger;
    Cpanel::Logger::cplog( $error, 'notice', __FILE__, 1 );

    return ( 0, $error ) if wantarray;

    return 0;
}

sub _setupreseller {
    my ( $user, $isowner ) = @_;

    require Cpanel::Hooks;
    require Cpanel::Logger;
    my $logger = Cpanel::Logger->new();

    my ( $hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => "Resellers::setup",
            'stage'    => 'pre',
            'blocking' => 0,
        },
        { 'reseller' => $user, 'isowner' => $isowner },
    );

    if ( int @{$hook_msgs} ) {
        $logger->info( join( "\n", @{$hook_msgs} ) );
    }

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        my $error = '_setupreseller called for a user that does not exist.' . " ($user)";
        return _fail_setupreseller($error);
    }

    if ( Cpanel::Reseller::isreseller($user) ) {
        my $error = '_setupreseller tried to make a reseller out of a reseller when a normal user was expected.' . " ($user)";
        return _fail_setupreseller($error);
    }

    my $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    if ( $cpuser_data->{'DEMO'} == 1 ) {
        my $error = '_setupreseller called for a user in demo mode. Demo mode is not allowed for resellers.' . " ($user)";
        return _fail_setupreseller($error);
    }

    if ( $cpuser_data->child_workloads() ) {
        return _fail_setupreseller("“$user” is a child account. Child accounts cannot be resellers. To make “$user” a reseller, make that change on the account’s parent node.");
    }

    #----------------------------------------------------------------------

    my $reslock = Cpanel::SafeFile::safeopen( \*RES, '>>', $Cpanel::ConfigFiles::RESELLERS_FILE );
    if ( !$reslock ) {
        Cpanel::Debug::log_warn("Could not write to $Cpanel::ConfigFiles::RESELLERS_FILE: $!");
        return 0;
    }

    require Whostmgr::ACLS::Data;
    my $default_acls = join ',', @{ Whostmgr::ACLS::Data::get_default_acls() };
    print RES "${user}:$default_acls\n";
    Cpanel::SafeFile::safeclose( \*RES, $reslock );

    my $domain = Cpanel::AcctUtils::Domain::getdomain($user);
    $domain = '' unless defined $domain;
    my $acctlog_fh;
    my $acctlog = Cpanel::SafeFile::safeopen( $acctlog_fh, '>>', $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );
    if ( !$acctlog ) {
        Cpanel::Debug::log_warn("Could not write to $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE: $!");
        return 0;
    }
    chmod 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE;
    my $localtime = localtime();

    my $log_user        = $ENV{'USER'} || $ENV{'REMOTE_USER'} || Cpanel::PwCache::getusername();
    my $log_remote_user = $ENV{'REMOTE_USER'} || Cpanel::PwCache::getusername();

    syswrite( $acctlog_fh, "$localtime:ADDRESELLER:$log_remote_user:$log_user:$domain:$user\n" );
    Cpanel::SafeFile::safeclose( $acctlog_fh, $acctlog );

    Cpanel::Reseller::Cache::reset_cache($user);
    Cpanel::ServerTasks::queue_task( ["WHMChromeTasks"], "rebuild_whm_chrome" );

    # Calling hook prior to changing owner because too many callers
    # depend upon inspecting the return from _changeowner to redo
    # now.
    ( $hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => "Resellers::setup",
            'stage'    => 'post',
            'blocking' => 0,
        },
        { 'reseller' => $user, 'isowner' => $isowner },
    );
    if ( int @{$hook_msgs} ) {
        $logger->info( join( "\n", @{$hook_msgs} ) );
    }

    if ( defined $isowner && $isowner eq '1' ) {
        require Whostmgr::Accounts::Tiny;
        return Whostmgr::Accounts::Tiny::_changeowner( $user, $user );
    }

    return 1;
}

sub _unsetupreseller {
    my ( $user, $skip_migrate ) = @_;

    if ( !length $user ) {
        return wantarray ? ( 0, '_unsetupreseller requires a user to unsetup' ) : 0;
    }
    return if !-e $Cpanel::ConfigFiles::RESELLERS_FILE;

    $user =~ s/\///g;

    my $had_reseller = 0;

    my $reslock = Cpanel::SafeFile::safeopen( \*RES, '+<', $Cpanel::ConfigFiles::RESELLERS_FILE );
    if ( !$reslock ) {
        Cpanel::Debug::log_warn("Could not edit $Cpanel::ConfigFiles::RESELLERS_FILE: $!");
        return;
    }
    my @RES = <RES>;
    seek( RES, 0, 0 );
    foreach (@RES) {
        if ( !/^\Q${user}\E:/ ) {
            print RES;
        }
        else {
            $had_reseller = 1;
        }
    }
    truncate( RES, tell(RES) );
    Cpanel::SafeFile::safeclose( \*RES, $reslock );

    if ( -e "$Cpanel::ConfigFiles::MAIN_IPS_DIR/$user" ) {
        unlink("$Cpanel::ConfigFiles::MAIN_IPS_DIR/$user");
    }

    if ($had_reseller) {
        my $domain = Cpanel::AcctUtils::Domain::getdomain($user);
        $domain = '' unless defined $domain;
        my $acctlog_fh;
        my $acctlog = Cpanel::SafeFile::safeopen( $acctlog_fh, '>>', $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );
        if ( !$acctlog ) {
            Cpanel::Debug::log_warn("Could not write to $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE: $!");
            return 0;
        }
        chmod 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE;
        my $localtime = localtime();

        my $env_remote_user = $ENV{'REMOTE_USER'} || 'unknown';
        my $env_user        = $ENV{'USER'}        || 'unknown';

        print {$acctlog_fh} "$localtime:DELRESELLER:$env_remote_user:$env_user:$domain:$user\n";
        Cpanel::SafeFile::safeclose( $acctlog_fh, $acctlog );

        Cpanel::Userdomains::updateuserdomains();

        _delete_reseller_limits($user);
        unlink "$Cpanel::ConfigFiles::DELEGATED_IPS_DIR/$user";
    }

    my $owner = Cpanel::AcctUtils::Owner::getowner($user);
    if ( $user eq $owner ) {
        require Whostmgr::Accounts::Tiny;
        Whostmgr::Accounts::Tiny::_changeowner( $user, 'root' );
        $owner = 'root';
    }

    require Whostmgr::Resellers::Change;

    # Transfer ownership of owned accounts to owner of this account
    Whostmgr::Resellers::Change::change_users_owners( $user, $owner ) unless $skip_migrate;

    Cpanel::Reseller::Cache::reset_cache($user);

    return 1;
}

sub _delete_reseller_limits {
    my ($user)         = @_;
    my $lock_datastore = 1;
    my $limits         = Whostmgr::Limits::Resellers::load_all_reseller_limits($lock_datastore);
    delete $limits->{'data'}{$user};
    return Whostmgr::Limits::Resellers::saveresellerlimits($limits);
}

1;
