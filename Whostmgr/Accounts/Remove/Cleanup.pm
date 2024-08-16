package Whostmgr::Accounts::Remove::Cleanup;

# cpanel - Whostmgr/Accounts/Remove/Cleanup.pm     Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This is where any new account-removal logic should go.
#
# TODO: Move things from Temp::User::Cpanel and Whostmgr::Accounts::Remove
# into this module.
#
# This module has gotten a bit unwieldy. It would be nice to break it into
# separate, loadable modules, à la Cpanel::Pkgacct.
#----------------------------------------------------------------------

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Remove::Cleanup

=head1 SYNOPSIS

    Whostmgr::Accounts::Remove::Cleanup->new(%opts)->run();

=head1 DESCRIPTION

This is a modular system for account removals. It’s meant to help organize
the work and to make it consistent between test/temporary accounts and
“real” accounts.

See the module’s internal documentation for how to add a cleanup step.

=cut

use Try::Tiny;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';

use Cpanel::AccessIds::ReducedPrivileges  ();
use Cpanel::Autodie                       ();
use Cpanel::ConfigFiles                   ();
use Cpanel::Config::Session               ();
use Cpanel::MailTools                     ();
use Cpanel::Domains                       ();
use Cpanel::FileUtils::Match              ();
use Cpanel::LoadFile                      ();
use Cpanel::JSON                          ();
use Cpanel::PublicContact::Write          ();
use Cpanel::Exception                     ();
use Cpanel::PwCache                       ();
use Cpanel::Security::Authn::User         ();
use Cpanel::Security::Authn::User::Modify ();
use Cpanel::ServerTasks                   ();
use Cpanel::Email::Accounts::Paths        ();
use Cpanel::InterfaceLock::Remove         ();
use Cpanel::UserFiles                     ();
use Cpanel::SMTP::GetMX::Cache            ();
use Cpanel::Session::SinglePurge          ();
use Cpanel::WebCalls::Datastore::Write    ();
use Cpanel::PromiseUtils                  ();
use Cpanel::Team::Config                  ();
use Cpanel::FileUtils::Dir                ();
use Cpanel::Team::Constants               ();
use Whostmgr::Accounts::Email             ();
use Whostmgr::Packages::Info::Modular     ();

use Whostmgr::Accounts::Remove::Cleanup::TLS            ();
use Whostmgr::Accounts::Remove::Cleanup::WorkerNodes    ();
use Whostmgr::Accounts::Remove::Cleanup::HordeMigration ();
use Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL ();

use constant _ENOENT => 2;

#----------------------------------------------------------------------
# HOW TO ADD A CLEANUP STEP - OLD VERSION
#----------------------------------------------------------------------
#
# (NB: See below to determine if the newer way to do this suits you.)
#
# 1) Add a function to do your work. By convention, function names
#   “_look_like_this()”.
#
# 2) OPTIONAL: Create a “_SKIP*” function, which will indicate whether a
#   given step should be skipped. (The advantages to this rather than
#   just putting the test directly into your function from step 1 is that
#   the hooks won’t execute.)
#
# 3) Add an entry to the @_CLEANUP_TASKS array below. *NOTE* that the order
# here is specific! See what _tls does and then what _SKIP_dovecot_sni
# checks for!
#
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# HOW TO ADD A CLEANUP STEP - NEW (?) VERSION (actually the old version)
#----------------------------------------------------------------------
#
# You may have noticed some modules below this namespace.
# Do not be fooled into thinking they are related in any manner to the "new"
# version mentioned below.
# These are basically just broken out for testing's sake without regard
# for the new system.
#
# Here you still need to add a "_look_like_a_fool()" subroutine
# as previously since there's no automatic mapping.
# Just alias it if you have to after 'use'-ing the module.
#
# Example subroutine for those following along: _horde_migration_cleanup
#
#----------------------------------------------------------------------

