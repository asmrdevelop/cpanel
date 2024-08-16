package Whostmgr::Config::Backup;

# cpanel - Whostmgr/Config/Backup.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = 1.1;    # Should match Whostmgr::Config::Backup

use Cwd                      ();
use Cpanel::Tar              ();
use Cpanel::SimpleSync::CORE ();
use Cpanel::SafeDir::MK      ();
use Cpanel::TempFile         ();    #for sub modules
use Cpanel::Filesys::Home    ();
use Cpanel::Rand             ();
use Cpanel::Dir::Loader      ();
use Cpanel::FileUtils::Copy  ();

use Whostmgr::Config::BackupUtils ();

use File::Path;

sub new {
    my $class = shift;

    my $self = { 'files_to_copy' => {} };
    $self = bless $self, $class;

    return $self;
}

sub _list_modules {
    my $self = shift;

    my @modules;
    my %BACKUP_MODULES = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/Whostmgr/Config/Backup');
    foreach my $type ( sort keys %BACKUP_MODULES ) {
        next if $type eq 'Base';
        foreach my $module ( @{ $BACKUP_MODULES{$type} } ) {
            my $mod = $module;
            $mod =~ s/\.pm$// or next;
            my $api_name = lc "cpanel::${type}::$mod";
            push @modules, { 'module' => $module, 'type' => $type, 'api_name' => $api_name, 'short_mod' => $mod };
        }
    }
    return \@modules;

}

sub _load_modules {
    my $self       = shift;
    my $module_ref = shift;

    my $all_modules_ref = $self->_list_modules();

    foreach my $module_info ( @{$all_modules_ref} ) {
        my $mod      = $module_info->{'short_mod'};
        my $module   = $module_info->{'module'};
        my $type     = $module_info->{'type'};
        my $api_name = $module_info->{'api_name'};
        if ( ref $module_ref && %{$module_ref} && !exists $module_ref->{$api_name} ) { next; }
        if ( !exists $INC{"Whostmgr/Config/Backup/$type/$mod.pm"} ) {
            eval "require Whostmgr::Config::Backup::${type}::${mod};";
            if ($@) {
                print STDERR "Failed to load module Whostmgr::Config::Backup::${type}::${mod}: $@\n";
            }
        }
        if ( !$self->{'modules'}->{$api_name} ) {
            $self->{'modules'}->{$api_name} = eval "Whostmgr::Config::Backup::${type}::${mod}->new();";
            if ($@) {
                print STDERR "Failed to create object Whostmgr::Config::Backup::${type}::${mod}: $@\n";
                delete $self->{'modules'}->{$api_name};
            }
        }
    }
    return;
}

