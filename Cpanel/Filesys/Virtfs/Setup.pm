
# cpanel - Cpanel/Filesys/Virtfs/Setup.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Filesys::Virtfs::Setup;

use strict;
use warnings;

use Cpanel::IO                     ();
use Cpanel::PwCache::PwFile        ();
use Cpanel::StatCache              ();
use Cpanel::Sys::Hostname          ();
use Cpanel::Filesys::Virtfs        ();
use Cpanel::PwCache                ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::Debug                  ();
use Cpanel::LoginDefs              ();
use Cpanel::ConfigFiles            ();
use Cpanel::SimpleSync::CORE       ();
use Cpanel::FileUtils::Write       ();
use Cpanel::Filesys::Root          ();
use Cpanel::OS                     ();

our $VERSION = '2.0';

sub new {
    my ( $class, $uid ) = @_;

    my ( $user, $gid, $homedir ) = ( Cpanel::PwCache::getpwuid($uid) )[ 0, 3, 7 ];
    my ($mailgid) = ( Cpanel::PwCache::getpwnam('mail') )[3];

    die "'$uid' is not a valid user id, and may not run jailshell (cpanel users file missing).\n" unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);

    my %users_domains;
    if ( my $cpdata_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user) ) {
        %users_domains = map { $_ => 1 } ( @{ $cpdata_ref->{'DOMAINS'} }, $cpdata_ref->{'DOMAIN'} );
    }

    my $self_mtime            = ( stat('/usr/local/cpanel/bin/setupvirtfs') )[9];
    my $virtfs_setup_pm_mtime = ( stat('/usr/local/cpanel/Cpanel/Filesys/Virtfs/Setup.pm') )[9];

    $self_mtime = $virtfs_setup_pm_mtime if $self_mtime < $virtfs_setup_pm_mtime;

    return bless {
        'uid'           => $uid,
        'gid'           => $gid,
        'user'          => $user,
        'homedir'       => $homedir,
        'mailgid'       => $mailgid,
        'self_mtime'    => $self_mtime,
        'users_domains' => \%users_domains,
    }, $class;
}

sub setup {
    my ($self) = @_;

    my $uid     = $self->{'uid'};
    my $user    = $self->{'user'};
    my $homedir = $self->{'homedir'};

    if ( !$user ) {
        warn "$uid could not be resolved to a user";
        return 0;
    }

    my $hostname = Cpanel::Sys::Hostname::gethostname();

    my $umask = umask(0022);

    $self->_ensure_cpanel_os_cache_file();

    $self->_create_virtfs_userdir();

    my $vfs_hd = "$Cpanel::Filesys::Virtfs::virtfs_dir/$user";

    for my $dirname ( $Cpanel::ConfigFiles::VALIASES_DIR, $Cpanel::ConfigFiles::VDOMAINALIASES_DIR, $Cpanel::ConfigFiles::VFILTERS_DIR ) {
        my $dir = "$vfs_hd/$dirname";
        mkdir $dir, 0711 if ( !-d $dir );
        chown 0, $self->{'gid'}, $dir;
        chmod 0751, $dir;
    }

    chmod 0711, $vfs_hd;
    chown 0, $self->{'gid'}, $vfs_hd;
    my $users_domains = $self->{'users_domains'};

    foreach my $domain ( keys %{$users_domains} ) {
        $self->_updatefile("$Cpanel::ConfigFiles::VFILTERS_DIR/$domain");
        $self->_updatefile("$Cpanel::ConfigFiles::VALIASES_DIR/$domain");
        $self->_updatefile("$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/$domain");
    }

    my $mtab_file = $vfs_hd . '/etc/mtab';
    if ( !-e $mtab_file
        || ( stat(_) )[9] < ( time - 14400 ) ) {
        if ( open( my $mtab_fh, '>', $mtab_file ) ) {
            my $dev_root = Cpanel::Filesys::Root::get_dev_root();
            print {$mtab_fh} join( "\n", map { -d $_ ? ("${dev_root} $_ virtfs defaults 0 0") : () } ( Cpanel::Filesys::Virtfs::get_virtfs_mount_points(), $homedir ) ) . "\n" . "none /proc proc rw 0 0\n";
            close($mtab_fh);
        }
    }

    my %CHECK_FILES = (
        ( map { '/etc/' . $_ => undef } Cpanel::Filesys::Virtfs::get_virtfs_etc_files() ),
        ( map { $_           => undef } Cpanel::Filesys::Virtfs::get_exim_deps() ),
        ( map { $_           => undef } Cpanel::Filesys::Virtfs::get_ea4_deps() ),
        ( map { $_           => undef } Cpanel::Filesys::Virtfs::get_additional_files() ),
        ( '/etc/group'  => undef ),
        ( '/etc/passwd' => undef ),
    );

    # case 33625: confirmed ok here
    foreach my $base_dir ( '', $vfs_hd ) {
        foreach my $dir ( Cpanel::Filesys::Virtfs::get_virtfs_etc_dirs() ) {
            next if !-d $base_dir . $dir;
            if ( opendir my $dir_dh, $base_dir . $dir ) {
                while ( my $file = readdir $dir_dh ) {
                    next if $file =~ m/^[.]/;
                    $CHECK_FILES{ $dir . '/' . $file } = undef;
                }
            }
        }
    }

    foreach my $file ( sort keys %CHECK_FILES ) {
        $self->_updatefile($file);
    }

    $self->_updatefile( '/usr/local/cpanel/bin/checkvirtfs', 1 );

    $self->_update_linux_shadow();

    chmod( 0755, "$vfs_hd/checkvirtfs" );

    umask($umask);

    return 1;
}

