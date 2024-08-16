package Whostmgr::Transfers::Session::Items::RearrangeAccount;

# cpanel - Whostmgr/Transfers/Session/Items/RearrangeAccount.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(Whostmgr::Transfers::Session::Item Whostmgr::Transfers::Session::Items::Schema::RearrangeAccount);

our $VERSION                     = '1.1';
our $TIMEOUT                     = ( 60 * 60 * 24 * 3 );    # 3 Days
our $MAX_RSYNC_READ_WAIT_TIMEOUT = ( 60 * 180 );            # 180 minutes
my $MAX_RSYNC_ATTEMPTS = 10;

use Cpanel::PwCache::Group ();
use Cpanel::ConfigFiles    ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';      # see POD for import specifics
use Cpanel::Kill::OpenFiles                    ();
use Cpanel::Autodie                            ();
use Cpanel::Chdir                              ();
use Cpanel::Config::CpUserGuard                ();
use Cpanel::Config::userdata                   ();
use Cpanel::Homedir::Modify                    ();
use Cpanel::Quota::Temp                        ();
use Cpanel::Signal                             ();
use Cpanel::StringFunc::Replace                ();
use Cpanel::Config::userdata::Cache            ();
use Cpanel::ConfigFiles::Apache::vhost         ();
use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::LoadModule                         ();
use Cpanel::AccessIds::ReducedPrivileges       ();
use Cpanel::Email::Perms::User                 ();
use Cpanel::FileProtect::Sync                  ();
use Cpanel::WebDisk::Utils                     ();
use Cpanel::HttpUtils::ApRestart::BgSafe       ();
use Cpanel::Mkdir                              ();
use Cpanel::DiskCheck                          ();
use Cpanel::Rsync                              ();
use Cpanel::Hooks                              ();
use Cpanel::Filesys::Home                      ();
use Cpanel::Exception                          ();
use Cpanel::Filesys::Info                      ();
use Cpanel::PwCache                            ();
use Cpanel::PwCache::Clear                     ();
use Cpanel::Config::LoadWwwAcctConf            ();
use Cpanel::Config::LoadCpConf                 ();
use Cpanel::NobodyFiles                        ();
use Cpanel::Sys::Kill                          ();
use Cpanel::SysAccounts                        ();
use Cpanel::TempFile                           ();
use Cpanel::Services::Enabled                  ();
use Cpanel::Server::FPM::Manager               ();
use Cpanel::ServerTasks                        ();
use Cpanel::NVData                             ();
use Cpanel::PHP::Config                        ();
use Cpanel::PHPFPM                             ();
use Cpanel::NSCD                               ();
use Cpanel::SSSD                               ();

use Cpanel::AcctUtils::Suspended ();
use Whostmgr::ACLS               ();
use Whostmgr::AcctInfo::Owner    ();
use Whostmgr::Accounts::Shell    ();
use File::Path                   ();

use Try::Tiny;

sub module_info {
    my ($self) = @_;

    return { 'item_name' => 'Account' };
}

sub restore {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(
              _restore_init
              _validate_rearrange
              check_restore_disk_space
              _run_pre_hooks
              _rearrange_account
              _run_post_hooks
            ),

            ( $self->can('post_restore') ? 'post_restore' : () )
        ]
    );
}

sub _restore_init {
    my ($self) = @_;

    $self->session_obj_init();

    $self->{'rearrange_user'} = $self->{'input'}->{'user'}   || $self->item();                                                 # self->item() FKA $self->{'input'}->{'user'};
    $self->{'new_mnt'}        = $self->{'input'}->{'target'} || Cpanel::Filesys::Home::get_homematch_with_most_free_space();
    $self->{'oldhome'}        = Cpanel::PwCache::gethomedir( $self->{'rearrange_user'} );
    $self->{'oldhome'} =~ s{/$}{}g;
    $self->{'newhome'} = "$self->{'new_mnt'}/$self->{'rearrange_user'}";
    return $self->validate_input( [qw(session_obj session_info output_obj rearrange_user oldhome new_mnt)] );
}

