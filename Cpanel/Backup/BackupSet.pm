package Cpanel::Backup::BackupSet;

# cpanel - Cpanel/Backup/BackupSet.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale                ();
use Cpanel::Backup::Config        ();
use Cpanel::Backup::BackupSetUtil ();
use Cpanel::Config::Users         ();
use File::Spec                    ();

my $locale;

#
# Get a hash of all the accounts backed to a list of the backup
# dates for each account
#
sub backup_set_list {

    # Get what we need from the config
    my $config_ref = _get_backup_config_data();
    my $backup_dir = $config_ref->{'backup_dir'};

    my @backup_dirs = _get_backup_directories($backup_dir);

    # Get the users/dates for incremental backups if any
    my $inc_data_ref;
    my %seen_dates;

    # Get the users/dates for incremental backups if any
    foreach my $type ( '', '/weekly', '/monthly' ) {
        my $user_backups = Cpanel::Backup::BackupSetUtil::get_incremental_backup_user_dates( $backup_dir . $type );
        foreach my $user ( keys %{$user_backups} ) {
            push @{ $inc_data_ref->{$user} }, $user_backups->{$user} if !$seen_dates{$user}->{ $user_backups->{$user} };
            $seen_dates{$user}->{ $user_backups->{$user} }++;
        }
    }

    my %results;
    foreach my $dir (@backup_dirs) {

        my $dir_name = ( File::Spec->splitdir($dir) )[-1];

        my @account_list = _get_accounts_in_backup_directory($dir);

        foreach my $account (@account_list) {

            # Skip the dates for which we've already found incremental backups
            next if ( exists $inc_data_ref->{$account} and $inc_data_ref->{$account} eq $dir_name );
            push @{ $results{$account} }, $dir_name;
        }
    }

    # Add the incremental backups to the results
    foreach my $user ( keys %$inc_data_ref ) {
        if ( exists $results{$user} ) {
            push @{ $results{$user} }, @{ $inc_data_ref->{$user} };
        }
        else {
            $results{$user} = $inc_data_ref->{$user};
        }
    }

    return [ map { { 'user' => $_, 'backup_date' => $results{$_} } } sort keys %results ];
}

#
# Gets just a list of all the dates for which we have backups
#
sub backup_date_list {

    # Get what we need from the config
    my $config_ref = _get_backup_config_data();
    my $backup_dir = $config_ref->{'backup_dir'};

    my @backup_dirs = _get_backup_directories($backup_dir);

    my %result_hash = map { ( File::Spec->splitdir($_) )[-1] => 1 } @backup_dirs;

    # Get the users/dates for incremental backups if any
    my $inc_data_ref = Cpanel::Backup::BackupSetUtil::get_incremental_backup_user_dates($backup_dir);

    # Add the incremental backups to the set
    foreach my $date ( values %$inc_data_ref ) {
        $result_hash{$date} = 1;
    }

    my @result_list = reverse sort keys %result_hash;

    return \@result_list;
}

#
# List all the backed up users for a specific date
#
sub backup_user_list {
    my ($date) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    return ( 0, $locale->maketext('A restore point must be specified.') ) unless ($date);

    # Get what we need from the config
    my $config_ref = _get_backup_config_data();
    my $backup_dir = $config_ref->{'backup_dir'};

    # Get any incremental backups that may exist for that date
    my $inc_user_list = Cpanel::Backup::BackupSetUtil::get_incremental_backup_users_for_date( $backup_dir, $date );

    # Get the accounts in the backup directory
    my $dir  = File::Spec->catdir( $backup_dir, $date );
    my $wdir = File::Spec->catdir( $backup_dir, 'weekly',  $date );
    my $mdir = File::Spec->catdir( $backup_dir, 'monthly', $date );

    # if the directory doesn't exist & there are no incremental backups, then this is a bad restore point
    if ( ( !-d $dir && !-d $wdir && !-d $mdir ) and scalar @$inc_user_list < 1 ) {
        return ( 0, $locale->maketext( 'Invalid restore point: [_1]', $date ) );
    }

    # Here we need a list of account names for which there are archives
    my %archives = map { $_ => 1 } (
        _get_accounts_in_backup_directory($dir),
        _get_accounts_in_backup_directory($wdir),
        _get_accounts_in_backup_directory($mdir),
        @$inc_user_list
    );

    # Get a list of all the accounts that exist
    my %users = map { $_ => 1 } Cpanel::Config::Users::getcpusers();

    # Now, construct a list of users/backups mapped to their backup status
    my $result_list = [];

    # Go through archives and see which ones represent an active user
    foreach my $account ( keys %archives ) {
        if ( $users{$account} ) {
            _push_user_status_results( $result_list, $account, 'active' );

            # Remove it from the list of users
            # Remaining users will be users that don't have a backup
            delete $users{$account};
        }
        else {
            _push_user_status_results( $result_list, $account, 'inactive' );
        }
    }

    # Remaining active users do not have backups
    foreach my $account ( keys %users ) {
        _push_user_status_results( $result_list, $account, 'no_backup' );
    }

    return ( 1, $result_list );
}