#----------------------------------------------------------------------
# HOW TO ADD A CLEANUP STEP - ACUTALLY NEW VERSION
#----------------------------------------------------------------------
#
# If you’re adding a new account configuration that’s stored in the cpuser
# file, then you don’t have to change this module at all. See
# Whostmgr::Packages::Info::Modular for more details.
#
# For an *example*, see Whostmgr/Packages/Info/Modular/Cloud.pm
#
# This of course, assumes you have defined this account component entirely
# via this system. This may not be the best solution for what you need, as
# you many need to remove data *not* created at account creation time
# or that is entirely unrelated to package state.
#
#----------------------------------------------------------------------

# referenced from tests;
# expanded at runtime (below) for modular account components
#
our @_CLEANUP_TASKS = (
    [ '_public_contact',                      'Removing public contact information …' ],
    [ '_authn_db',                            'Removing external authentication links …' ],
    [ '_autossl',                             'Running AutoSSL account deletion logic …' ],
    [ '_tls',                                 'Removing installed TLS resources …' ],
    [ '_dovecot_sni',                         'Enqueuing rebuild of Dovecot’s SNI configuration …' ],
    [ '_excluded_domains',                    'Removing AutoSSL exclusions …' ],
    [ '_outgoing_email_suspend_and_hold',     'Removing outgoing email suspensions and holds …' ],
    [ '_dkim',                                'Removing DKIM keys …' ],
    [ '_remove_getmx_cache',                  'Removing MX cache …' ],
    [ '_sessions',                            'Removing sessions for cPanel services …' ],
    [ '_clean_mysql_roundcube_userdata',      'Removing RoundCube data from MySQL …' ],
    [ '_remove_team_account',                 'Removing Team Account …' ],
    [ '_interface_locks',                     'Removing any unneeded pending interface locks …' ],
    [ '_mailman_lists_and_archives',          'Removing GNU Mailman mailing lists and archives …' ],
    [ '_apache_domlogs',                      'Removing web logs …' ],
    [ '_remove_mail_service_configs',         'Removing mail and service configurations …' ],
    [ '_remove_port_authority_ports',         'Removing any port authority assignments …' ],
    [ '_stop_cpuser_service_manager',         'Stopping any cPUser Service Manager based services …' ],
    [ '_worker_nodes',                        'Removing child accounts …' ],
    [ '_linked_node_cache_entry',             'Removing linked-node account cache entry …' ],
    [ '_webcalls',                            'Removing web hooks …' ],
    [ '_account_enhancement_reseller_limits', 'Reclaiming any Account Enhancement usages for resellers …' ],
    [ '_horde_migration_cleanup',             'Removing horde migration data from cpanelroundcube dir …' ],
);

sub new {
    my ( $class, %opts ) = @_;

    my %clean_opts = map { ( "_$_" => $opts{$_} ) } qw(
      username
      todo_before
      on_error
      todo_after
      cpuser_data
    );

    return bless \%clean_opts, $class;
}

sub run {
    my ($self) = @_;

    my @cleanup_tasks = @_CLEANUP_TASKS;

    for my $component ( Whostmgr::Packages::Info::Modular::get_enabled_components() ) {
        my $label = $component->removeacct_label();
        next if !$label;

        push @cleanup_tasks, [
            sub { $component->do_removeacct( $self->{'_username'} ) },
            $label,
        ];
    }

    for my $task_ar (@cleanup_tasks) {
        my ( $task, $announcement ) = @$task_ar;

        # $task can be either a coderef or a string that names the
        # function in this module to run.
        #
        my $fn_name = ( 'CODE' ne ref $task ) && $task;

        if ($fn_name) {
            my $skip_fn_name = "_SKIP$fn_name";
            if ( $self->can($skip_fn_name) && $self->$skip_fn_name() ) {
                next;
            }
        }

        if ( $self->{'_todo_before'} ) {
            $self->{'_todo_before'}->($announcement);
        }

        try {
            $fn_name ? $self->$fn_name() : $task->();

            if ( $self->{'_todo_after'} ) {
                $self->{'_todo_after'}->();
            }
        }
        catch {
            my $error = Cpanel::Exception::get_string($_);
            if ( $self->{'_on_error'} ) {
                $self->{'_on_error'}->($error);
            }
            else {
                warn $error;
            }
        };
    }

    return;
}

