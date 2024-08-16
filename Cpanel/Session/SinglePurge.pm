package Cpanel::Session::SinglePurge;

# cpanel - Cpanel/Session/SinglePurge.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Session ();
use Cpanel::Session::Load   ();

our $VERSION = 3.0;

# Purge all sessions for user
# input:
#    user - the user to purge
#    reason - why the sessions are being removed
sub purge_user {
    my ( $user, $reason, $log_obj ) = @_;

    my $user_string = "$user:";
    foreach my $dir ( Cpanel::Config::Session::session_dirs() ) {
        if ( opendir( my $session_dir, $dir ) ) {
            while ( my $session = readdir($session_dir) ) {
                purge_session( $session, $reason, $log_obj ) if index( $session, $user_string ) == 0;
            }
            closedir($session_dir);
        }
    }
    return;
}

sub purge_session {
    my ( $session, $reason, $log_obj, $faillog ) = @_;

    $session =~ tr{/}{}d;

    my $obfree_session = $session;
    Cpanel::Session::Load::get_ob_part( \$obfree_session );    # strip obpart for log and file access

    if ( !-e $Cpanel::Config::Session::SESSION_DIR . '/preauth/' . $obfree_session ) {
        my ($user) = ( split( m{:}, $session ) )[0];
        if ($user) {
            my $session_ref = Cpanel::Session::Load::loadSession($session);
            my $err;
            if ( $session_ref->{'session_temp_user'} && $session_ref->{'session_temp_pass'} ) {
                my $session_temp_user         = $session_ref->{'session_temp_user'};
                my $created_session_temp_user = $session_ref->{'created_session_temp_user'};
                require Cpanel::Session::Temp;
                local $@;
                eval { Cpanel::Session::Temp::remove_temp_user( $user, $session_temp_user, $created_session_temp_user ); };
                $err = $@;
            }
            my $key = $err ? 'FAILEDPURGE' : 'PURGE';

            _kill_registered_processes( $user, $session_ref );

            my $host = ( $ENV{'REMOTE_HOST'} || 'internal' );
            $reason ||= 'unknown';

            my $safe_fail_log = $faillog || '';
            $safe_fail_log =~ s/[\r\n]//g;
            my $entry = qq{$host $key $obfree_session $reason} . ( $safe_fail_log ? " [$safe_fail_log]" : '' ) . qq{\n};

            require Cpanel::Logger;
            require Cpanel::ConfigFiles;
            $log_obj ||= Cpanel::Logger->new( { 'alternate_logfile' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/session_log' } );
            if ( !$log_obj ) { die "Could not open session_log: $!"; }
            $log_obj->info($entry);
        }
    }

    return unlink( map { "$_/$obfree_session" } Cpanel::Config::Session::session_dirs() );

}

sub _kill_registered_processes {
    my ( $username, $session_ref ) = @_;

    my $list_str = $session_ref->{'registered_processes'};

    if ( length $list_str ) {
        require Cpanel::UPID;
        require Cpanel::UPIDList;

        my $rprocs = Cpanel::UPIDList->new($list_str);

        # Don’t terminate processes that are already gone.
        $rprocs->prune();

        my @pids = map { Cpanel::UPID::extract_pid($_) } $rprocs->get();

        if (@pids) {
            require Cpanel::Daemonizer::Tiny;

            # We daemonize so that safekill_multipid() can wait on the
            # processes without delaying the logout.
            Cpanel::Daemonizer::Tiny::run_as_daemon(
                sub {
                    require Cpanel::Kill;

                    # In case any of the processes is a process group leader …
                    @pids = map { -$_, $_ } @pids;

                    my $is_whm = ( -1 != index( $session_ref->{'origin_as_string'} // q<>, 'app=whostmgr' ) );

                    if ( !$is_whm ) {
                        require Cpanel::AccessIds::SetUids;
                        Cpanel::AccessIds::SetUids::setuids($username);
                    }

                    return Cpanel::Kill::safekill_multipid( \@pids );
                }
            );
        }
    }

    return;
}

1;
