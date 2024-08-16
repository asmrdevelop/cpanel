package Whostmgr::Transfers::Systems::PostRestoreActions;

# cpanel - Whostmgr/Transfers/Systems/PostRestoreActions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# RR Audit: JNK

use Cpanel::AccessIds::ReducedPrivileges  ();
use Cpanel::ConfigFiles                   ();
use Cpanel::CachedDataStore               ();
use Cpanel::ContactInfo::Sync             ();
use Cpanel::Hooks                         ();
use Cpanel::NVData                        ();
use Cpanel::PwDiskCache::Utils            ();
use Cpanel::SafeRun::Object               ();
use Cpanel::Config::userdata::UpdateCache ();
use Cpanel::ServerTasks                   ();
use Cpanel::DIp::Update                   ();
use Cpanel::Config::userdata::Load        ();
use Cpanel::SSL::Setup                    ();
use Try::Tiny;
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::IPv6::ApiSupport        ();
use Whostmgr::Transfers::State      ();

use base qw(
  Whostmgr::Transfers::Systems
);

our $POSTRESTORE_SCRIPT = "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/postrestoreacct";

sub get_phase {
    return 100;
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This runs post-restoration actions and cleanups.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module updates system databases and name server IP address lists, restarts services, unblocks dynamic content, and runs custom post-restoration scripts.') ];
}

*restricted_restore = \&unrestricted_restore;

sub unrestricted_restore {
    my ($self) = @_;

    my $user = $self->newuser();

    $self->start_action( $self->_locale()->maketext('Updating Caches …') );

    # This is now being run at least 2 times per account restoration. The first time is in
    # the Account module during account recreation to avoid issues with double assigning a
    # dedicated IP address. The second time here to refresh the cache for additional
    # restored domains.
    Cpanel::Config::userdata::UpdateCache::update($user);

    # Update domainips must be done after the userdata cache is updated because it relies
    # on the userdata cache.
    my $errmsg = _run_updatedomainips();
    $self->warn($errmsg) if $errmsg;

    my $wwwacct_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    if ( defined $wwwacct_ref->{'ADDR6'} && $wwwacct_ref->{'ADDR6'} ) {
        $self->start_action( $self->_locale()->maketext('Enabling IPv6 for account …') );
        Cpanel::IPv6::ApiSupport::enable_ipv6_for_user( $user, q{SHARED} );
    }

    my $olduser = $self->olduser();    # case 113733: Used only externally

    my $domain = $self->{'_utils'}->main_domain();

    my $user_homedir = $self->homedir();

    $self->start_action('Updating Nameserver IP Address Report');
    try {
        Cpanel::ServerTasks::queue_task( ['NameServerIPTasks'], 'updatenameserveriplist' );
    }
    catch {
        $self->warn( $self->_locale()->maketext( 'The system failed to update the Nameserver IP Address Report because of an error: [_1].', $_ ) );
    };

    $self->start_action('Syncing contact information');
    try {
        Cpanel::ContactInfo::Sync::sync_contact_info( $self->newuser() );
        Cpanel::ContactInfo::Sync::sync_mail_users_contact_info( 'user' => $self->newuser() );
    }
    catch {
        $self->warn( $self->_locale()->maketext( 'The system failed to synchronize contact information for the user “[_1]” because of an error: [_2]', $self->newuser(), $_ ) );
    };

    Cpanel::ServerTasks::queue_task( ['MysqlTasks'], 'dbindex' );

    $self->_run_ssl_setup_for_user();
    $self->_update_account_enhancement_reseller_limits();
    $self->_update_nvdata_defaultdir();

    if ( Whostmgr::Transfers::State::is_transfer() ) {
        Cpanel::SafeRun::Object->new( 'program' => '/usr/local/cpanel/scripts/xfertool', 'args' => [ '--unblockdynamiccontent', $user ] );
    }

    if ( -x $POSTRESTORE_SCRIPT ) {
        $self->start_action('Running postrestore script');
        my $run = Cpanel::SafeRun::Object->new( 'program' => $POSTRESTORE_SCRIPT, 'args' => [ $user, $olduser, $domain, $user_homedir ] );    # case 113733: Used only externally
        my $err = $run->stderr();
        my $out = $run->stdout();
        $self->out($out)  if $out;
        $self->warn($err) if $err;
    }

    Cpanel::PwDiskCache::Utils::remove_entry_for_user( $self->newuser() );

    # No need to hold the cache between
    # users as this can tie up lots of memory
    Cpanel::CachedDataStore::clear_cache();

    # Ensure the extracted tarball dir is passed as an arg so that integrators can restore data not in the homedir, but in the tarball
    Cpanel::Hooks::hook(
        {
            'category' => 'PkgAcct',
            'event'    => 'Restore',
            'stage'    => 'post',
        },
        { 'extract_dir' => $self->{'_archive_manager'}->trusted_archive_contents_dir(), %{ $self->{'_utils'}{'flags'} } }
    );

    return 1;
}

