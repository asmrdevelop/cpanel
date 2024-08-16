package Whostmgr::Accounts::Suspension;

# cpanel - Whostmgr/Accounts/Suspension.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Suspension - Suspend or unsuspend a cPanel account

=head1 SYNOPSIS

    my $prevent_reseller_unsuspend = 0;
    my $should_ftp_accts_be_left_unsuspended = 0;
    Whostmgr::Accounts::Suspension::suspendacct(
        "username",                  "a reason for suspension",
        $prevent_reseller_unsuspend, $should_ftp_accts_be_left_unsuspended
    );

    Whostmgr::Accounts::Suspension::unsuspendacct("username");

=cut

use Cpanel::AcctUtils::Account    ();
use Cpanel::Debug                 ();
use Cpanel::LoadModule            ();
use Cpanel::PwCache::Clear        ();
use Whostmgr::ACLS                ();
use Whostmgr::Accounts::Suspended ();
use Whostmgr::AcctInfo::Owner     ();

use Try::Tiny;

=head1 FUNCTIONS

=head2 suspendacct

Suspends the cPanel account specifed

=head3 POSITIONAL ARGUMENTS

=over

=item 1. Username

Required, string

The username of the cPanel account to suspend.

=item 2. Reason

Optional, string

The reason for suspension.

=item 3. Prevent resellers from unsuspending

Optional, boolean

"Locks" the account so that only administrators can unsuspend the account.
Non-root resellers will not be able to unsuspend.

Defaults to C<0>.

=item 4. Leave FTP accounts enabled

Optional, boolean

Leave the FTP accounts unsuspended.

Defaults to C<0>.

=back

=cut

sub suspendacct {
    my $user       = shift;
    my $reason     = shift;
    my $disallowun = shift() ? 1 : 0;

    my $leave_ftp_enabled = shift ? 1 : 0;

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        my $error = '_suspendacct called for a user that does not exist.' . " ($user)";
        Cpanel::Debug::log_warn("$error");
        wantarray ? return ( 0, $error ) : return 0;
    }

    if ( 0 == scalar getpwnam $user ) {
        wantarray ? return ( 0, 'Root user may not be suspended.' ) : return 0;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Rlimit');
    Cpanel::Rlimit::set_rlimit_to_infinity();
    if (   !Whostmgr::ACLS::hasroot()
        && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        return wantarray ? ( 0, "Access Denied to Account $user" ) : 0;
    }

    Cpanel::LoadModule::load_perl_module('Capture::Tiny');
    require '/usr/local/cpanel/scripts/suspendacct';    ## no critic qw(Modules::RequireBarewordIncludes)
    my ( $output, @result );
    my $ok = 1;

    my @flags = (
        '--child-ok',                                   # Suspend even if it’s a child account.
    );
    push @flags, '--leave-ftp-accts-enabled' if $leave_ftp_enabled;

    try {
        ( $output, @result ) = Capture::Tiny::capture_merged(
            sub {
                scripts::suspendacct::run( @flags, '--', $user, $reason, $disallowun );
            }
        );
    }
    catch {
        $ok = 0;
        $output ||= "$_";
        Cpanel::Debug::log_warn($_);
    };

    Cpanel::PwCache::Clear::clear_global_cache();
    return wantarray ? ( $ok, $output ) : $ok;
}

=head2 unsuspendacct

Unsuspends the cPanel account specifed

=head3 POSITIONAL ARGUMENTS

=over

=item 1. Username

Required, string

The username of the cPanel account to suspend.

=item 2. Retain Service Proxies

Optional, boolean

Whether to retain service proxies that may exist on the account.

=back

=cut

sub unsuspendacct {
    my ( $user, $retain_service_proxies ) = @_;

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        my $error = '_unsuspendacct called for a user that does not exist.' . " ($user)";
        Cpanel::Debug::log_warn("$error");
        wantarray ? return ( 0, $error ) : return 0;
    }

    if ( !Whostmgr::ACLS::hasroot() && Whostmgr::Accounts::Suspended::is_locked($user) ) {
        my $error = "_unsuspendacct called for an account that can only be unsuspended by root ($user)";
        Cpanel::Debug::log_warn("$error");
        wantarray ? return ( 0, $error ) : return 0;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Rlimit');
    Cpanel::Rlimit::set_rlimit_to_infinity();
    if (   !Whostmgr::ACLS::hasroot()
        && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        wantarray ? return ( 0, "Access Denied to Account $user" ) : return 0;
    }

    Cpanel::LoadModule::load_perl_module('Capture::Tiny');
    require '/usr/local/cpanel/scripts/unsuspendacct';    ## no critic qw(Modules::RequireBarewordIncludes)
    my ( $output, @result );
    my $ok = 1;

    my @flags = (
        '--child-ok',
    );

    push @flags, '--retain-service-proxies' if $retain_service_proxies;

    try {
        ( $output, @result ) = Capture::Tiny::capture_merged(
            sub {
                scripts::unsuspendacct::run( @flags, '--', $user );
            }
        );
    }
    catch {
        $ok = 0;
        $output ||= "$_";
        Cpanel::Debug::log_warn($_);
    };

    Cpanel::PwCache::Clear::clear_global_cache();
    return wantarray ? ( $ok, $output ) : $ok;
}

1;
