package Cpanel::Filesys::Virtfs;

# cpanel - Cpanel/Filesys/Virtfs.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cwd                        ();
use File::Basename             ();
use Cpanel::Kill::Single       ();
use Cpanel::PwCache::Build     ();
use Cpanel::PwCache            ();
use Cpanel::LoadFile           ();
use Cpanel::PsParser           ();
use Cpanel::Mount              ();
use Cpanel::PwCache            ();
use Cpanel::SafeFile::Simple   ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Filesys::Mounts    ();
use Cpanel::ConfigFiles        ();
use Cpanel::Debug              ();
use Cpanel::Config::Httpd::EA4 ();
use Cpanel::LoadModule         ();

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

our $virtfs_dir      = "/home/virtfs";
our $virtfs_lock_dir = "$virtfs_dir/_lock";
my %mount_unescapes = ( '040' => " ", '011' => "\t", "134" => "\\", "012" => "\n" );

######[ kill all jailshell logins of the given user, no mercy.

sub _lock_uid_virtfs {
    my ($uid) = @_;

    _ensure_lock_dir();

    return Cpanel::SafeFile::Simple->new("$virtfs_lock_dir/$uid");
}

sub _ensure_lock_dir {
    if ( !-e $virtfs_lock_dir ) {
        mkdir $virtfs_dir,      0755 if !-e $virtfs_dir;
        mkdir $virtfs_lock_dir, 0700 || return 0;
    }
}

# do a cleanup of all mounted partitions in /home/virtfs
sub cleanup_inactive_virtfs {
    _ensure_lock_dir();

    my $users_with_inactive_virtfs_mounts_ref = _fetch_users_with_inactive_virtfs_mounts();

    return 0 if !scalar keys %{$users_with_inactive_virtfs_mounts_ref};

    my %locks;

    foreach my $user ( keys %{$users_with_inactive_virtfs_mounts_ref} ) {
        my $uid = ( Cpanel::PwCache::getpwnam($user) )[2];

        next if !defined $uid;    #aka user deleted

        if ( my $lock_ref = _lock_uid_virtfs($uid) ) {
            $locks{$user} = $lock_ref;
        }
        else {
            Cpanel::Debug::log_warn("Could not lock on $virtfs_lock_dir/$uid for user: $user");
            delete $users_with_inactive_virtfs_mounts_ref->{$user};
        }
    }

    my $locked_users_with_inactive_virtfs_mounts_ref = $users_with_inactive_virtfs_mounts_ref;

    $users_with_inactive_virtfs_mounts_ref = _fetch_users_with_inactive_virtfs_mounts();

    my $cleaned = 0;

    foreach my $user ( keys %{$users_with_inactive_virtfs_mounts_ref} ) {
        next if !exists $locked_users_with_inactive_virtfs_mounts_ref->{$user};

        _umount_user_virtfs($user);

        if ( $locks{$user} ) {
            $locks{$user}->unlock();
            delete $locks{$user};
        }

        $cleaned++;
    }

    #
    # Clear any remaining locks
    #
    # This code is only hit when the user's virtfs
    # is cleaned up or unmounted between the point we fetch the list
    # of users _fetch_users_with_inactive_virtfs_mounts, obtain the locks
    # and then fetch the users again in _fetch_users_with_inactive_virtfs_mounts
    #
    foreach ( values %locks ) {
        $_->unlock();
    }

    return $cleaned;
}

# do a cleanup for all unmount directories for unknown users in /home/virtfs
sub cleanup_unmounts_virtfs_for_dead_users {
    my (%opts) = @_;

    my $clean_user            = $opts{'user'};
    my $user_has_virtfsmounts = {};

    for my $mount ( Cpanel::Filesys::Virtfs::get_virtfs_mounts() ) {
        $user_has_virtfsmounts->{ Cpanel::Filesys::Virtfs::get_username_from_virtfs_mount_string($mount) || '' } = 1;
    }
    delete $user_has_virtfsmounts->{''};

    my @candidates;

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeFind');

    Cpanel::SafeFind::find(
        {
            'follow'   => 0,
            'no_chdir' => 0,
            'wanted'   => sub {
                push @candidates, $_ if -d $File::Find::name && !-l $File::Find::name;
                $File::Find::prune = 1 if $File::Find::name ne $virtfs_dir;
                return;
            }
        },
        $virtfs_dir
    );

    @candidates = grep { $_ !~ qr{^[\.\_]} && !exists $user_has_virtfsmounts->{$_} } @candidates;

    foreach my $user (@candidates) {
        next if length $clean_user && $clean_user ne $user;

        # only want to remove virtfs for dead users
        next                                                  if ( defined( ( Cpanel::PwCache::getpwnam($user) )[0] ) );    # this is optional ( can be removed if needed )
        print "-- Cleaning virtfs for dead user '$user' --\n" if $opts{verbose};
        Cpanel::Filesys::Virtfs::remove_user_virtfs( $user, -1 );
    }

    return;
}