sub _account_enhancement_reseller_limits ($self) {
    require Whostmgr::AccountEnhancements;
    require Whostmgr::AccountEnhancements::Reseller;
    foreach my $key ( grep { /ACCOUNT-ENHANCEMENT/ } keys %{ $self->{'_cpuser_data'} } ) {
        my $name        = $key =~ s/ACCOUNT-ENHANCEMENT-//r;
        my $enhancement = eval { Whostmgr::AccountEnhancements::find($name) };
        next if !eval { $enhancement->isa('Whostmgr::AccountEnhancements::AccountEnhancement') };
        Whostmgr::AccountEnhancements::Reseller::update_usage( $self->{'_cpuser_data'}{'OWNER'}, $enhancement->get_id(), -1 );
    }

    return;
}

sub _worker_nodes ($self) {
    Whostmgr::Accounts::Remove::Cleanup::WorkerNodes::clean_up( $self->{'_cpuser_data'} );

    return;
}

sub _linked_node_cache_entry ($self) {
    require Cpanel::LinkedNode::AccountCache;
    require Cpanel::PromiseUtils;

    my $cache_p = Cpanel::LinkedNode::AccountCache->new_p();

    my $username = $self->{'_username'};

    Cpanel::PromiseUtils::wait_anyevent(
        $cache_p->then(
            sub ($cache) {
                my $needs_save = $cache->remove_cpuser($username);
                return $needs_save && $cache->save_p();
            }
        )
    )->get();

    return;
}

sub _webcalls ($self) {
    my $writer = Cpanel::PromiseUtils::wait_anyevent( Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30 ) )->get();

    $writer->purge_user( $self->{'_username'} );

    return;
}

#tested directly
sub _remove_mail_service_configs {
    my ($self) = @_;

    my $user        = $self->{'_username'};
    my $cpuser_data = $self->{'_cpuser_data'};
    my $domain      = $cpuser_data->{'DOMAIN'};
    my @PDS         = @{ $cpuser_data->{'DOMAINS'} || [] };

    my @CONFIG_DIRS = (
        $Cpanel::ConfigFiles::VFILTERS_DIR,
        $Cpanel::ConfigFiles::VALIASES_DIR,
        $Cpanel::ConfigFiles::VDOMAINALIASES_DIR,
    );

    for my $domain_name ( @PDS, $domain ) {
        my @paths = map { "$_/$domain_name" } @CONFIG_DIRS;
        _unlink_or_warn_if_exists($_) for @paths;

        Cpanel::MailTools::remove_vmail_files($domain_name);
    }

    Whostmgr::Accounts::Email::update_outgoing_mail_suspended_users_db(
        user => $user, suspended => 0,
    );
    Whostmgr::Accounts::Email::update_outgoing_mail_hold_users_db(
        user => $user, hold => 0,
    );

    # ManualMX protects against invalid domain names but cpuser data has no such protection.
    # Filter out the invalid domains from cpuser data before trying to remove manual MX entries.
    require Cpanel::Exim::ManualMX;
    require Cpanel::Validate::Domain::Tiny;
    my $possible_manual_mx = [ grep { Cpanel::Validate::Domain::Tiny::validdomainname( $_, 1 ) } ( @PDS, $domain ) ];
    Cpanel::Exim::ManualMX::unset_manual_mx_redirects($possible_manual_mx);

    return;
}

