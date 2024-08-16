package Cpanel::Config::Backup;

# cpanel - Cpanel/Config/Backup.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Config::LoadConfig           ();
use Cpanel::Debug                        ();
use Cpanel::JSON::FailOK                 ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::LoadModule                   ();

our $conf_file   = '/etc/cpbackup.conf';
our $shadow_file = '/etc/cpbackup.conf.shadow';
our $public_conf = '/etc/cpbackup.public.conf';

our $conf_cache;
my $conf_file_mtime = 0;
my $has_serializer;

sub import {
    my $this = shift;
    if ( !exists $INC{'Cpanel/JSON.pm'} ) {
        Cpanel::JSON::FailOK::LoadJSONModule();
    }
    if ( exists $INC{'Cpanel/JSON.pm'} ) {
        $has_serializer = 1;
    }
    return Exporter::import( $this, @_ );
}

sub load {

    # Used to populate settings in WHM with defaults
    if ( !-e $conf_file ) {
        my %conf = (
            'BACKUPACCTS'      => 'no',
            'BACKUPDAYS'       => '2,4,6',
            'BACKUPDIR'        => '/backup',
            'BACKUPENABLE'     => 'no',
            'BACKUPFILES'      => 'yes',
            'BACKUPFTPDIR'     => '',
            'BACKUPFTPHOST'    => '',
            'BACKUPFTPPASS'    => '',
            'BACKUPFTPPASSIVE' => 'yes',
            'BACKUPFTPUSER'    => '',
            'BACKUPINC'        => 'no',
            'BACKUPINT'        => 'weekly',
            'BACKUPLOGS'       => 'no',
            'BACKUPMOUNT'      => 'no',
            'BACKUPRETDAILY'   => 0,
            'BACKUPRETMONTHLY' => 1,
            'BACKUPRETWEEKLY'  => 1,
            'BACKUPTYPE'       => 'normal',
            'MYSQLBACKUP'      => 'accounts',
            'BACKUPCHECK'      => 'yes',
            'BACKUP2'          => 'yes',
            'LOCALZONESONLY'   => 'no',
        );
        return wantarray ? %conf : \%conf;
    }

    my $filesys_mtime = ( stat(_) )[9];

    # memory cache
    if ( $filesys_mtime == $conf_file_mtime && $conf_cache ) {
        return wantarray ? %{$conf_cache} : $conf_cache;
    }

    # Check to see if Cpanel::JSON is loaded
    $has_serializer = exists $INC{'Cpanel/JSON.pm'} && $INC{'Cpanel/JSON.pm'} ? 1 : 0;
    Cpanel::Debug::log_debug("Cpanel::Config::Backup::load has_serializer : $has_serializer") if $Cpanel::Debug::level;

    # Cpanel::JSON cache
    if ($has_serializer) {
        Cpanel::Debug::log_debug("Cpanel::JSON load of backup conf") if $Cpanel::Debug::level;
        my $cache_file;
        my $cache_filesys_mtime = 0;

        if ( $> == 0 && -e $shadow_file . '.cache' ) {    # No need to do -r (costs 5 additional syscalls) since root can always read
            $cache_filesys_mtime = ( stat(_) )[9];
            $cache_file          = $shadow_file . '.cache';
        }
        elsif ( -r $conf_file . '.cache' ) {
            $cache_filesys_mtime = ( stat(_) )[9];
            $cache_file          = $conf_file . '.cache';
        }
        my $now = time();

        Cpanel::Debug::log_debug( __PACKAGE__ . "::load cache_filesys_mtime = $cache_filesys_mtime , filesys_mtime: $filesys_mtime , now : $now" ) if $Cpanel::Debug::level;

        if ( $cache_filesys_mtime > $filesys_mtime && $cache_filesys_mtime < $now ) {
            my $conf_ref = Cpanel::JSON::FailOK::LoadFile($cache_file);
            if ( $conf_ref && ( scalar keys %{$conf_ref} ) > 0 ) {
                Cpanel::Debug::log_debug( __PACKAGE__ . "::load file system cache hit" ) if $Cpanel::Debug::level;
                $conf_cache      = $conf_ref;
                $conf_file_mtime = $filesys_mtime;
                return wantarray ? %{$conf_ref} : $conf_ref;
            }
            Cpanel::Debug::log_debug( __PACKAGE__ . "::load file system cache miss" ) if $Cpanel::Debug::level;
        }
    }

    # Process both wwwacct files
    my @configfiles;
    push @configfiles, $conf_file;

    #SECURITY: any refactor of this will require major auditting
    if ( -r $shadow_file ) { push @configfiles, $shadow_file; }    #shadow file must be last as the cache gets written for each file with all the files before it in it

    my $can_write_cache;
    if ( $> == 0 && $has_serializer ) {
        $can_write_cache = 1;
    }

    my %CONF;
    foreach my $configfile (@configfiles) {
        Cpanel::Config::LoadConfig::loadConfig( $configfile, \%CONF, '\s+' );

        if ($can_write_cache) {
            my $cache_file = $conf_file . '.cache';
            if ( $configfile eq $shadow_file ) {
                $cache_file = $shadow_file . '.cache';
            }

            # This used to do a locked write, however since write_file
            # renames into place there is no danger of a partial write
            Cpanel::FileUtils::Write::JSON::Lazy::write_file( $cache_file, \%CONF, ( $configfile eq $shadow_file ) ? 0600 : 0644 );
        }
    }

    $conf_file_mtime = $filesys_mtime;
    $conf_cache      = \%CONF;

    return wantarray ? %CONF : \%CONF;
}