sub _update_linux_shadow {
    my ($self) = @_;

    my $user       = $self->{'user'};
    my $self_mtime = $self->{'self_mtime'};

    my $update_shadow = !-e "$Cpanel::Filesys::Virtfs::virtfs_dir/$user/etc/shadow" ? 1              : 0;
    my $vshadow_mtime = !$update_shadow                                             ? ( stat(_) )[9] : 0;
    my $shadow_mtime  = ( stat('/etc/shadow') )[9];

    # update virtual shadow file for any of the following reasons:
    # 1. non-existent
    # 2. this script is newer
    # 3. system shadow file is newer

    # get most recent time; script or system shadow
    $shadow_mtime = $self_mtime if $self_mtime > $shadow_mtime;

    # update virtfs shadow file if it's older
    if ( $update_shadow || $shadow_mtime >= $vshadow_mtime ) {

        my $mytime    = int( time() / ( 60 * 60 * 24 ) );
        my $passwd_ok = 0;

        # force nopass on all users, except virtfs user
        my $shadow_txt = join(
            "\n",
            map { "$_:!!:" . $mytime . ":0:99999:7:::" } grep { $_ ne $user } ( _get_passwd_users( "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . '/etc/passwd' ) )
        ) . "\n";

        # now duplicate the virtfs user
        my $pw_ref;
        if ( ( $pw_ref = Cpanel::PwCache::PwFile::get_line_from_pwfile( '/etc/shadow', $user ) ) && ref $pw_ref eq 'ARRAY' && @{$pw_ref} ) {
            $passwd_ok = 1;

            # case 59760
            # ensure proper number of entries retrieved from get_line_from_pwfile()
            # otherwise incorrect number of ':' written; bad shadow format
            #                                 -- thanks Alex @ Bump Networks
            push @$pw_ref, ('') x ( 8 - $#$pw_ref );
            $shadow_txt .= join( ':', @{$pw_ref} ) . "\n";
        }
        else {
            Cpanel::Debug::log_warn("Failed to locate user $user in /etc/shadow");
        }
        Cpanel::FileUtils::Write::overwrite_no_exceptions( "$Cpanel::Filesys::Virtfs::virtfs_dir/$user/etc/shadow", $shadow_txt, 0400 );

    }

    return 1;
}

sub _get_passwd_users {
    my ($passwd_file) = @_;

    if ( open( my $passwd_fh, '<', $passwd_file ) ) {
        local $/;
        return map { ( split( /:/, $_ ) )[0] } split( /\n/, readline($passwd_fh) );
    }
    return ();
}

sub _updatefile {
    my ( $self, $file, $install_into_fs_root ) = @_;

    my $user = $self->{'user'};

    $install_into_fs_root ||= 0;
    my $file_target = $file;

    my @full_path = split( m/\//, $file );
    if ($install_into_fs_root) {
        $file_target = '/' . pop @full_path;
    }
    else {
        pop @full_path;
    }

    my $sync = 0;

    if ( !lstat($file) ) {
        if ( lstat( "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file_target ) ) {
            unlink "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file_target;
        }
    }
    else {
        my ( $src_gid, $src_mtime ) = ( stat(_) )[ 5, 9 ];
        if ( lstat( "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file_target ) ) {
            return if ( -l _ );
            my ( $dest_gid, $dest_mtime ) = ( stat(_) )[ 5, 9 ];

            # Compare mtimes
            if ( $src_mtime > $dest_mtime || $dest_gid != $src_gid ) {
                $sync = 1;
            }
        }
        else {
            if ( !$install_into_fs_root ) {
                my $mkdir;
                foreach my $part (@full_path) {
                    next if !$part;
                    $mkdir .= '/' . $part;
                    if ( !Cpanel::StatCache::cachedmtime( "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $mkdir ) ) {
                        mkdir "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $mkdir;
                    }
                }
            }
            $sync = 1;
        }
    }

    if ($sync) {
        if ( $file eq '/etc/passwd' || $file eq '/etc/group' ) {
            $self->_updatepasswdfile($file);
        }
        else {
            local $Cpanel::SimpleSync::CORE::sync_contents_check = 0;

            # Update file
            my ( $status, $message ) = Cpanel::SimpleSync::CORE::syncfile( $file, "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file_target );

            return $status;
        }
    }
    return 1;
}

sub _updatepasswdfile {
    my ( $self, $file ) = @_;

    my $user = $self->{'user'};

    my %required_users = ( $user => 1, 'nobody' => 1, 'cpaneleximfilter' => 1, 'mailman' => 1, 'mailtrap' => 1 );

    my $users_match       = '(?:' . join( '|', map { quotemeta($_) } keys %required_users ) . ')';
    my $users_match_regex = qr/\n($users_match:[^\r\n]+)/s;

    # we also need to check that the integer value is lower than UID_MIN
    my $uid_match_regex = qr/\n([^:]+:[^:]*:((?:[0-9]+)):[^\r\n]*)/s;

    if ( !-e $file ) {
        if ( -e "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file ) {
            unlink "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file;
        }
    }
    else {
        my $mode = ( stat(_) )[2];
        my $block;
        my %SEEN_USER;

        # Update file
        if ( open my $file_fh, '<', $file ) {
            if ( open my $dest_fh, '>', "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file ) {
                my $newpasswd = '';
                while ( !eof($file_fh) ) {
                    last if ( !defined( $block = Cpanel::IO::read_bytes_to_end_of_line( $file_fh, 65535 ) ) );
                    $block = "\n" . $block;    # need a \n for our regex to match -- we use /s since is much faster then /m
                    while ( $block =~ m/$uid_match_regex/g ) {
                        next if $2 >= Cpanel::LoginDefs::get_uid_min();
                        next if $SEEN_USER{ ( split( /:/, $1 ) )[0] }++;
                        $newpasswd .= $1 . "\n";
                    }
                    while ( $block =~ m/$users_match_regex/g ) {
                        next if $SEEN_USER{ ( split( /:/, $1 ) )[0] }++;
                        $newpasswd .= $1 . "\n";
                    }

                }
                print {$dest_fh} $newpasswd;
                close $dest_fh;
                my $perms = sprintf '%04o', $mode & 07777;
                chmod oct($perms), "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . $file;
            }
            else {
                Cpanel::Debug::log_warn("Unable to update $Cpanel::Filesys::Virtfs::virtfs_dir/$user$file");
                return;
            }
            close $file_fh;
        }
    }

    return 1;
}

sub _create_virtfs_userdir {
    my ($self) = @_;

    my $user = $self->{'user'};

    if ( !-d "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . '/etc' ) {
        if ( !-d $Cpanel::Filesys::Virtfs::virtfs_dir ) {
            if ( -e _ ) {
                unlink $Cpanel::Filesys::Virtfs::virtfs_dir;
            }
            mkdir $Cpanel::Filesys::Virtfs::virtfs_dir;
        }
        chown 0, 0, $Cpanel::Filesys::Virtfs::virtfs_dir;
        if ( !-d "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user ) {
            mkdir "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user, 0755;
        }
        mkdir "$Cpanel::Filesys::Virtfs::virtfs_dir/" . $user . '/etc', 0755;
    }

    if ( !-e "$Cpanel::Filesys::Virtfs::virtfs_dir/$user/jail_owner" ) {
        Cpanel::FileUtils::Write::overwrite_no_exceptions( "$Cpanel::Filesys::Virtfs::virtfs_dir/$user/jail_owner", $user, 0644 );
    }

    return 1;
}

# The Cpanel::OS cache file needs to exist so that jailshell users can query Cpanel::OS from within.
# Unjailed users can already read /etc/redhat-release or /etc/os-release as needed.
sub _ensure_cpanel_os_cache_file {
    Cpanel::OS::is_supported();    # any Cpanel::OS::* call guarantee that the cache file is set
    return;
}

1;