sub _remove_port_authority_ports {
    my ($self) = @_;

    no warnings "once";
    local $ENV{"scripts::cpuser_port_authority::bail_die"} = 1;

    if ( !$INC{"/usr/local/cpanel/scripts/cpuser_port_authority"} ) {
        require "/usr/local/cpanel/scripts/cpuser_port_authority";    ## no critic qw(Modules::RequireBarewordIncludes)
    }

    local $SIG{__WARN__} = sub { };                                   # to work around CPANEL-23274 on firewalld systems
    scripts::cpuser_port_authority->user( 'remove', $self->{'_username'} );

    return 1;
}

sub _stop_cpuser_service_manager {    # this will be improved via ZC-4243
    my ($self) = @_;

    my $curhome = Cpanel::PwCache::gethomedir( $self->{_username} );
    if ( -s "$curhome/.ubic.cfg" ) {
        require Cpanel::AccessIds;
        try {
            Cpanel::AccessIds::do_as_user_with_exception(
                $self->{_username},
                sub {
                    local $ENV{HOME} = $curhome;

                    # would be cool if Cpanel::FindBin (or whatever) did this for us: CPANEL-22345 and CPANEL-23118
                    my $real_perl  = readlink("/usr/local/cpanel/3rdparty/bin/perl");
                    my $cp_bin_dir = $real_perl;
                    $cp_bin_dir =~ s{/perl$}{};
                    local $ENV{PATH} = "$cp_bin_dir:$ENV{PATH}";    # not only does this allow it to find our ubic-admin, it allows its env-shebang to pick up our perl

                    system( "ubic", "stop", "--force" );
                }
            );
        }
        catch {
            warn $_;
        };
    }

    return;
}

#tested directly
sub _apache_domlogs {
    my ($self) = @_;

    my $user        = $self->{'_username'};
    my $cpuser_data = $self->{'_cpuser_data'};

    my $domain           = $cpuser_data->{'DOMAIN'};
    my @PDS              = @{ $cpuser_data->{'DOMAINS'}     || [] };
    my @_raw_deaddomains = @{ $cpuser_data->{'DEADDOMAINS'} || [] };
    my @true_deaddomains = Cpanel::Domains::get_true_user_deaddomains( \@_raw_deaddomains );

    ## case 9010: remove domlogs for deaddomains, as well
    my @paths = (
        "${user}-imapbytes_log.offset",
        "${user}-imapbytes_log",
        "${user}-popbytes_log.offset",
        "${user}-popbytes_log",
        $user,
    );

    my $dir = apache_paths_facade->dir_domlogs();

    my @domains = ( $domain, "www.$domain", @PDS, @true_deaddomains );
    for (@domains) {
        next if index( $_, '.' ) == 0;

        push @paths, (
            $_,
            "${_}.bkup",
            "${_}.bkup2",
            "${_}.offset",
            "${_}.bkup.offset",
            "${_}-ssl_log",
            "${_}-ssl_log.bkup",
            "${_}-ssl_log.bkup2",
            "${_}-ssl_log.offset",
            "${_}-ssl_log.bkup.offset",
            "${_}-bytes_log",
            "${_}-bytes_log.offset",
            "ftp.${_}-ftp_log",
            "${_}-smtpbytes_log",
            "${_}-smtpbytes_log.offset",
        );
    }

    if ( -e "$dir/${user}" ) {
        require File::Path;
        File::Path::remove_tree("$dir/$user");
    }

    _unlink_or_warn_if_exists("$dir/$_") for @paths;

    return;
}