sub _validate_rearrange {
    my ($self)          = @_;
    my $homematch       = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf()->{'HOMEMATCH'};
    my $default_homedir = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf()->{'HOMEDIR'} || '/home';
    my $fs              = Cpanel::Filesys::Info::_all_filesystem_info();
    my $creator         = $self->session->creator();

    # Initialize ACLs for the life of this method.
    # This is for the checkowner() and hasroot() checks below.

    local %Whostmgr::ACLS::ACL;
    local $ENV{'REMOTE_USER'} = $creator;
    Whostmgr::ACLS::init_acls();

    if ( !Whostmgr::AcctInfo::Owner::checkowner( $creator, $self->{'rearrange_user'} ) ) {
        return ( 0, "Session creator ($creator) does not own ($self->{'rearrange_user'})" );
    }
    if ( !exists( $fs->{ $self->{'new_mnt'} } ) && !Whostmgr::ACLS::hasroot() ) {
        return ( 0, "Invalid mount point ($self->{'new_mnt'}) [Not in mount table]" );
    }
    if ( $self->{'new_mnt'} !~ /^\// || ( !-d $self->{'new_mnt'} ) ) {
        return ( 0, "Invalid mount point ($self->{'new_mnt'}) [Does it exist?]" );
    }
    if ( $homematch && $self->{'new_mnt'} !~ m{$homematch} && $self->{'new_mnt'} ne $default_homedir ) {
        return ( 0, "$self->{'new_mnt'} does not match &ldquo;$homematch&rdquo;" );
    }
    if ( $self->{'new_mnt'} =~ m{virtfs} ) {
        return ( 0, "$self->{'new_mnt'} is not a valid mount point for storing home directories" );
    }
    if ( -e $self->{'newhome'} && !-l $self->{'newhome'} ) {
        return ( 0, "New homedir already exists, all actions canceled (was this account already moved?)" );
    }
    return 1;
}

sub _run_pre_hooks {
    my ($self) = @_;
    my ( $pre_hook_result, $hook_msgs ) = Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Accounts::rearrangeacct',
            'stage'    => 'pre',
            'blocking' => 1,
        },
        {
            'current_home' => $self->{'oldhome'},
            'new_mnt'      => $self->{'new_mnt'},
            'user'         => $self->{'rearrange_user'},
        },
    );
    if ( !$pre_hook_result ) {
        my $hooks_msg = int @{$hook_msgs} ? join "\n", @{$hook_msgs} : '';
        return ( 0, "Hook denied moving account to $self->{'newhome'}: " . $hooks_msg );
    }

    return 1;

}

sub _run_post_hooks {
    my ($self) = @_;
    Cpanel::Hooks::hook(
        {
            'category' => 'Whostmgr',
            'event'    => 'Accounts::rearrangeacct',
            'stage'    => 'post',
        },
        {
            'current_home' => $self->{'oldhome'},
            'new_mnt'      => $self->{'new_mnt'},
            'user'         => $self->{'rearrange_user'},
        },
    );
    return 1;
}

sub is_transfer_item {
    return 0;
}

sub allow_non_root_enqueue {
    return 1;
}

sub check_restore_disk_space {
    my ($self) = @_;

    # Case 176937 - --force should override disk space checks
    if ( $self->{'session_obj'}->{'ignore_disk_space'} ) {
        return ( 1, 'ok' );
    }

    my $source = $self->{'oldhome'};
    my $target = $self->{'newhome'};
    return Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source( 'source' => $source, 'target' => $target );
}