sub clean_user_virtfs {
    my ($user)  = @_;
    my $status  = 0;
    my $message = '';

    if ( !$user ) {
        $message .= "No user name given";
        return wantarray ? ( $status, $message ) : $status;
    }
    my $processes_arr = Cpanel::PsParser::fast_parse_ps( 'want_uid' => 0, 'exclude_kernel' => 1, 'exclude_self' => 1 );    # do not need to resolve uids since root is always resolved
    foreach my $process ( @{$processes_arr} ) {
        if ( $process->{'command'} =~ m/jailshell\s+\(\Q$user\E\)\s+\[(\d+)\]/ and $process->{'uid'} == 0 ) {              # make sure we've got the jailshell parent running as root to prevent mischief
            my $child_pid = $1;
            if ( $child_pid > 100 ) {                                                                                      # small layer of defense against killing init or something important just in case
                Cpanel::Kill::Single::safekill_single_pid( $child_pid, 1 );                                                # kill child
            }
            if ( $process->{'pid'} > 100 ) {
                Cpanel::Kill::Single::safekill_single_pid( $process->{'pid'}, 1 );                                         # kill parent
            }
        }
    }

    _umount_user_virtfs($user);

    my $mount_file_contents_ref = _get_mount_file_contents_ref();
    $status = 1;

    # Case 899
    # check each mount point to be sure none of them are mounted after we try umounting them.
    # if there are files still in any of these directories (other than . and ..) then there is a problem
    my @mounted = get_virtfs_mounts_of_user( $user, $mount_file_contents_ref );
    foreach my $dir ( sort { length $b <=> length $a } @mounted ) {
        $status = 0;
        $message .= "Virtfs directory \"$dir\" was not umounted properly, not removing\n";
        Cpanel::Debug::log_warn("Virtfs directory \"$dir\" was not umounted properly, not removing");
    }

    $message .= "Mounts on $virtfs_dir directories cleared." if $status;
    return wantarray ? ( $status, $message, $mount_file_contents_ref ) : $status;
}

my $locale;