#tested directly
sub _mailman_lists_and_archives {
    my ($self) = @_;

    my $domain = $self->{'_cpuser_data'}{'DOMAIN'};
    my @PDS    = @{ $self->{'_cpuser_data'}{'DOMAINS'} || [] };

    # This used to loop through each entry in the mailman directories for
    # each domain and parked domain on the account. We now go once through
    # each entry.
    my %trailers      = map { $_ => 1 } ( $domain, @PDS );
    my %mbox_trailers = map { $_ => 1, "$_.mbox" => 1 } ( $domain, @PDS );

    my $dns_list = join( '|', map { quotemeta($_) } $domain, @PDS );

    my @list_sources = (
        scalar Cpanel::FileUtils::Match::get_files_matching_trailers( "$Cpanel::ConfigFiles::MAILMAN_ROOT/lists",            '_', \%trailers ),
        scalar Cpanel::FileUtils::Match::get_files_matching_trailers( "$Cpanel::ConfigFiles::MAILMAN_ROOT/suspended.lists",  '_', \%trailers ),
        scalar Cpanel::FileUtils::Match::get_files_matching_trailers( "$Cpanel::ConfigFiles::MAILMAN_ROOT/archives/private", '_', \%mbox_trailers ),
        scalar Cpanel::FileUtils::Match::get_files_matching_trailers( "$Cpanel::ConfigFiles::MAILMAN_ROOT/archives/public",  '_', \%trailers ),
        scalar Cpanel::FileUtils::Match::get_matching_files( "$Cpanel::ConfigFiles::MAILMAN_ROOT/locks", "_(?:$dns_list)\." )
    );

    # Example lock file format
    # gapi_gapersonalinjury.com.archiver.lock
    # gapi_gapersonalinjury.com.lock
    # gapi_gapersonalinjury.com.archiver.lock.blackhole.dev.cpanel.net.37927.1
    # gapi_gapersonalinjury.com.lock.blackhole.dev.cpanel.net.37927.0

    my @unlink = map { @$_ } @list_sources;

    if (@unlink) {
        require File::Path;
        my $privs = Cpanel::AccessIds::ReducedPrivileges->new('mailman');
        File::Path::rmtree( \@unlink );
    }

    return;
}

sub _interface_locks {
    my ($self) = @_;

    Cpanel::InterfaceLock::Remove::remove_user_locks( { user => $self->{'_username'} } );

    return;
}

sub _sessions {
    my ($self) = @_;

    Cpanel::Session::SinglePurge::purge_user( $self->{'_username'}, 'killacct' );

    return;
}

sub _remove_getmx_cache {
    my ($self) = @_;

    my $user_cfg = $self->{'_cpuser_data'};
    my @domains  = (
        $user_cfg->{'DOMAIN'},
        @{ $user_cfg->{'DOMAINS'} || [] },
    );

    Cpanel::SMTP::GetMX::Cache::delete_cache_for_domains( \@domains );

    return;
}

sub _dkim {
    my ($self) = @_;

    my $user_cfg = $self->{'_cpuser_data'};
    my @domains  = (
        $user_cfg->{'DOMAIN'},
        @{ $user_cfg->{'DOMAINS'} || [] },
    );

    my @files = map { Cpanel::UserFiles::dkim_key_files_for_domain($_) } @domains;

    _unlink_or_warn_if_exists($_) for @files;

    return;
}

sub _authn_db {
    my ($self) = @_;

    if ( -d Cpanel::Security::Authn::User::get_user_db_directory( $self->{'_username'} ) ) {
        Cpanel::Security::Authn::User::Modify::remove_all_authn_links_for_system_user_and_subusers( $self->{'_username'} );
    }

    return;
}

sub _autossl {
    my ($self) = @_;

    # This is just a wrapper around
    # Cpanel::SSL::Auto::Purge::purge_user('theuser');
    Cpanel::ServerTasks::schedule_task( ['SSLCleanupTasks'], 5, "autossl_purge_user $self->{_username}" );
    return;
}

sub _excluded_domains {

    # Now handled in _autossl
    return;
}

sub _tls {
    my ($self) = @_;

    my $cpuser_hr = $self->{'_cpuser_data'};

    # Just in case, for whatever reason, the “username” given to this
    # class’s constructor isn’t the same as the cpuser data’s USER.
    local $cpuser_hr->{'USER'} = $self->{'_username'};

    # NB: Other parts of this restore depend on this being a boolean
    # that indicates whether any TLS removals took place.
    $self->{'_removed_dtls'} = Whostmgr::Accounts::Remove::Cleanup::TLS::clean_up($cpuser_hr);

    return;
}