=head1 _update_account_enhancement_reseller_limits

If the owner of the account being restored is a reseller
this method will call C<Whostmgr::AccountEnhancements::Reseller::recalculate_usage>
to update the Account Enhancement usage for that reseller.

=head2 ARGUMENTS

=over 1

=item $self

The current instance

=back

=head2 RETURNS

return 1 or 0  - for whether an update was successful.

=head2 EXCEPTIONS

=over

=item When C<Whostmgr::AccountEnhancements::Reseller::recalculate_usage> throws.

=back

=cut

sub _update_account_enhancement_reseller_limits {
    my ($self) = @_;

    require Whostmgr::Resellers::Check;
    if ( Whostmgr::Resellers::Check::is_reseller( $self->new_owner ) ) {
        require Whostmgr::AccountEnhancements::Reseller;
        $self->start_action('Updating Account Enhancement reseller limits for the account owner.');
        Whostmgr::AccountEnhancements::Reseller::recalculate_usage( $self->new_owner );
        return 1;
    }

    return 0;
}

sub _run_ssl_setup_for_user {
    my ($self) = @_;

    # validated in AccountRestoration.pm if restricted
    my $main_domain = $self->{'_utils'}->main_domain();
    my $newuser     = $self->newuser();
    if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $newuser, $main_domain ) ) {

        # If we restored a certificate in SSL.pm, we do not do SSL setup since we want to preserve
        # the certificate that was installed instead of installing the Best Available Certificate
        # which may generate a self signed certificate if the certificate we restored is faulty.
        #
        # In this case, we queue an AutoSSL run to bring everything up to date
        # in case the archive was older and needs its certificate updated.
        Cpanel::SSL::Setup::schedule_autossl_run_if_feature( 'user' => $newuser );
    }
    else {
        # case CPANEL-16146: We prevent Cpanel::SSL::Setup from running in
        # Account.pm in case we are restoring certificates.  Since we did not install
        # a certificate for the main domain we now call Cpanel::SSL::Setup to install
        # the best available certificate (that may mean generating a self signed one) and
        # queue an AutoSSL run to try to get something better.
        Cpanel::SSL::Setup::setup_new_domain( 'user' => $newuser, 'domain' => $main_domain );
    }

    return 1;
}

#for testing
sub _run_updatedomainips {
    return Cpanel::DIp::Update::update_dedicated_ips_and_dependencies_or_warn();
}

sub _update_nvdata_defaultdir {
    my ($self) = @_;
    my ( $old_ok, $oldhomedirs_ref ) = $self->{'_archive_manager'}->get_old_homedirs();

    return if !ref $oldhomedirs_ref;

    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            my $default_dir = Cpanel::NVData::_get("defaultdir");
            my $new_homedir = $self->{'_utils'}->homedir();

            return unless defined $default_dir;

            for my $homedir_path ( @{$oldhomedirs_ref} ) {
                $default_dir =~ s{^\Q$homedir_path\E}{$new_homedir};
            }

            Cpanel::NVData::_set( "defaultdir", $default_dir );
        },
        $self->newuser(),
    );

    return;
}

1;
