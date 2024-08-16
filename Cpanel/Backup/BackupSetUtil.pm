package Cpanel::Backup::BackupSetUtil;

# cpanel - Cpanel/Backup/BackupSetUtil.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use File::Spec     ();
use Cpanel::JSON   ();
use Cpanel::Logger ();

my $logger = Cpanel::Logger->new();

# This is the only check we are doing at this time, so don't refactor to make the call directly to get_incremental_backup_date_for_user()
sub is_restore_point_directory_incremental {
    my ( $full_backup_dir, $user ) = @_;
    return 0 if !looks_like_restore_point_directory_incremental( $full_backup_dir, $user );

    return get_incremental_backup_date_for_user( $full_backup_dir, $user );
}

#
# Get a map of users => date for the incremental backups
#
sub get_incremental_backup_user_dates {
    my ($backup_dir) = @_;

    # Get the directory under which all the accounts reside;
    # If it doesn't exist, then we don't have any incrementals
    my $main_dir = File::Spec->catdir( $backup_dir, 'incremental', 'accounts' );
    return {} unless ( -d $main_dir );

    my $dh;
    unless ( opendir $dh, $main_dir ) {
        $logger->warn("Unable to open $main_dir:  $!");
        return {};
    }

    my $results = {};

    while ( my $name = readdir $dh ) {

        # Ignore . and ..
        next if ( $name =~ /^\.\.?$/ );

        # Get the full path for the sub directory
        my $full_name = File::Spec->catdir( $main_dir, $name );

        # Skip if this is not a directory
        next unless ( -d $full_name );

        # Okay, we figure $name must be an account with an incremental backup
        my $date = get_incremental_backup_date_for_user( $backup_dir, $name );

        # But skip if no date for this could be found
        next unless $date;

        # Found an incremntal backup date for the account
        $results->{$name} = $date;
    }

    closedir($dh);

    return $results;
}

#
# Get all the users who have incremental backups for a specific date
#
sub get_incremental_backup_users_for_date {
    my ( $backup_dir, $date ) = @_;

    my $inc_backups_ref = get_incremental_backup_user_dates($backup_dir);
    my @results         = grep { $inc_backups_ref->{$_} eq $date } keys %$inc_backups_ref;

    return \@results;
}

#
# Get the date for the incremental backup for a particular user
# Return 'undef' if there isn't one
#
sub get_incremental_backup_date_for_user {
    my ( $backup_dir, $user ) = @_;

    # Get the directory for the incremental backup for the account
    # and verify that it exists
    my $new_inc_account_dir = File::Spec->catdir( $backup_dir, $user );
    my $account_dir;
    if ( -d $new_inc_account_dir ) {
        $account_dir = $new_inc_account_dir;
    }
    else {
        # only fallback to old_inc_account_dir catdir
        # if needed
        my $old_inc_account_dir = File::Spec->catdir( $backup_dir, 'incremental', 'accounts', $user );
        if ( -d $old_inc_account_dir ) {
            $account_dir = $old_inc_account_dir;
        }
        else {
            return undef;
        }
    }

    my $date = read_date_from_meta_file($account_dir);

    # If we can read it from the meta file, just return it.
    return $date if ( defined $date and $date );

    # Couldn't read it, so we need to generate it
    my $latest_data_ref = get_latest_file_date_for_directory($account_dir);
    my $timestamp       = $latest_data_ref->{'timestamp'};

    # If we can generate it, write it to the meta file
    $date = write_date_to_meta_file( $account_dir, $timestamp ) if ($timestamp);

    return $date;
}

sub read_date_from_meta_file {
    my ($account_dir) = @_;

    my $hash_ref = get_hash_from_meta_file( get_meta_file_path($account_dir) );

    return $hash_ref->{'BACKUP_DATE'};
}

#
# Take a timestamp and convert it to our date format
# write it to the meta file & return what we converted
#
sub write_date_to_meta_file {
    my ( $account_dir, $timestamp ) = @_;

    # Convert into our human-readable date
    my ( $day, $month, $year ) = ( localtime($timestamp) )[ 3, 4, 5 ];

    # Return it converted into our date stamp format for backups
    my $date = sprintf "%04d-%02d-%02d", $year + 1900, $month + 1, $day;

    my $meta_file = get_meta_file_path($account_dir);

    my $hash_ref = {};

    if ( -e $meta_file ) {
        $hash_ref = get_hash_from_meta_file($meta_file);
    }

    $hash_ref->{'BACKUP_DATE'} = $date;

    if ( !write_hash_to_meta_file( $meta_file, $hash_ref ) ) {
        $logger->warn("Unable to write $date to meta file $meta_file");
    }

    return $date;
}

#
# Deserialize the metadata file into a hash,
# If it doesn't exist or contains nothing or is corrupt or unreadable
# then just return an empty hash
#
sub get_hash_from_meta_file {
    my ($meta_file) = @_;

    my $fh;
    unless ( open( $fh, '<', $meta_file ) ) {
        $logger->warn("Unable to read $meta_file");
        return {};
    }

    my $contents = <$fh>;
    close $fh;

    my $hash_ref;

    eval { local $SIG{__DIE__}; $hash_ref = Cpanel::JSON::Load($contents); };
    unless ( $hash_ref && ref $hash_ref eq 'HASH' ) {
        $logger->warn("Unable to load data from $meta_file: it may be empty or corrupt.");
        return {};
    }

    return $hash_ref;
}

#
# Write the hash data to the meta file
# Return 0/1 for fail/pass
#
sub write_hash_to_meta_file {
    my ( $meta_file, $hash_ref ) = @_;

    # We unlink the file before we start writing to it,
    # because otherwise, we'll incorrectly link previously generated weekly/monthly
    # backups to the current backup's date. (See notes in case 94809)
    unlink $meta_file;
    if ( open( my $fh, '>', $meta_file ) ) {
        my $contents = Cpanel::JSON::SafeDump($hash_ref);
        print {$fh} $contents;
        close $fh;
        return 1;
    }
    else {
        $logger->warn("Could not open $meta_file for writing : $!");
        return 0;
    }

}

#
# Given the path to an account's incremental backup directory,
# return the full path to the meta data file
#
sub get_meta_file_path {
    my ($account_dir) = @_;
    return File::Spec->catfile( $account_dir, 'backup_meta_data' );
}

#
# This is used to generate an incremental backup meta-file that
# doesn't yet exist.
#
sub get_latest_file_date_for_directory {
    my ($path) = @_;

    my $timestamp = 0;
    my $newest;

    # pkgacct always creates a version file when it does a backup
    # so we just check this
    #
    my ($mtime) = ( stat("$path/version") )[9];

    if ($mtime) {
        $timestamp = $mtime;
        $newest    = "$path/version";
    }

    # 'newest' file info helps with debugging
    return ( { timestamp => $timestamp, newest => $newest } );
}

# A light weight version of is_restore_point_directory_incremental that
# only checks to see if the homedir exists
sub looks_like_restore_point_directory_incremental {
    my ( $full_backup_dir, $user ) = @_;
    return -d "$full_backup_dir/$user/homedir" ? 1 : 0;
}

1;