sub _SKIP_dovecot_sni {
    my ($self) = @_;

    die "Need “_removed_dtls” set!" if !defined $self->{'_removed_dtls'};

    return !$self->{'_removed_dtls'};
}

sub _dovecot_sni {
    my ($self) = @_;

    Cpanel::ServerTasks::schedule_task(
        ['DovecotTasks'], 120,
        'build_mail_sni_dovecot_conf',
        'reloaddovecot',
    );

    return;
}

sub _public_contact {
    my ($self) = @_;

    Cpanel::PublicContact::Write->unset( $self->{'_username'} );

    return;
}

sub _outgoing_email_suspend_and_hold {

    my ($self) = @_;

    my $limits_dir = "$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_BASE_PATH/" . $self->{'_username'};

    Cpanel::Autodie::exists($limits_dir);

    if ( -d _ ) {

        my $limits_file = "$limits_dir/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME";

        my $limits_json = Cpanel::LoadFile::load_if_exists($limits_file);

        if ( length $limits_json ) {

            my $email_limits_ref;

            try {
                $email_limits_ref = Cpanel::JSON::Load($limits_json);
            }
            catch {
                warn "The system encountered an error while reading the “$limits_file” file: " . Cpanel::Exception::get_string($_);
            };

            if ($email_limits_ref) {
                foreach my $domain ( keys %$email_limits_ref ) {
                    foreach my $account ( keys %{ $email_limits_ref->{$domain}{'suspended'} } ) {
                        Whostmgr::Accounts::Email::update_outgoing_mail_suspended_users_db( user => "$account\@$domain", suspended => 0 );
                    }
                    foreach my $account ( keys %{ $email_limits_ref->{$domain}{'hold'} } ) {
                        Whostmgr::Accounts::Email::update_outgoing_mail_hold_users_db( user => "$account\@$domain", hold => 0 );
                    }
                }
            }

        }

        Cpanel::Autodie::unlink_if_exists($limits_file);
        require File::Path;
        File::Path::remove_tree($limits_dir);
    }

    return;
}

#----------------------------------------------------------------------

# This function is called 100000x time on account removal
# so small optimizations matter
sub _unlink_or_warn_if_exists {
    local $!;
    return unlink $_[0] || do {
        warn "unlink($_[0]): $!" if $! != _ENOENT();
    };
}

# Remove Team Account if exists. In case of any Team::Config::remove_team
# exceptions, do not fail the whole Account Termination process, delete
# the team-user session files and team config file.
sub _remove_team_account {
    my ($self)      = @_;
    my $user        = $self->{'_username'};
    my $cpuser_data = $self->{'_cpuser_data'};
    my $domain      = $cpuser_data->{'DOMAIN'};
    eval { Cpanel::Team::Config::remove_team($user); } or do {
        warn "Cpanel::Team::Config::remove_team throws exceptions: $@";

        # TODO: DUCK-7709
        my $session_cache_dir  = "$Cpanel::Config::Session::SESSION_DIR/cache";
        my @team_user_sessions = map { /(^[a-z0-9]+?\@\Q$domain\E):/ } ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($session_cache_dir) } );
        foreach my $active_session (@team_user_sessions) {
            Cpanel::Session::SinglePurge::purge_user( $active_session, 'Terminating team_owner account' );
        }

        _unlink_or_warn_if_exists("$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$user");
    };
    return;
}

*_SKIP_horde_migration_cleanup        = \&Whostmgr::Accounts::Remove::Cleanup::HordeMigration::maybe_construct_horde_dir2kill_for_cleanup_module_or_just_return_early;
*_horde_migration_cleanup             = \&Whostmgr::Accounts::Remove::Cleanup::HordeMigration::clean_up;
*_SKIP_clean_mysql_roundcube_userdata = \&Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL::skip_this;
*_clean_mysql_roundcube_userdata      = \&Whostmgr::Accounts::Remove::Cleanup::RoundCubeMySQL::clean_up;

1;