sub _rearrange_account {
    my ($self) = @_;

    my $time          = time();
    my $user          = $self->{'rearrange_user'};
    my $oldhome       = $self->{'oldhome'};
    my $newhome       = $self->{'newhome'};
    my $temp_location = "$oldhome-rearrange-$time";

    my $chdir = Cpanel::Chdir->new('/');    # chdir to / to avoid EBUSY during rename

    print $self->_locale()->maketext( "The system will move “[_1]” to “[_2]”.", $oldhome, $newhome ) . "\n";
    Cpanel::Autodie::unlink_if_exists($newhome);
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $newhome, Cpanel::SysAccounts::homedir_perms() );
    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
    Cpanel::Autodie::chown( $uid, $gid, $newhome );
    print $self->_locale()->maketext( "The system will catalog files owned by “[_1]” in “[_2]”.", 'nobody', $oldhome );

    my $temp_obj = Cpanel::TempFile->new();
    my ( $temp_file, $temp_fh ) = $temp_obj->file();
    Cpanel::NobodyFiles::notate_nobodyfiles( $oldhome, $temp_fh );
    close($temp_fh);

    #Lift quotas while we’re transferring the account.
    {
        my $tempquota = Cpanel::Quota::Temp->new( user => $user );
        $tempquota->disable();

        my $copy_is_clean = $self->_copy_homedir($temp_location);

        Cpanel::Homedir::Modify::rename_homedir( $user, $oldhome, $temp_location );

        print $self->_locale()->maketext( "The system will symlink “[_1]” to “[_2]”.", $oldhome, $newhome ) . "\n";
        Cpanel::Autodie::symlink( $newhome, $oldhome );

        # In case anything has started back up we need to kill it
        # to ensure future processes are accessing the relocated
        # files
        Cpanel::Kill::OpenFiles::safekill_procs_access_files_under_dir($oldhome);
        Cpanel::Sys::Kill::kill_users_processes( $self->{'rearrange_user'} );

        $self->_restore_nobody_files($temp_file);

        $self->_remove_old_homedir($temp_location) if $copy_is_clean;

        $tempquota->restore();
    }

    $self->_add_old_homedir_to_homedirlinks( $user, $oldhome );

    # userdata update
    Cpanel::Config::userdata::update_homedir_data( { 'user' => $user, 'new_homedir' => $newhome, 'old_homedir' => $oldhome } );

    $self->_update_system_password_file_homedir();

    my @warnings = Cpanel::FileProtect::Sync::sync_user_homedir($user);
    foreach my $warning (@warnings) {
        $self->{output_obj}->warn($warning);
    }

    Cpanel::Email::Perms::User::ensure_all_perms($newhome);

    _update_user_nvdata( $user, $newhome, $oldhome );

    $self->_update_ftp_password_file_homedir();

    print $self->_locale()->maketext("The system will update the virtual host include files.") . "\n";
    system '/usr/local/cpanel/scripts/ensure_vhost_includes', '--user=' . $user, '--no-restart';

    $self->_rebuild_users_php_conf_file();

    $self->_rebuild_users_http_vhosts();

    $self->_rebuild_users_ftp_vhosts();

    print $self->_locale()->maketext("The system will update the [asis,Web Disk] configuration.") . "\n";
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub { Cpanel::WebDisk::Utils::_change_webdisk_username( $oldhome, "$newhome" ) },
        $user
    );

    if ( Cpanel::AcctUtils::Suspended::is_suspended($user) ) {
        print $self->_locale()->maketext("The system will update the [asis,Apache] configuration file: [asis,account_suspensions.conf]") . "\n";
        system( '/usr/local/cpanel/scripts/generate_account_suspension_include', '--update' );
    }

    if ( Cpanel::Services::Enabled::is_enabled('cpanel_php_fpm') ) {
        Cpanel::Server::FPM::Manager::regenerate_user($user);
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv cpanel_php_fpm" );
    }

    print $self->_locale()->maketext("The system will restart the web server.") . "\n";
    Cpanel::LoadModule::load_perl_module('Cpanel::Rlimit');
    Cpanel::Rlimit::set_rlimit_to_infinity();
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    $self->_update_jailshell();

    # Function below already checks whether nscd is running, no need to check
    # on this twice.
    Cpanel::NSCD::clear_cache();
    Cpanel::SSSD::clear_cache();

    print $self->_locale()->maketext("The rearrangement of home directories on the account is complete.") . "\n";
    return 1;
}

sub _update_user_nvdata {
    my ( $user, $new_homedir, $old_homedir ) = @_;

    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            my $defaultdir = Cpanel::NVData::_get("defaultdir");
            return unless defined $defaultdir;

            if ( $defaultdir =~ s/^\Q$old_homedir\E/$new_homedir/ ) {

                Cpanel::NVData::_set( "defaultdir", $new_homedir );
            }
        },
        $user
    );

    return;
}

