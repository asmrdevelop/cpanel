
# cpanel - Whostmgr/Config/Restore.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Config::Restore;

use strict;
use warnings;

our $VERSION = 1.1;    # should match Whostmgr::Config::Restore

use strict;
use Cwd                      ();
use Cpanel::Tar              ();
use Cpanel::SimpleSync::CORE ();
use Cpanel::SafeDir::MK      ();
use Cpanel::Filesys::Home    ();
use Cpanel::Rand             ();
use Cpanel::Dir::Loader      ();
use Cpanel::FileUtils::Copy  ();

use Whostmgr::Config::BackupUtils ();

use File::Path ();

sub new {
    my $class = shift;

    my $self = {};
    $self = bless $self, $class;

    return $self;
}

sub _list_modules {
    my $self = shift;

    my @modules;
    my %BACKUP_MODULES = Cpanel::Dir::Loader::load_multi_level_dir('/usr/local/cpanel/Whostmgr/Config/Restore');
    foreach my $type ( sort keys %BACKUP_MODULES ) {
        next if $type =~ m<\Abase\z>i;

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
        if ( !exists $INC{"Whostmgr/Config/Restore/$type/$mod.pm"} ) {
            eval "require Whostmgr::Config::Restore::${type}::${mod};";
            if ($@) {
                print STDERR "Failed to load module Whostmgr::Config::Restore::${type}::${mod}: $@\n";
            }
        }
        if ( !$self->{'modules'}->{$api_name} ) {
            $self->{'modules'}->{$api_name} = eval "Whostmgr::Config::Restore::${type}::${mod}->new();";
            if ($@) {
                print STDERR "Failed to create object Whostmgr::Config::Restore::${type}::${mod}: $@\n";
                delete $self->{'modules'}->{$api_name};
            }
        }
    }
    return;
}