sub backup {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my $self = shift;
    my %OPTS = @_;

    my $backup_path = $OPTS{'backup_path'};
    my $parent_dir  = $OPTS{'parent_dir'} || '';
    my $module_ref  = $OPTS{'modules'};
    my $skip_post   = $OPTS{'skip_post'};
    my $verbose     = $OPTS{'verbose'} || 0;

    $self->{'files_to_copy'} = {};
    my $cwd = Cwd::fastcwd() || Cwd::getcwd() || '/';

    chdir($cwd) || return ( 0, "Could not validate current working directory: $!" );

    $self->_load_modules($module_ref);

    my %VERSIONS;
    foreach my $module ( keys %{$module_ref} ) {
        if ( !exists $self->{'modules'}->{$module} || !ref $self->{'modules'}->{$module} ) {
            return ( 0, "The module $module could not be loaded" );
        }
        $VERSIONS{$module} = $self->{'modules'}->{$module}->version();
    }

    foreach my $module ( keys %{ $self->{'modules'} } ) {
        if ( ref $module_ref && %{$module_ref} && !$module_ref->{$module} ) { next; }
        $self->{'modules'}->{$module}->{'caller'} = $self;
        eval { $self->{'modules'}->{$module}->backup($self); };
        if ($@) {
            return ( 0, "$module failed: $@" );
        }
    }

    Cpanel::SafeDir::MK::safemkdir( $parent_dir, '0700' ) if ( !-d $parent_dir );

    my $time = time();
    if ( !$backup_path ) {
        $parent_dir ||= Cpanel::Filesys::Home::get_homematch_with_most_free_space();
        $backup_path = Cpanel::Rand::get_tmp_dir_by_name( $parent_dir . '/whm-config-backup' );
    }
    elsif ( !$parent_dir ) {
        my @backup_path_path = split( /\/+/, $backup_path );
        pop @backup_path_path;
        $parent_dir = join( '/', @backup_path_path );
    }
    return ( 0, "Failed to find a place to store the backup" ) if !$parent_dir;
    return ( 0, "Failed to create a tmp dir for the backup" )  if !$backup_path;

    chdir($backup_path) || return ( 0, "Could not chdir to $backup_path" );

    $backup_path =~ s/\/+/\//g;
    $parent_dir  =~ s/\/+/\//g;

    if ( ( $parent_dir =~ tr/\/// ) < 1 ) {
        return ( 0, "Parent Dir: $parent_dir cannot be a top level directory" );    # ok to not remove because invalid
    }
    if ( ( $backup_path =~ tr/\/// ) < 2 ) {
        return ( 0, "Backup Path: $backup_path cannot be a top or second level directory" );    # ok to not remove because invalid
    }
    if ( open( my $version_fh, ">", "$backup_path/version" ) ) {
        print {$version_fh} "version=$VERSION\ntime=$time\n";
        close($version_fh);
    }
    else {
        system '/bin/rm', '-rf', '--', $backup_path if $backup_path;
        return ( 0, "failed to create version file" );
    }

    $self->{'backup_path'} = $backup_path;

    foreach my $fmodule ( keys %{ $self->{'files_to_copy'} } ) {
        foreach my $source_file ( keys %{ $self->{'files_to_copy'}->{$fmodule} } ) {
            my $target_data = $self->{'files_to_copy'}->{$fmodule}->{$source_file};
            my $target_dir  = $target_data->{'dir'};
            my $file_name   = $target_data->{'file'} || ( split( /\/+/, $source_file ) )[-1] || $source_file;

            Cpanel::SafeDir::MK::safemkdir( "$backup_path/$target_dir", 0755 ) if !-e "$backup_path/$target_dir";
            print "Backing up $source_file …\n"                                if $verbose;
            my ( $sync_status, $sync_statusmsg ) = Cpanel::SimpleSync::CORE::syncfile( $source_file, "$backup_path/$target_dir/$file_name" );
            if ( !$sync_status ) {
                print STDERR "Could not install $source_file => $backup_path/$target_dir/$file_name: $sync_statusmsg\n";
            }
        }
    }

    if ( exists $self->{'dirs_to_copy'} ) {
        foreach my $dmodule ( sort keys %{ $self->{'dirs_to_copy'} } ) {
            foreach my $source_dir ( sort keys %{ $self->{'dirs_to_copy'}->{$dmodule} } ) {
                next if !-e $source_dir;

                my $target_data = $self->{'dirs_to_copy'}->{$dmodule}->{$source_dir};
                my $base_path   = $backup_path . "/" . $target_data->{'archive_dir'};

                # If the source is a symlink make sure to copy what is linked
                # Making sure it has a trailing "/" will ensure this
                if ( -l $source_dir and $source_dir !~ /\/$/ ) {
                    $source_dir .= '/';
                }

                print "Backing up $source_dir …\n" if $verbose;
                Cpanel::FileUtils::Copy::safecopy( $source_dir, $base_path );
            }
        }
    }

    foreach my $module ( keys %VERSIONS ) {
        my $version = $VERSIONS{$module};
        my $vpath   = $module;
        $vpath =~ s/::/\//g;
        Cpanel::SafeDir::MK::safemkdir( "$backup_path/$vpath/", 0755 ) if !-e "$backup_path/$vpath/";
        if ( open( my $version_fh, ">", "$backup_path/$vpath/version" ) ) {
            print {$version_fh} "version=$version\ntime=$time\n";
            close($version_fh);
        }
        else {
            print STDERR "failed to write $backup_path/$vpath/version: $!\n";
        }
    }

    my $tarcfg = Cpanel::Tar::load_tarcfg();

    my $file_name = $OPTS{'file-prefix'} || 'whm-config-backup';

    if ( !$module_ref || 2 > keys %$module_ref ) {
        my $type;

        if ( my $key = ref($module_ref) && ( keys %$module_ref )[0] ) {
            $type = "$key-$VERSIONS{$key}";
        }
        else {
            $type = "all-$VERSION";
        }

        $type =~ s/::/__/g;

        $file_name .= "-$type";
    }

    $file_name .= "-$time.tar.gz";

    {
        require Cpanel::Umask;
        require Cpanel::Autodie;

        my $umask_obj = Cpanel::Umask->new(077);
        Cpanel::Autodie::open( my $cpm, '>', "../$file_name" );
        Cpanel::Autodie::chmod( 0600, $cpm );
    }
    my $rv = system( $tarcfg->{'bin'}, '--use-compress-program=/usr/local/cpanel/bin/gzip-wrapper', '--create', '--preserve-permissions', '--file', "../$file_name", '.' );
    if ($rv) {    #ran out of disk space or failed
        system '/bin/rm', '-rf', '--', $backup_path if $backup_path;
        return ( 0, "tar failed or ran out of disk space during the backup" );
    }

    if ( !$skip_post ) {
        foreach my $module ( keys %{ $self->{'modules'} } ) {
            if ( ref $module_ref && %{$module_ref} && !$module_ref->{$module} ) { next; }

            $self->{'modules'}->{$module}->{'caller'} = $self;

            eval { $self->{'modules'}->{$module}->post_backup($self); };
        }
    }
    system '/bin/rm', '-rf', '--', $backup_path if $backup_path;

    chdir($cwd) || return ( 0, "Could not return to previous working directory" );

    return ( 1, "Backup Successful", "$parent_dir/$file_name" );
}

#    Whostmgr::Config::Backup::backup_ifexists ($parent, '/var/cpanel/conf/apache', 'cpanel/easy/apache/other', 'local');
#    Whostmgr::Config::Backup::backup_ifexists ($parent, '/var/cpanel/conf/apache', 'cpanel/easy/apache/other', 'main');
#    Whostmgr::Config::Backup::backup_ifexists ($parent, '/usr/local/apache/conf', 'cpanel/easy/apache', 'includes');
#    Whostmgr::Config::Backup::backup_ifexists ($parent, '/var/cpanel/templates', 'cpanel/easy/apache/templates', "apache*/*local");

sub backup_ifexists {
    my ( $parent, $module, $dir, $backup_dir, $file_spec ) = @_;

    $parent->{'files_to_copy'}->{$module} = {} if !exists $parent->{'files_to_copy'}->{$module};
    $parent->{'dirs_to_copy'}->{$module}  = {} if !exists $parent->{'dirs_to_copy'}->{$module};

    my $files_to_copy = $parent->{'files_to_copy'}->{$module};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{$module};

    my @files = glob("$dir/$file_spec");

    foreach my $file (@files) {
        my $my_backup_dir = $backup_dir;
        my $my_file       = $file;

        # deal with multi level file spec

        if ( index( $file_spec, "/" ) >= 0 ) {
            my $subpart = Whostmgr::Config::BackupUtils::remove_base_path( $dir, $file );

            my @array = split( /\//, $subpart );
            my $xfile = pop @array;
            my $xdir  = join( '/', @array );

            $my_backup_dir .= "/$xdir";
            $my_file = $xfile;
        }

        if ( -e $file ) {
            if ( -d $file ) {
                $dirs_to_copy->{$file} = { "archive_dir" => $my_backup_dir };
            }
            else {
                $files_to_copy->{$file} = { "dir" => $my_backup_dir };
            }
        }
    }

    return;
}

our $_prerestore_backup_parent = '/var/cpanel/cpconftool_prerestore_backups';

sub prerestore_backup {
    if ( ( ref( $_[0] ) ) =~ m/^Whostmgr::Config/ ) {    # if accidentally called $backup->prerestore_backup
        shift;
    }

    my @modules = @_;
    die "No modules specified" if @modules == 0;

    my $modules_ref = { map { $_ => 1 } @modules };

    my $tmpobj = Cpanel::TempFile->new();

    my $backup = Whostmgr::Config::Backup->new();
    my ( $status, $statusmsg, $file ) = $backup->backup(
        'modules'     => $modules_ref,
        'skip_post'   => 0,
        'file-prefix' => 'cpconftool-prerestore-backup'
    );

    return ( $status, $statusmsg, $file );
}

sub query_module_info {
    my $self = shift;
    my %OPTS = @_;

    my $module_ref = $OPTS{'modules'};
    $self->_load_modules($module_ref);

    my $output = {};

    foreach my $module ( keys %{$module_ref} ) {
        if ( !exists $self->{'modules'}->{$module} || !ref $self->{'modules'}->{$module} ) {
            $output->{$module} = "$module could not be loaded";
        }
        else {
            my $obj = $self->{'modules'}->{$module};
            if ( $obj->can("query_module_info") ) {
                $output->{$module} = $obj->query_module_info();
            }
            else {
                $output->{$module} = "N/A";
            }
        }
    }

    return $output;
}

1;
