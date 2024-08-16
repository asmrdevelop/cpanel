package Cpanel::Backup::SkipUsers;

# cpanel - Cpanel/Backup/SkipUsers.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale             ();
use Cpanel::CloseFDs           ();
use Cpanel::Sys::Setsid::Fast  ();
use Whostmgr::Accounts::List   ();
use Whostmgr::Accounts::Modify ();

our $skipusers_file         = '/etc/cpbackup-userskip.conf';
our $update_status_path     = '/var/cpanel/backups/.updatestatus.log';
our $update_status_pid_path = '/var/cpanel/backups/.updatestatus.pid';
my $locale;

# This function determines the status of a forked update_all_users_files() call and returns it
# returns 'perc' ( percent complete ) , 'msg' ( short text for status ) ,
# If still running: 'lastuser' for last user updated, 'cnt' for number of users processed, 'starttime' for when the process
#  was started and the 'currenttime' for when the status call was made. All of these can be used to let the user know how far
#  along in the process it is.
sub set_all_status {
    my %status;
    my $retcode = 1;
    $locale ||= Cpanel::Locale->get_handle();

    $status{'msg'} = "Default status";

    # process is not running by default
    $status{'running'} = 0;

    if ( -e $update_status_pid_path ) {
        if ( open( my $pid_fh, '<', $update_status_pid_path ) ) {
            chomp( my $pid = <$pid_fh> );
            close($pid_fh);

            # sanity check on pid value
            if ( $pid !~ m/^\d+$/ ) {
                $retcode = 0;
                $status{'msg'} = $locale->maketext( 'Bad PID value detected in “[_1]”.', $update_status_pid_path );
            }
            else {

                # check to see if the process is still running or not
                if ( kill 0, $pid ) {

                    # process still going, get the latest available data from the log and return it
                    $status{'running'} = 1;
                    if ( open( my $data_fh, '<', $update_status_path ) ) {
                        chomp( my $data = <$data_fh> );
                        close($data_fh);
                        $retcode = 1;
                        ( $status{'starttime'}, $status{'cnt'}, $status{'perc'}, $status{'lastuser'} ) = split( /\|/, $data, 4 );
                        $status{'currenttime'} = time;
                        $status{'msg'}         = 'OK';
                    }
                    else {
                        $retcode = 0;
                        $status{'msg'} = $locale->maketext( 'Could not open status log “[_1]” : [_2]', $update_status_path, $! );
                    }
                }
                else {    # if the pid is no longer active, assume the process has completed
                    $retcode        = 1;
                    $status{'perc'} = 100;
                    $status{'msg'}  = $locale->maketext('Done');

                    # remove pidfile now that we've detected it as m.i.a.
                    unlink($update_status_pid_path);
                }
            }
        }
        else {
            $retcode = 0;
            $status{'msg'} = $locale->maketext( 'Could not open “[_1]” : [_2]', $update_status_pid_path, $! );
        }
    }
    else {
        $retcode = 1;                                                         # that's fine
        $status{'msg'} = $locale->maketext('No save_all process running.');
    }
    return ( $retcode, \%status );
}

sub emend_state {
    my ($state) = @_;
    if   ( $state =~ m/^disable/i ) { $state = 0; }
    if   ($state)                   { $state = 1; }
    else                            { $state = 0; }
    return $state;
}

# Forks off a process that will loop through all cPanel user accounts and set the requested status for legacy/new backup types
# in the user config files. While this is much faster than calling modifyacct, it still takes a little time and is thus backgrounded.
# Call set_all_status() to get information on it's progress
sub update_all_users_files {
    my ($args_ref) = @_;
    $locale ||= Cpanel::Locale->get_handle();
    my $dbg = 0;

    # check to be sure we aren't already running a mass update
    if ( -e $update_status_pid_path ) {
        if ( open( my $pid_fh, '<', $update_status_pid_path ) ) {
            chomp( my $pid = <$pid_fh> );
            close($pid_fh);
            if ( $pid =~ m/^\d+$/ ) {

                # check to see if the process is still running or not
                if ( kill 0, $pid ) {
                    return ( 0, $locale->maketext( 'Configuration update process already running ([_1]).', $pid ) );
                }
            }
        }
    }

    # If the state we want to set is not specified as 1, we default to 0
    my $state = emend_state( $$args_ref{'state'} );
    if ( $dbg > 0 ) { print STDERR "state = $state\n"; }

    # If the backup version isn't specified as backup, default to legacy backup
    my $type = $$args_ref{'backupversion'};
    if   ( $dbg > 0 )             { print STDERR "Backup type = $type\n"; }
    if   ( $type =~ m/^backup/i ) { $type = 'backup'; }
    else                          { $type = 'legacy_backup'; }

    # fork into background as this might take awhile
    if ( $dbg > 0 ) { print STDERR "Forking process into background..\n"; }

    my $mainpid;
    unless ( $mainpid = fork ) {
        unless (fork) {
            Cpanel::Sys::Setsid::Fast::fast_setsid();
            Cpanel::CloseFDs::fast_daemonclosefds();
            $0 = "cPBackup Config Processing";

            my ( $success, $msg ) = write_pid( $$, $update_status_pid_path );
            if ( !$success ) {
                return ( 0, $msg );
            }
            loop_and_modify_all_accounts( $state, $type, \@{ Whostmgr::Accounts::List::listaccts() } );
            exit 0;
        }
        exit 0;
    }
    if ( $dbg > 0 ) { print STDERR "Process is backgrounded\n"; }
    my $waiting = waitpid( $mainpid, 0 );
    if ( $dbg > 0 ) { print STDERR "Waiting .. $waiting ($mainpid)\n"; }
    return ( 1, $locale->maketext('Configuration update process started') );
}