sub restore {    ## no critic qw(Subroutines::ProhibitExcessComplexity Subroutines::RequireArgUnpacking)
    my $self = shift;
    my %OPTS = @_;

    my $backup_path       = $OPTS{'backup_path'};
    my $module_ref        = $OPTS{'modules'};
    my $skip_post         = $OPTS{'skip_post'};
    my $prefix            = $OPTS{'prefix'}            || '';
    my $prerestore_backup = $OPTS{'prerestore_backup'} || 0;
    my $verbose           = $OPTS{'verbose'}           || 0;

    $self->{'files_to_copy'} = {};

    $self->_load_modules($module_ref);

    if ($prerestore_backup) {
        require Whostmgr::Config::Backup;

        my @modules;
        foreach my $module ( keys %{ $self->{'modules'} } ) {
            push( @modules, $module );
        }

        Whostmgr::Config::Backup::prerestore_backup(@modules) if @modules;
    }

    if ( $prefix && $prefix =~ /\/$/ ) {
        $prefix =~ s/\/+$//g;
    }

    my $cwd = Cwd::fastcwd() || '/';
    chdir($cwd)              || return ( 0, "Could not validate current working directory: $!" );

    my $remove_backup_path = 0;

    if ( !defined $backup_path ) {
        return ( 0, "Backup Path: backup path is not defined" );
    }
    elsif ( !-e $backup_path ) {
        return ( 0, "Backup Path: $backup_path does not exist" );
    }
    elsif ( !-d $backup_path ) {    # assume pre-extracted
        my $tarcfg     = Cpanel::Tar::load_tarcfg();
        my $parent_dir = Cpanel::Filesys::Home::get_homematch_with_most_free_space();
        chdir($parent_dir) || do {
            chdir($cwd);
            return ( 0, "Could not chdir() to $parent_dir" );
        };
        my $backup_dir = Cpanel::Rand::get_tmp_dir_by_name( $parent_dir . '/whm-config-backup' );
        if ( ( $backup_dir =~ tr/\/// ) < 2 ) {
            chdir($cwd);
            return ( 0, "Backup Path: $backup_dir cannot be a top or second level directory" );
        }

        chdir($backup_dir) || do {
            chdir($cwd);
            return ( 0, "Could not chdir() to $parent_dir" );
        };
        my $rv = system( $tarcfg->{'bin'}, "pxzf", $backup_path, '.' );
        if ($rv) {    #ran out of disk space or failed
            $rv = system( $tarcfg->{'bin'}, "pxf", $backup_path, '.' );    #try again without z
            if ($rv) {                                                     #ran out of disk space or failed
                system '/bin/rm', '-rf', '--', $backup_dir if $backup_dir;
                chdir($cwd);
                return ( 0, "untar failed (is this a valid backup?) or we ran out of disk space during the restore" );
            }
        }

        $remove_backup_path = 1;
        $backup_path        = $backup_dir;
    }

    my %CFG;
    if ( open( my $version_fh, "<", "$backup_path/version" ) ) {
        local $/;
        %CFG = map { ( split( /=/, $_ ) )[ 0, 1 ] } split( /\n/, readline($version_fh) );
        close($version_fh);
    }
    else {
        system '/bin/rm', '-rf', '--', $backup_path if $backup_path && $remove_backup_path;
        chdir($cwd);
        return ( 0, "Failed to load version file from backup ($backup_path/version)" );
    }

    if ( $CFG{'version'} > $VERSION ) {
        system '/bin/rm', '-rf', '--', $backup_path if $backup_path && $remove_backup_path;
        chdir($cwd);
        return ( 0, "This backup was created with a newer version of the backup tool ($CFG{'version'}) and cannot be restored with this version ($VERSION)" );
    }

    $self->{'backup_path'} = $backup_path;

    my ( $final_status, %restore_status ) = $self->_do_restore($module_ref);

    my ( $fstatus, $ferrors ) = $self->_restore_files( $prefix, $verbose );

    if ( !$fstatus ) {
        $final_status = -1;
        $restore_status{file_errors} = $ferrors;
    }

    my ( $dstatus, $derrors ) = $self->_restore_dirs( $backup_path, $verbose );

    if ( !$dstatus ) {
        $final_status = -1;
        $restore_status{directory_errors} = $derrors;
    }

    $self->_do_post_actions( $final_status, \%restore_status, $module_ref ) unless $skip_post;

    system '/bin/rm', '-rf', '--', $backup_path if $backup_path && $remove_backup_path;

    chdir($cwd);    # if this fails their system is very broken so no checking here

    my $message = $final_status ? "Restore Successful" : "Restore Failed";
    $message = "Restore Partially Successful" if $final_status == -1;

    return ( $final_status, $message, \%restore_status );
}

sub _do_restore {
    my ( $self, $module_ref ) = @_;

    my $final_status = 0;

    my %restore_status;
    $self->{real_files_to_copy} = {};
    $self->{real_dirs_to_copy}  = {};
    $self->{dirs_to_copy}  //= {};
    $self->{files_to_copy} //= {};

    #nothing to do
    return ( $final_status, %restore_status ) unless ref $module_ref eq 'HASH';

    foreach my $module ( keys %{ $self->{'modules'} } ) {
        next if !$module_ref->{$module};
        $self->{'modules'}->{$module}->{'caller'} = $self;

        my ( $status, $statusmsg, $data ) = $self->{'modules'}->{$module}->restore($self);
        $final_status += $status;

        $restore_status{$module}{'restore'} = { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data };

        #Make sure we don't restore stuff in the event that you know, the restore actually failed
        %{ $self->{'real_files_to_copy'} } = ( %{ $self->{'real_files_to_copy'} }, %{ $self->{'files_to_copy'} } ) if $status;
        $self->{'files_to_copy'} = {};

        #Do the same thing for directories
        %{ $self->{'real_dirs_to_copy'} } = ( %{ $self->{'real_dirs_to_copy'} }, %{ $self->{'dirs_to_copy'} } ) if $status;
        $self->{'dirs_to_copy'} = {};
    }

    #If we don't have as many successes as modules, we have a partial failure
    $final_status = -1 if $final_status && ( scalar( keys( %{ $self->{'modules'} } ) ) != $final_status );

    #Otherwise, clamp the value to 1
    $final_status = !!$final_status if $final_status > 0;

    return ( $final_status, %restore_status );
}

sub _restore_dirs {
    my ( $self, $backup_path, $verbose ) = @_;

    my $errors = [];
    foreach my $source_dir ( sort keys %{ $self->{'real_dirs_to_copy'} } ) {
        my $target_data = $self->{'real_dirs_to_copy'}->{$source_dir};
        my $base_path   = $backup_path . "/" . $target_data->{'archive_dir'};

        if ( !-d $base_path ) {

            #XXX I'm pretty sure this is something we should just let pass rather than reporting as below
            #push( @$errors, "Source directory $base_path does not exist, was skipped" );
            next;
        }

        my $source_parent = Whostmgr::Config::BackupUtils::get_parent_path( $source_dir, 1 );

        if ( -d $source_dir ) {
            my $errors_dir = [];
            File::Path::remove_tree( $source_dir, { 'keep_root' => 1, error => \$errors_dir } );
            push( @$errors, "Could not clear out existing $source_dir!" ) if scalar(@$errors_dir);
        }
        else {
            my $mkdir_res = Cpanel::SafeDir::MK::safemkdir( $source_dir, 0755 );
            if ( !$mkdir_res ) {
                push( @$errors, "Could not create directory $source_dir" );
            }
        }

        print "Restoring $base_path to $source_parent …\n" if $verbose;
        my $copy_res = Cpanel::FileUtils::Copy::safecopy( $base_path, $source_parent );
        push( @$errors, "Could not copy $base_path to $source_parent" ) unless $copy_res;
    }

    #Preserve the old behavior of printing all errors to stderr
    foreach my $msg (@$errors) { print STDERR "$msg\n" }

    return ( int( !scalar(@$errors) ), $errors );
}

sub _restore_files {
    my ( $self, $prefix, $verbose ) = @_;

    my $errors = [];
    foreach my $source_file ( sort keys %{ $self->{'real_files_to_copy'} } ) {
        my $target_data = $self->{'real_files_to_copy'}->{$source_file};
        my $target_dir  = $target_data->{'dir'};
        my $file_name   = $target_data->{'file'} || ( split( /\/+/, $source_file ) )[-1] || $source_file;

        if ( !-d "${prefix}$target_dir" ) {
            my $mkdir_res = Cpanel::SafeDir::MK::safemkdir( "${prefix}$target_dir", 0755 );
            if ( !$mkdir_res ) {
                push( @$errors, "Could not create directory ${prefix}$target_dir" );
                next;
            }
        }

        if ( $target_data->{'delete'} ) {
            my $unlink_res = unlink "${prefix}$target_dir/$file_name";
            push( @$errors, "Could not remove '${prefix}$target_dir/$file_name'!" ) if !$unlink_res && $! != 2;    #Exclude ENOENT, that's OK
        }
        else {
            print "Restoring $source_file to ${prefix}$target_dir/$file_name …\n" if $verbose;
            my ( $sync_status, $sync_statusmsg ) = Cpanel::SimpleSync::CORE::syncfile( $source_file, "${prefix}$target_dir/$file_name" );
            push( @$errors, "Could not install $source_file => ${prefix}$target_dir/$file_name: $sync_statusmsg" ) unless $sync_status;
        }
    }

    #Preserve the old behavior of printing all errors to stderr
    foreach my $msg (@$errors) { print STDERR "$msg\n" }

    return ( int( !scalar(@$errors) ), $errors );
}

sub _do_post_actions {
    my ( $self, $final_status, $restore_status, $module_ref ) = @_;

    foreach my $module ( keys %{ $self->{'modules'} } ) {
        next if ( ref $module_ref ne 'HASH' || !$module_ref->{$module} );
        $self->{'modules'}->{$module}->{'caller'} //= $self;
        next unless $restore_status->{$module}->{'restore'}->{'status'};    # failed
        my ( $status, $statusmsg, $data ) = ( 1, "Success", 'No action Taken' );

        if ( $self->{'modules'}->{$module}->can("post_restore") ) {
            eval { ( $status, $statusmsg, $data ) = $self->{'modules'}->{$module}->post_restore($self); };

            #populate info if we died
            if ($@) {
                $status    = 0;
                $statusmsg = "Failure";
                $data      = $@;
            }

            # either way we failed, and we can only get here if we succeeded at least once
            $final_status = -1 if !$status;

        }

        $restore_status->{$module}->{'post_restore'} = { 'status' => $status, 'statusmsg' => $statusmsg, 'data' => $data };
    }
    return $final_status;
}

sub restore_ifexists {
    my ( $parent, $dir, $target_dir, $file, $del_original ) = @_;

    $del_original = 0 if !defined $del_original;

    my @backups = glob("$dir/$file");

    foreach my $backup (@backups) {
        my $my_target_dir = $target_dir;
        my $my_file       = $file;

        # deal with multi level file spec

        if ( index( $file, "/" ) >= 0 ) {
            my $subpart = Whostmgr::Config::BackupUtils::remove_base_path( $dir, $backup );

            my @array = split( /\//, $subpart );
            my $xfile = pop @array;
            my $xdir  = join( '/', @array );

            $my_target_dir .= "/$xdir";
            $my_file = $xfile;
        }
        else {
            my @array = split( /\//, $backup );
            $my_file = $array[-1];
        }

        if ( -e $backup ) {
            if ( -d $backup ) {
                $parent->{'dirs_to_copy'}->{$backup} = { 'archive_dir' => $my_target_dir };
            }
            else {
                if ($del_original) {
                    my $xfile = $my_target_dir . "/" . $my_file;
                    unlink $xfile if -e $xfile;
                }

                $parent->{'files_to_copy'}->{$backup} = { 'dir' => $my_target_dir, "file" => $my_file };
            }
        }
    }

    return;
}

1;