sub _add_old_homedir_to_homedirlinks {
    my ( $self, $user, $old_homedir ) = @_;

    my $guard      = Cpanel::Config::CpUserGuard->new($user);
    my $cpuser_ref = $guard->{data};
    if ( !grep { $_ eq $old_homedir } @{ $cpuser_ref->{HOMEDIRLINKS} } ) {
        push @{ $cpuser_ref->{HOMEDIRLINKS} }, $old_homedir;
        $guard->save();
    }
    else {
        $guard->abort();
    }

    return 1;
}

sub _remove_old_homedir {
    my ( $self, $temp_location ) = @_;
    print $self->_locale()->maketext("The file transfer succeeded.") . "\n";
    print $self->_locale()->maketext( "The system will remove the old files from “[_1]”.", $temp_location ) . "\n";
    Cpanel::Autodie::chmod( 0, $temp_location );
    Cpanel::Autodie::chown( 0, 0, $temp_location );
    File::Path::rmtree($temp_location) or $self->{output_obj}->warn( $self->_locale()->maketext( "The system failed to remove “[_1]” because of the following error: [_2]", $temp_location, $! ) );
    return 1;
}

sub _rebuild_users_ftp_vhosts {
    my ($self) = @_;

    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};

    print $self->_locale()->maketext( "The system will update the file “[_1]”.", "proftpd.conf" ) . "\n";
    my $proftpconf = Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file();
    if ( -e $proftpconf ) {
        Cpanel::StringFunc::Replace::regsrep( $proftpconf, "<Anonymous " . quotemeta($oldhome) . "/public_ftp>", "        <Anonymous $newhome/public_ftp>" );
        print $self->_locale()->maketext("The system will restart the [asis,FTP] server.") . "\n";
        Cpanel::Signal::send_hup_proftpd();
    }
    return 1;
}

sub _rebuild_users_http_vhosts {
    my ($self)  = @_;
    my $user    = $self->{'rearrange_user'};
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};

    print $self->_locale()->maketext( "The system will update the file “[_1]”.", "httpd.conf" ) . "\n";
    my $cache   = Cpanel::Config::userdata::Cache::load_cache( $user, 1 );
    my @domains = ( $cache && ref $cache eq 'HASH' ) ? ( keys %$cache ) : ();
    if ( scalar @domains ) {
        my $conf_path = apache_paths_facade->file_conf();

        my @vhosts;
        foreach my $domain ( keys %$cache ) {
            push @vhosts, { 'new_domain' => $domain, 'current_domain' => $domain, 'owner' => $user };
        }
        my ( $ok, $msg ) = Cpanel::ConfigFiles::Apache::vhost::replace_vhosts( \@vhosts );
        $self->{output_obj}->warn($msg) if !$ok;

    }
    return 1;
}

sub _rebuild_users_php_conf_file {
    my ($self) = @_;
    my $user = $self->{'rearrange_user'};

    print $self->_locale()->maketext("The system will rebuild the [asis,PHP-FPM] configuration files (if applicable).") . "\n";
    my $cache   = Cpanel::Config::userdata::Cache::load_cache( $user, 1 );
    my @domains = ( $cache && ref $cache eq 'HASH' ) ? ( keys %$cache ) : ();

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( \@domains );
    Cpanel::PHPFPM::rebuild_files( $php_config_ref, 1, 1, 0 );

    return 1;
}

sub _update_jailshell {
    my ($self)  = @_;
    my $user    = $self->{'rearrange_user'};
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};
    my $cpconf  = Cpanel::Config::LoadCpConf::loadcpconf();

    return 1 if !$cpconf->{'jailapache'} || Whostmgr::Accounts::Shell::has_unrestricted_shell($user);

    print $self->_locale()->maketext("The system will update the [asis,Apache] jail configuration.") . "\n";
    system( 'umount', '-l', "/home/virtfs/$user$oldhome" );
    system( '/usr/local/cpanel/scripts/update_users_jail', $user );
    return 1;
}