sub write_pid {
    my ( $pid, $update_status_pid_path ) = @_;
    if ( $update_status_pid_path !~ m/\.pid$/ ) {
        return ( 0, $locale->maketext('Bad path name; it must end in [output,class,.pid,code].') );
    }
    if ( open( my $pid_fh, '>', $update_status_pid_path ) ) {
        print $pid_fh $pid;
        close($pid_fh);
        return ( 1, "OK" );
    }
    else {
        return ( 0, $locale->maketext( 'Could not open “[_1]” : [_2]', $update_status_pid_path, $! ) );
    }
}

sub loop_and_modify_all_accounts {
    my ( $state, $type, $accounts_ref ) = @_;
    my $acct_ttl  = @{$accounts_ref};
    my $starttime = time;
    my $cnt       = 0;
    my $perc      = 0;
    foreach my $acct_hr ( @{$accounts_ref} ) {
        $cnt++;
        if ( $acct_ttl > 0 ) {
            $perc = int( ( $cnt / $acct_ttl ) * 100 );
        }

        # Greater overhead to write out all users rather than just ones we don't skip, but this avoids a lot of edge cases
        # where the output wouldn't make any sense. If this becomes a real problem, move it behind the next if int line below
        # and just write 100% once it exits the loop.
        if ( open( my $log_fh, '>', $update_status_path ) ) {
            print $log_fh "$starttime\|$cnt\|$perc\|$acct_hr->{'user'}\n";
            close($log_fh);
        }
        next if int $acct_hr->{$type} == int $state;
        Whostmgr::Accounts::Modify::modify( 'user' => $acct_hr->{'user'}, uc($type) => $state );
    }
    return;
}

sub sync_legacy_userfile2skipusers {

    no warnings 'redefine';
    local *Whostmgr::ACLS::hasroot = sub { 1 };    # PPI NO PARSE -- module does not need to be load

    my @skipusers;
    foreach my $acct_hr ( @{ Whostmgr::Accounts::List::listaccts() } ) {
        next if $acct_hr->{'legacy_backup'};
        push @skipusers, $acct_hr->{'user'};
    }

    if ( open my $skipfile_fh, '>', $skipusers_file ) {
        print $skipfile_fh join( "\n", @skipusers );
        close $skipfile_fh;
    }
    else {
        return 0;
    }
    return 1;
}

sub sync_legacy_skipusers2userfile {

    no warnings 'redefine';
    local *Whostmgr::ACLS::hasroot = sub { 1 };    # PPI NO PARSE -- module does not need to be load

    if ( open my $skipfile_fh, '<', $skipusers_file ) {

        my %skipped_users;
        while ( my $user = readline $skipfile_fh ) {
            chomp $user;
            $skipped_users{$user} = 1;
        }

        foreach my $acct_hr ( @{ Whostmgr::Accounts::List::listaccts() } ) {
            my $username = $acct_hr->{'user'};
            if ( exists $skipped_users{$username} ) {

                # next if !$acct_hr->{'legacy_backup'}; # set default of off if no entry exists and user is in the skip file
                Whostmgr::Accounts::Modify::modify( 'user' => $username, 'LEGACY_BACKUP' => 0 );
            }
            else {
                next if $acct_hr->{'legacy_backup'};    # if entry already exists, don't overwrite
                Whostmgr::Accounts::Modify::modify( 'user' => $username, 'LEGACY_BACKUP' => 1 );
            }
        }
        return 1;
    }
    else {
        return 0;
    }

}

sub sync_legacy_users {
    my ($source) = @_;

    if ( $source eq 'skipusers' ) {
        sync_legacy_skipusers2userfile();
    }
    elsif ( $source eq 'userfile' ) {
        sync_legacy_userfile2skipusers();
    }
    else {
        die 'Invalid Source provided: ' . $source;
    }
    return;
}

# used in unit testing

sub _set_skipusers_file {
    ($skipusers_file) = @_;
    return;
}

1;