sub save {
    my $conf_ref = shift;
    return if ref $conf_ref ne 'HASH';

    Cpanel::LoadModule::load_perl_module('Cpanel::StringFunc::Trim');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::FlushConfig');
    Cpanel::LoadModule::load_perl_module('Cpanel::Backup::Config');
    my $orig_conf_ref = load();

    # If we're enabling legacy backups, enable all users.
    if ( $orig_conf_ref->{'BACKUPENABLE'} eq 'no' && $conf_ref->{'BACKUPENABLE'} eq 'yes' ) {
        if ( opendir my $dh, '/var/cpanel/users' ) {
            while ( my $user = readdir $dh ) {
                next if $user =~ /^\./;
                next if $user =~ tr/\r\n//;
                Cpanel::Backup::Config::toggle_user_backup_state( { user => $user, legacy => 1, BACKUP => 1 }, {} );
            }
            closedir $dh;
        }
    }

    # when legacy backup is enabled or disabled, need to clear command.tmpl cache
    if ( $orig_conf_ref->{'BACKUPENABLE'} ne $conf_ref->{'BACKUPENABLE'} ) {
        require Whostmgr::Templates::Chrome::Rebuild;
        Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();
    }

    # Merge user supplied data
    @{$orig_conf_ref}{ keys %$conf_ref } = values %$conf_ref;

    # Separate FTP password and store in shadow file
    if ( $orig_conf_ref->{'BACKUPFTPPASS'} ) {
        my %shadow = ( 'BACKUPFTPPASS' => $orig_conf_ref->{'BACKUPFTPPASS'} );
        $shadow{'BACKUPFTPPASS'} = Cpanel::StringFunc::Trim::ws_trim( $shadow{'BACKUPFTPPASS'} );
        Cpanel::Config::FlushConfig::flushConfig( $shadow_file, \%shadow, ' ' );
        chmod 0600, $shadow_file;
        unlink $shadow_file . '.cache';
    }
    else {
        unlink $shadow_file;
    }
    delete $orig_conf_ref->{'BACKUPFTPPASS'};

    $orig_conf_ref->{'BACKUPDAYS'} =~ s/\s*\,\s*$//g;
    if ( $orig_conf_ref->{'BACKUPDAYS'} eq '' ) {
        delete $orig_conf_ref->{'BACKUPDAYS'};
    }

    $orig_conf_ref->{'BACKUPCHECK'} = 'yes';
    $orig_conf_ref->{'BACKUP2'}     = 'yes';

    # Create public versions
    if ( open my $pub_conf_fh, '>', $public_conf ) {
        my %public_config = (
            'BACKUPENABLE' => $orig_conf_ref->{'BACKUPENABLE'},
            'BACKUPTYPE'   => $orig_conf_ref->{'BACKUPTYPE'},
            'BACKUPDIR'    => $orig_conf_ref->{'BACKUPDIR'},
        );
        Cpanel::Config::FlushConfig::flushConfig( $public_conf, \%public_config, ' ' );
        chmod 0644, $public_conf;
    }

    # Write config file
    Cpanel::Config::FlushConfig::flushConfig( $conf_file, $orig_conf_ref, ' ' );
    chmod 0644, $conf_file;
    unlink $conf_file . '.cache';

    Cpanel::Backup::Config::clear_backup_dirs_cache();

    # Recache
    return load();
}

sub get_backupdir {
    my $conf = load();
    return $conf->{'BACKUPDIR'};
}

sub add_cronjob {
    require Cpanel::Config::Crontab;

    my $updated;

    try {
        $updated = Cpanel::Config::Crontab::sync_root_crontab();
    }
    catch {
        Cpanel::Debug::log_warn("Failed to sync root crontab: $_");
    };

    return $updated || 0;
}

1;