#
# Add a hash ref containing the username + status to the end of a results array
#
sub _push_user_status_results {
    my ( $array_ref, $user, $status ) = @_;

    push @$array_ref, { 'username' => $user, 'status' => $status };
    return;
}

#
# Return a needed subset of the backup data
#
sub _get_backup_config_data {

    # Get what we need from the config
    my $conf           = Cpanel::Backup::Config::load();
    my $backup_dir     = $conf->{'BACKUPDIR'};
    my $is_incremental = ( $conf->{'BACKUPTYPE'} eq 'incremental' ) ? 1 : 0;
    my $is_compressed  = ( $conf->{'BACKUPTYPE'} eq 'compressed' )  ? 1 : 0;

    return (
        {
            'backup_dir'     => $backup_dir,
            'is_incremental' => $is_incremental,
            'is_compressed'  => $is_compressed
        }
    );
}

#
# Get the all the account names inside of a backup set
#
sub _get_accounts_in_backup_directory {
    my ($backup_dir) = @_;

    # Backups for accounts will be under the accounts directory under the backup set dir
    $backup_dir = File::Spec->catdir( $backup_dir, 'accounts' );
    return () unless -d $backup_dir;

    # List of accounts retrieved
    my @accounts = ();

    my $dh;
    unless ( opendir $dh, $backup_dir ) {
        print STDERR "[backup] Unable to open $backup_dir:  $!";
        return ();
    }

    require Cpanel::Validate::Username;
    my $validate_user_regex_str = Cpanel::Validate::Username::get_regexp_str();
    my @nodes                   = readdir($dh);
    my $name_length;
    foreach my $name ( sort @nodes ) {
        next if $name eq '.' || $name eq '..';
        $name_length = length $name;

        # If it's a directory that looks like an incremental backupw
        if ( $name_length > 7 && substr( $name, -7 ) eq '.tar.gz' ) {
            substr( $name, -7, 7, '' );
        }
        elsif ( $name_length > 4 && substr( $name, -4 ) eq '.tar' ) {
            substr( $name, -4, 4, '' );
        }

        # If its not a valid username no point in proceeding
        elsif ( $name !~ m{$validate_user_regex_str}o ) {
            next;
        }

        # If the dir contains a dot we check if its a valid incremental
        elsif ( index( $name, '.' ) > -1 && !Cpanel::Backup::BackupSetUtil::looks_like_restore_point_directory_incremental( $backup_dir, $name ) ) {
            next;
        }

        push @accounts, $name;
    }

    closedir($dh);

    return @accounts;
}

#
# Returns an ordered list, newest to oldest, of all the paths
# to the backup directories.  Used for pruning.
#
sub _get_backup_directories {
    my ($basedir) = @_;

    # Our result list of directories
    my @backup_dirs = ();

    foreach my $bu_dir ( $basedir, $basedir . '/weekly', $basedir . '/monthly' ) {
        if ( !-d $bu_dir ) { next; }
        if ( opendir my $dh, $bu_dir ) {
            while ( my $dir_name = readdir $dh ) {

                # Only get the ones formated YYYY-MM-DD
                next unless ( ( $dir_name =~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}\/?$/ ) );

                my $full_dir = File::Spec->catdir( $bu_dir, $dir_name );

                if ( -d $full_dir ) {
                    push @backup_dirs, $full_dir;
                }
            }
            closedir($dh);
        }
        else {
            print STDERR "[backup] Unable to open $bu_dir:  $!";
        }
    }

    return reverse sort @backup_dirs;
}

1;