sub _update_system_password_file_homedir {
    my ($self)  = @_;
    my $user    = $self->{'rearrange_user'};
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};

    my ( $name, $passwd, $uid, $gid, $quota, undef, $gcos, undef, $shell, undef ) = Cpanel::PwCache::getpwnam($user);

    print $self->_locale()->maketext( "The system will update the file “[_1]”.", "/etc/passwd" ) . "\n";
    Cpanel::StringFunc::Replace::regsrep( "/etc/passwd", '^' . quotemeta($user) . ':', "$user:x:$uid:$gid:$gcos:$newhome:$shell" );
    Cpanel::PwCache::Clear::clear_global_cache();
    return 1;
}

sub _update_ftp_password_file_homedir {
    my ($self)  = @_;
    my $user    = $self->{'rearrange_user'};
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};

    print $self->_locale()->maketext( "The system will update the file “[_1]”.", "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$user" ) . "\n";
    Cpanel::StringFunc::Replace::regsrep( "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$user", ':' . quotemeta($oldhome), ":$newhome", 1 );
    return 1;
}

sub _restore_nobody_files {
    my ( $self, $temp_file ) = @_;
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};
    my $user    = $self->{'rearrange_user'};

    print $self->_locale()->maketext( "The system will restore ownership for “[_1]” in “[_2]”.", 'nobody', $newhome );
    if ( open( my $nobody_fh, "<", $temp_file ) ) {
        my $err;
        try {
            local $SIG{'__WARN__'} = sub {
                $self->{output_obj}->warn(@_);
            };
            Cpanel::NobodyFiles::chown_nobodyfiles( $newhome, $nobody_fh, $user );
        }
        catch {
            $err = $_;
        };
        close $nobody_fh or do {
            $self->{output_obj}->warn( $self->_locale()->maketext( 'The system failed to close the file “[_1]” because of an error: [_2]', $temp_file, $! ) );
        };

        if ($err) {
            $self->{output_obj}->warn( Cpanel::Exception::get_string($err) );
        }
    }
    else {
        $self->{output_obj}->warn( $self->_locale()->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $temp_file, $! ) );
    }
    return;
}

sub _copy_homedir {
    my ( $self, $temp_location ) = @_;
    my $oldhome = $self->{'oldhome'};
    my $newhome = $self->{'newhome'};

    my $attempts      = 1;
    my $copy_is_clean = 1;
    print $self->_locale()->maketext( "The system will copy data from “[_1]” to “[_2]” using multiple “[_3]” executions.", $oldhome, $newhome, 'rsync' ) . "\n";

    while (1) {

        Cpanel::Sys::Kill::kill_users_processes( $self->{'rearrange_user'} );
        my $err;
        try {
            print "rsync: $attempts";
            $self->_rsync_as_user();
        }
        catch {
            $err = $_;
        };

        last if !$err && $attempts > 1;    # We always want to rsync twice in case something changes

        # during the first rsync as we will get a more narrow
        # window on the second rsync

        $self->{output_obj}->warn($err) if $err;

        if ( ++$attempts > $MAX_RSYNC_ATTEMPTS ) {
            $self->{output_obj}->warn( $self->_locale()->maketext( "The system failed to cleanly copy all of the files from “[_1]” to “[_2]” because of the following error: [_3].", $oldhome, $newhome, Cpanel::Exception::get_string($err) ) );
            $self->{output_obj}->warn( $self->_locale()->maketext( "The system will leave the original files in place at “[_1]” to allow for manual retrieval.", $temp_location ) );
            $copy_is_clean = 0;
            last;
        }
    }
    return $copy_is_clean;
}

sub _rsync_as_user {
    my ($self) = @_;

    my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user( $self->{'rearrange_user'} );
    my @ids               = ( ( Cpanel::PwCache::getpwnam( $self->{'rearrange_user'} ) )[ 2, 3 ], @supplemental_gids );

    return Cpanel::Rsync->run(
        'setuid' => \@ids,
        'args'   => [
            '--force',
            "$self->{'oldhome'}/" => "$self->{'newhome'}/",
        ]
    );
}
1;