sub _clean_virtfs_fn {
    my ( $params, $logwarn ) = @_;
    my $mount_cache                  = $params->{'mount_cache'};
    my $virtfs_home                  = $params->{'virtfs_home'};
    my $virtfs_mount_point           = $params->{'virtfs_mount_point'};
    my $virtfs_device_id             = $params->{'virtfs_device_id'};
    my $found_file_outside_device_sr = $params->{'found_file_outside_device_sr'};
    my $clean_virtfs                 = sub {
        my $filename = $_;
        my ( $file_device_id, $file_inode ) = ( stat($filename) )[ 0, 1 ];
        my $is_dir           = -d _ ? 1 : 0;
        my $file_mount_point = _get_path_mount_point( $filename, $is_dir, $mount_cache );

        # removed below after we chdir out
        return if $File::Find::name eq $virtfs_home;

        my $sys_file = $File::Find::name;
        my $is_link  = -l $File::Find::name ? 1 : 0;
        if ($is_link) {

            # need to clean the symlinks on a c7 box: /bin, /lib, /lib64, /sbin
            if ( !unlink($filename) ) {
                $logwarn->( $locale->maketext( 'The file “[_1]” could not be removed from the [asis,virtfs] device: [_2]', $File::Find::name, $! ) );
            }
            return;
        }
        $sys_file =~ s/^$virtfs_home//;
        my ( $sys_file_device_id, $sys_file_inode ) = ( stat($sys_file) )[ 0, 1 ];

        if ( defined $sys_file_device_id && $sys_file_device_id == $file_device_id && $sys_file_inode == $file_inode ) {

            # safe for a file but not for a directory
            $logwarn->( $locale->maketext( '“[_1]” points to the same inode as the system file “[_2]”.', $File::Find::name, $sys_file ) );
            return;
        }
        elsif ( $file_mount_point ne $virtfs_mount_point ) {
            $$found_file_outside_device_sr = 1;
            $logwarn->( $locale->maketext( '“[_1]” is located on a mount point, [_3], outside of the [asis,virtfs] device “[_2]” (whose mount point is [_4]).', $File::Find::name, $virtfs_dir, $file_mount_point, $virtfs_mount_point ) );
            return;
        }
        elsif ( $file_device_id != $virtfs_device_id ) {
            $$found_file_outside_device_sr = 1;
            $logwarn->( $locale->maketext( '“[_1]” is located on a device outside of the [asis,virtfs] device ([_2]).', $File::Find::name, $virtfs_dir ) );
            return;
        }

        if ( $is_dir && !$is_link ) {

            # need to be sure we are not running rmdir on a symlink
            if ( !rmdir($filename) ) {

                # If this fails grep [user] /proc/*/mounts will show what is holding on to the mount
                # Its usually named.  This is fixed in kernel 3.18+
                $logwarn->( $locale->maketext( 'The directory “[_1]” could not be removed from the [asis,virtfs] device: [_2]', $File::Find::name, $! ) );
            }
        }
        else {
            if ( !unlink($filename) ) {
                $logwarn->( $locale->maketext( 'The file “[_1]” could not be removed from the [asis,virtfs] device: [_2]', $File::Find::name, $! ) );
            }
        }
        return;
    };
    return $clean_virtfs;
}

sub remove_user_virtfs {
    my ( $user, $uid ) = @_;

    # allow us to remove the virtfs file after removing the user's system account
    #   uid is mainly used as a lock
    $uid ||= ( Cpanel::PwCache::getpwnam($user) )[2];

    if ( !$uid || $uid eq '-1' ) {
        Cpanel::Debug::log_warn("Could not lookup user $user") if !$uid;
        $uid = "nonexistent_$user";    # adequate for _lock_uid_virtfs in the case of a nonexistent user
    }

    my $lock = _lock_uid_virtfs($uid);
    if ( !$lock ) {
        return wantarray ? ( 0, "Could not lock virtfs for user $user" ) : 0;
    }

    # $mount_file_contents_ref has a list of the current mounted filesystems
    # after the clean
    my ( $clean_status, $clean_message, $mount_file_contents_ref ) = clean_user_virtfs($user);
    if ( !$clean_status ) {
        $lock->unlock();
        return wantarray ? ( $clean_status, $clean_message ) : $clean_status;
    }

    my $virtfs_device_id = ( stat($virtfs_dir) )[0];
    my $main_is_dir      = -d _ ? 1 : 0;
    if ( !defined $virtfs_device_id ) {
        $lock->unlock();
        return wantarray ? ( 0, "Failed to get the device id of $virtfs_dir" ) : 0;
    }

    my $mount_cache = _build_mounts_cache($mount_file_contents_ref);

    my $virtfs_mount_point = _get_path_mount_point( $virtfs_dir, $main_is_dir, $mount_cache );
    if ( !defined $virtfs_mount_point ) {
        $lock->unlock();
        return wantarray ? ( 0, "Failed to get the mount point of $virtfs_dir" ) : 0;
    }

    my $found_file_outside_device = 0;

    my $virtfs_home = "$virtfs_dir/$user";
    if ( !-e $virtfs_home ) {
        $lock->unlock();
        return wantarray ? ( 0, "Virtfs for $user does not exist or has already been removed." ) : 0;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    $locale ||= Cpanel::Locale->get_handle();

    my $first_error;
    my $logwarn = sub {
        my $msg = shift;

        # log all errors
        Cpanel::Debug::log_warn($msg);

        # only display the first one
        $first_error ||= $msg;
        return;
    };

    # MUST chdir for security reasons
    eval {
        my $clean_virtfs = _clean_virtfs_fn(
            {
                mount_cache                  => $mount_cache,
                virtfs_home                  => $virtfs_home,
                virtfs_mount_point           => $virtfs_mount_point,
                virtfs_device_id             => $virtfs_device_id,
                found_file_outside_device_sr => \$found_file_outside_device,
            },
            $logwarn
        );

        # only display the first error
        #   we try to remove as much valid files as possible
        #   if the error occurs during a killacct, the user will not be able to run it twice
        #   and we just want to free unused space

        Cpanel::LoadModule::load_perl_module('Cpanel::SafeFind');
        Cpanel::SafeFind::finddepth( { 'follow' => 0, 'no_chdir' => 0, 'wanted' => $clean_virtfs }, $virtfs_home );
        if ( defined $first_error ) {

            # debug information
            #Cpanel::Debug::log_debug( "lsof $virtfs_home:\n" . Cpanel::SafeRun::Simple::saferunallerrors( '/usr/sbin/lsof', '+D', $virtfs_home ) );
            #Cpanel::Debug::log_debug( "find $virtfs_home:\n" . Cpanel::SafeRun::Simple::saferunallerrors( '/usr/bin/find', $virtfs_home) );
            die $first_error;
        }

        my $virtfs_home_device_id = ( stat($virtfs_home) )[0];
        if ($virtfs_home_device_id) {

            # umount($virtfs_home)
            if ( !rmdir($virtfs_home) ) {
                my $error = $!;

                # debug information
                #Cpanel::Debug::log_debug( "lsof $virtfs_home:\n" . Cpanel::SafeRun::Simple::saferunallerrors( '/usr/sbin/lsof', '+D', $virtfs_home ) );
                die $locale->maketext( 'The virtfs home “[_1]” could not be removed from the [asis,virtfs] device: [_2]', $virtfs_home, $error );
            }
        }
        else {
            die $locale->maketext( '“[_1]” is located on a device outside of the [asis,virtfs] device ([_2]).', $virtfs_home, $virtfs_dir );
        }
    };
    my $err = $@;
    if ($err) {
        $lock->unlock();
        return wantarray ? ( 0, $err ) : 0;
    }
    $lock->unlock();
    return wantarray ? ( 1, "Virtfs for $user removed" ) : 1;
}

######[ returns list of all mounted virtfs for all users

sub get_virtfs_mounts {
    my ($mount_file_contents_ref) = @_;
    my $mounts_ref = _get_mounts_containing( ' ' . Cwd::abs_path($virtfs_dir) . '/', $mount_file_contents_ref );
    return keys %$mounts_ref;
}

sub get_virtfs_mounts_of_user {
    my ( $user, $mount_file_contents_ref ) = @_;
    my $mounts_ref = _get_mounts_containing( ' ' . Cwd::abs_path("$virtfs_dir/$user") . '/', $mount_file_contents_ref );
    return keys %$mounts_ref;
}

sub _get_all_mount_points {
    my ($mount_file_contents_ref) = @_;

    $mount_file_contents_ref ||= _get_mount_file_contents_ref();

    my $dataref             = $mount_file_contents_ref->{'contents_ref'};
    my $mountpoint_position = $mount_file_contents_ref->{'position_of_mountpoint_on_line_in_file'};

    # >2 because that is the first place a mount point can start
    # 01234
    # /x /home/virtfs
    # Mounts need to be unescaped
    # space (\040), tab (\011), newline (\012)  and  back-slash  (\134)
    my $mount_point;
    return {
        map {
            $mount_point = ( split( m{ }, $_ ) )[$mountpoint_position] // '';
            if ( $mount_point =~ tr{\(\\}{} ) {
                $mount_point =~ s/\\040\(deleted\)//;
                $mount_point =~ s/\\([0-9]{3})/$mount_unescapes{$1}/g;
            }
            $mount_point ? ( $mount_point => 1 ) : ();
        } grep { ord($_) != ord("\t") } split( m{\n}, $$dataref )    # ignore lines which start with a tab
    };
}

sub _get_mounts_containing {
    my ( $match, $mount_file_contents_ref ) = @_;

    $mount_file_contents_ref ||= _get_mount_file_contents_ref();

    my $dataref                         = $mount_file_contents_ref->{'contents_ref'};
    my $mountpoint_position             = $mount_file_contents_ref->{'position_of_mountpoint_on_line_in_file'};
    my $min_mountpoint_position_in_line = $mount_file_contents_ref->{'minimum_position_to_start_matching_at_on_line'};

    # >2 because that is the first place a mount point can start
    # 01234
    # /x /home/virtfs
    # Mounts need to be unescaped
    # space (\040), tab (\011), newline (\012)  and  back-slash  (\134)
    my $mount_point;
    return {
        map {
            if ( index( $_, $match ) > $min_mountpoint_position_in_line ) {
                $mount_point = ( split( m{ }, $_ ) )[$mountpoint_position];
                if ( $mount_point =~ tr{\(\\}{} ) {
                    $mount_point =~ s/\\040\(deleted\)//;
                    $mount_point =~ s/\\([0-9]{3})/$mount_unescapes{$1}/g;
                }
                ( $mount_point => 1 );
            }
            else {
                ();
            }
        } grep { ord($_) != ord("\t") } split( m{\n}, $$dataref )    # ignore lines which start with a tab
    };
}

# NOTE: An entry in /proc/self/mountstats can start with "no device". While this may not lead to malfunction at this time, our parsing is still technically wrong.
sub _get_mount_file_contents_ref {
    #
    # We prefer /proc/self/mountstats over /proc/mounts since it takes about
    # 50% of the time to read
    #
    my $mountfile                       = Cpanel::Filesys::Mounts::get_mount_stats_file_path();
    my $mount_file_is_really_mountstats = index( $mountfile, 'mountstats' ) > -1 ? 1 : 0;

    my $mountpoint_position             = $mount_file_is_really_mountstats ? 4 : 1;
    my $min_mountpoint_position_in_line = $mount_file_is_really_mountstats ? 8 : 2;
    #
    # mountstats looks like
    # device /dev/mapper/VolGroup00-LogVol00 mounted on /home/virtfs/gb0bv1id/var/cpanel/email_send_limits with fstype ext3
    # 0      1                               2       3  4
    # so we want 4
    #
    # mounts looks like
    # /dev/mapper/VolGroup00-LogVol00 /home/virtfs/gb0bv1id/usr/local/cpanel/3rdparty/mailman/logs ext3 rw,relatime,errors=continue,user_xattr,acl,barrier=1,data=ordered,jqfmt=vfsv0,usrjquota=quota.user 0 0
    # 0                               1
    # so we want 1
    #
    my $dataref = Cpanel::LoadFile::load_r($mountfile);

    return {
        'path'                                          => $mountfile,
        'position_of_mountpoint_on_line_in_file'        => $mountpoint_position,
        'minimum_position_to_start_matching_at_on_line' => $min_mountpoint_position_in_line,
        'contents_ref'                                  => $dataref,
    };
}

sub _build_mounts_cache {
    my ($mount_file_contents_ref) = @_;
    return _get_all_mount_points($mount_file_contents_ref);
}

######[ directories created to act as mount points for jailshell

sub get_virtfs_mount_points {
    my @FSS = qw(
      /libexec
      /opt
      /usr
      /usr/sbin
      /var
      /var/tmp
      /var/spool
      /etc/mail
      /etc/alternatives
      /tmp
      /dev
    );

    # TODO: Parse 'dir_base' from /etc/cpanel/ea4/paths.conf (EA-5130)
    if ( -f '/etc/cpanel/ea4/is_ea4' ) {
        push @FSS, '/etc/apache2' if -d '/etc/apache2';
        push @FSS, '/etc/scl'     if -d '/etc/scl';
    }

    # potential symlinks
    foreach my $point (qw{ /bin /lib /lib64 /sbin}) {
        if ( !-l $point ) {
            push @FSS, $point;
        }
        else {
            my $link_to = readlink($point);
            $link_to = '/' . $link_to if index( $link_to, '/' ) != 0;
            push @FSS, $link_to unless grep { $_ eq $link_to } @FSS;
        }
    }

    if ( !-l q{/bin} && -e '/var/cpanel/conf/jail/flags/mount_usr_bin_suid' ) {

        # /usr/bin might be enabled to make crontab work

        # We should not do this as crontab can be used to escape the jail
        # It would be much better if we distributed our own crontab
        # that knew about jailshell.

        push @FSS, '/usr/bin';
    }
    if ( -e '/var/cpanel/conf/jail/flags/mount_usr_local_cpanel_3rdparty_mailman_suid' ) {
        push @FSS, $Cpanel::ConfigFiles::MAILMAN_ROOT;
    }

    return ( sort { length $b <=> length $a } @FSS );
}

######[ files that get copied into $virtfs_dir/user/etc/ during mount

sub get_virtfs_etc_files {

    # sorted
    my @FILES = qw(
      aliases
      antivirus.exim
      backupmxhosts
      bashrc
      cron.allow
      cron.deny
      cpanel_exim_system_filter.local
      demodomains
      demouids
      demousers
      DIR_COLORS
      domainusers
      email_send_limits
      exim.conf
      exim.pl
      exim.pl.local
      eximmailtrap
      host.conf
      hosts
      inputrc
      ld.so.cache
      ld.so.conf
      localdomains
      localtime
      lynx.cfg
      lynx.lss
      man.config
      man_db.conf
      my.cnf
      nsswitch.conf
      outgoing_mail_suspended_users
      outgoing_mail_hold_users
      profile
      protocols
      remotedomains
      resolv.conf
      secondarymx
      senderverifybypasshosts
      services
      skipsmtpcheckhosts
      spammeripblocks
      sudoers
      termcap
      trueuserdomains
      trueuserowners
      trustedmailhosts
      userdomains
      vimrc
      odbcinst.ini
    );
    return (@FILES);
}

sub get_virtfs_etc_dirs {

    # sorted
    my @DIRS = qw(
      /etc/crypto-policies/back-ends
      /etc/my.cnf.d
      /etc/pam.d
      /etc/pki/tls/certs
      /etc/profile.d
      /etc/security
    );

    # Case CPANEL-40006: Ensure SSL peer certificates are accessible for Ubuntu users
    push @DIRS, qw(
      /etc/ssl/certs
      /usr/lib/ssl/certs
    );

    return (@DIRS);
}

######[ helper routines for scripts so possible changes to logic in future can be consolidated in one place

sub get_mountpoint_from_virtfs_mount_string {
    my ($mount) = @_;
    if ( $mount =~ /^(.*\/virtfs\/[^\/]+\/.*)/ ) {
        return $1;
    }
    return;
}

sub get_username_from_virtfs_mount_string {
    my ($mount) = @_;
    if ( $mount =~ /^.*\/virtfs\/([^\/]+)\/.*/ ) {
        return $1;
    }
    return;
}

sub get_jailshell_path {
    return '/usr/local/cpanel/bin/jailshell';
}

sub _additional_files_path { return '/var/cpanel/jailshell-additional-files'; }

sub get_additional_files {
    if ( -e _additional_files_path() ) {
        return split( /\n/, Cpanel::LoadFile::loadfile( _additional_files_path() ) );
    }
    return ();
}

sub get_exim_deps {
    if ( -e '/var/cpanel/exim.conf.deps' && ( stat(_) )[9] > ( stat('/etc/exim.conf') )[9] ) {
        return split( /\n/, Cpanel::LoadFile::loadfile('/var/cpanel/exim.conf.deps') );
    }
    else {
        my %FILE_DEPS;
        if ( open my $exim_fh, '<', '/etc/exim.conf' ) {
            while ( my $line = readline $exim_fh ) {
                if ( $line =~ m/\/etc\/(\w+)/ && $line !~ m/^\s*#/ ) {
                    my $file = $1;
                    next if exists $FILE_DEPS{$file} || !-e '/etc/' . $file || -d _;
                    $FILE_DEPS{ '/etc/' . $file } = 1;
                }
            }
            close $exim_fh;
            if ( open( my $exim_deps_cache_fh, '>', '/var/cpanel/exim.conf.deps' ) ) {
                print {$exim_deps_cache_fh} join( "\n", keys %FILE_DEPS );
                close($exim_deps_cache_fh);
            }
        }
        return keys %FILE_DEPS;
    }
}

sub get_ea4_deps {
    return () if !Cpanel::Config::Httpd::EA4::is_ea4();
    my $apache_conf_dir = apache_paths_facade->dir_conf();

    # php.conf.yaml is the old location (11.52), php.conf is the new location (11.54+)
    return ( '/etc/cpanel/ea4/paths.conf', "$apache_conf_dir/php.conf.yaml", '/etc/cpanel/ea4/php.conf', '/etc/cpanel/ea4/is_ea4' );
}

sub _fetch_users_with_inactive_virtfs_mounts {

    my %users_with_inactive_virtfs_mounts;

    for my $mount ( get_virtfs_mounts() ) {
        $users_with_inactive_virtfs_mounts{ get_username_from_virtfs_mount_string($mount) } = undef;
    }

    return {} if !scalar keys %users_with_inactive_virtfs_mounts;

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf();
    if ( $cpconf_ref->{'jailapache'} ) {
        Cpanel::PwCache::Build::init_passwdless_pwcache();
        my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

        # Delete users with jailshell or noshell since they
        # will always have their bind mounts active
        # when jailapache is enabled.  We never want to
        # clean them up since their vhost will break if we do
        delete @users_with_inactive_virtfs_mounts{
            map { $_->[0] } grep { $_->[8] && $_->[8] =~ m{(?:no|jail)shell} } @$pwcache_ref    #aka users with jail or noshell
        };
    }
    else {
        my %users_with_processes;
        my $processes_arr = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 1, 'skip_stat' => 1, 'skip_cmdline' => 1, 'exclude_self' => 1 );    # do not need to resolve uids since root is always resolved
        foreach my $proc ( @{$processes_arr} ) {
            $users_with_processes{ $proc->{'user'} } = $proc->{'uid'};
        }

        delete @users_with_inactive_virtfs_mounts{ keys %users_with_processes };
    }
    return \%users_with_inactive_virtfs_mounts;
}

sub _umount_user_virtfs {
    my ( $user, $mount_file_contents_ref ) = @_;
    my @mounted = get_virtfs_mounts_of_user( $user, $mount_file_contents_ref );

    foreach my $mp ( sort { length $b <=> length $a } @mounted ) {

        # success of these are ultimately detected just after this
        # try a umount with force then use a detach in case of failure
        my $can_unmount = Cpanel::Mount::umount( $mp, $Cpanel::Mount::MNT_FORCE ) == 0
          || Cpanel::Mount::umount( $mp, $Cpanel::Mount::MNT_DETACH ) == 0;
        if ( !$can_unmount ) {
            Cpanel::Debug::log_warn("Virtfs mountpoint failed to umount: $mp [ $! ]");
        }
    }

    return;
}

sub _get_path_mount_point {
    my ( $path, $is_dir, $mount_cache ) = @_;

    if ( !%$mount_cache ) {

        # Prevent implementor error from deleting things
        # that we should not delete.
        die "_get_path_mount_point requires a filled mount_cache";
    }

    my $abspath = Cwd::abs_path($path);

    if ( !defined $is_dir ) {
        $is_dir = -d $abspath ? 1 : 0;
    }

    if ( !$is_dir ) {
        $abspath = File::Basename::dirname($abspath);
    }
    while ( !_is_mount_point( $abspath, $mount_cache ) ) {
        $abspath = File::Basename::dirname($abspath);
    }

    return $abspath;
}

sub _is_mount_point {
    my ( $path, $mount_cache ) = @_;

    die "_is_mount_point requires the mount_cache" unless $mount_cache;

    return 0 unless defined $path;
    if ( !length $path || index( $path, '/' ) != 0 ) {

        # is_mount_point should always be called with an absolute path
        #   as we are going to cache the value
        $path = Cwd::abs_path($path);
    }
    return 0 unless defined $path && length $path;

    # remove trailing /
    $path =~ s{/+$}{};
    $path = q{/} if length($path) == 0;

    return $mount_cache->{$path} if defined $mount_cache && exists $mount_cache->{$path};

    my $res;
    $res = 1 if $path eq '/';

    if ( !-e $path || -l $path ) {
        $res = 0;
    }
    else {
        my ( $current_dir_device, $current_dir_inode ) = ( lstat(_) )[ 0, 1 ];
        my ( $parent_dir_device,  $parent_dir_inode )  = ( lstat("$path/..") )[ 0, 1 ];

        if ( $current_dir_device != $parent_dir_device ) {
            $res = 1;
        }
        elsif ( defined $current_dir_inode && $current_dir_inode == $parent_dir_inode ) {
            $res = 1;
        }
        else {
            $res = 0;
        }
    }

    $mount_cache->{$path} = $res if defined $mount_cache && !exists $mount_cache->{$path};

    return $res;
}

1;
