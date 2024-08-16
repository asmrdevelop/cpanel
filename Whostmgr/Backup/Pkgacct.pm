package Whostmgr::Backup::Pkgacct;

# cpanel - Whostmgr/Backup/Pkgacct.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Autodie                      ();
use Cpanel::Daemonizer::Tiny             ();
use Cpanel::Exception                    ();
use Cpanel::Logger                       ();
use Cpanel::Rand::Get                    ();
use Cpanel::SafeRun::Object              ();
use Cpanel::Time                         ();
use Cpanel::Validate::LineTerminatorFree ();
use Cpanel::Validate::Username           ();
use Cpanel::Version::Full                ();
use Whostmgr::AcctInfo::Owner            ();
use Whostmgr::Backup::Pkgacct::Config    ();
use Whostmgr::Backup::Pkgacct::Logs      ();
use Whostmgr::Whm5                       ();

use Try::Tiny;

my $MAX_SESSION_DIR_CREATION_ATTEMPTS = 20;

###########################################################################
#
# Method:
#   start_background_pkgacct
#
# Description:
#   This function initiates a pkgacct command initiated as a background process.
#
# Parameters:
#   $user - The username of the user to run the pkgacct on.
#   $args - A hashref of arguments that will be converted by Whostmgr::Whm5::get_pkgcmd to command line arguments.
#           See that function for a complete list of allowed arguments.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter  - Thrown if user is not passed.
#   Cpanel::Exception::UserNotFound      - Thrown if the supplied user doesn't exist or the calling user doesn't have control over them.
#   Cpanel::Exception::InvalidCharacters - Thrown if the args contain an invalid character. Currently, the only invalid character is a null byte '\0'
#   This will also throw anything CpaneL::SafeRun::Object::new_or_die can throw.
#
# Returns:
#   The method returns a hashref on success and throws an exception if it failed.
#   The hashref contains:
#       session_id                - The ID of the background pkgacct session created to package the user. This can be used to stream the pkgacct log
#                                   via live_tail_log.cgi
#       complete_master_log       - The name of the master log after it completes. This can be used to pass into live_tail_log.cgi for streaming.
#       complete_master_error_log - The name of the master error log after it completes. This can be used to pass into live_tail_log.cgi for streaming.
#
sub start_background_pkgacct {
    my ( $user, $args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'user' ] ) if !length $user;

    # We want both of these cases to have the exact same error message. Otherwise, we'd disclose information to the caller.
    if ( !Cpanel::Validate::Username::user_exists($user) || !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
    }

    Cpanel::Validate::LineTerminatorFree::validate_or_die($_) for %$args;

    my ( $session_id, $session_dir );
    my $tries = 0;

    do {
        $session_id  = _generate_session_id($user);
        $session_dir = $Whostmgr::Backup::Pkgacct::Config::SESSION_DIR . "/$session_id";
    } while ( -e $session_dir && ++$tries < $MAX_SESSION_DIR_CREATION_ATTEMPTS );

    if ( -e $session_dir ) {
        die Cpanel::Exception::create( 'NameGenerationFailed', 'The system failed to generate an unused [asis,pkgacct] session ID after “[_1]” attempts.', [$MAX_SESSION_DIR_CREATION_ATTEMPTS] );
    }

    my $log_obj = Whostmgr::Backup::Pkgacct::Logs->new( 'id' => $session_id );

    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            try {

                my $stdout_fh = $log_obj->open_master_log_file();
                my $stderr_fh = $log_obj->open_master_error_log_file();

                my $serv_type = Whostmgr::Whm5::find_WHM_version( Cpanel::Version::Full::getversion() );

                $args->{'serialized_output'} = 1;
                $args->{'servtype'}          = $serv_type;
                $args->{'tarroot'}           = q{''} if !length $args->{'tarroot'};

                my @pkgacct_args = Whostmgr::Whm5::get_pkgcmd_as_array( 'pkgacct', $user, $args );
                my $pkgacct_cmd  = shift @pkgacct_args;

                try {
                    my $run = Cpanel::SafeRun::Object->new_or_die(
                        program => $pkgacct_cmd,
                        args    => \@pkgacct_args,
                        stdout  => $stdout_fh,
                        stderr  => $stderr_fh,

                        timeout      => $Whostmgr::Backup::Pkgacct::Config::SESSION_TIMEOUT,
                        read_timeout => $Whostmgr::Backup::Pkgacct::Config::READ_TIMEOUT,

                        after_fork => sub {
                            my ($pid) = @_;
                            require Cpanel::UPID;
                            Cpanel::Autodie::symlink( Cpanel::UPID::get($pid), "$session_dir/upid" );
                        },
                    );
                }
                catch {
                    Cpanel::Logger->new()->warn( "Background pkgacct failed in execution due to an error: " . Cpanel::Exception::get_string($_) );
                };
            }
            catch {
                Cpanel::Logger->new()->warn( "Background pkgacct did not execute due to an error: " . Cpanel::Exception::get_string($_) );
            }
            finally {
                $log_obj->mark_session_completed();
            };
        }
    );

    return {
        session_id                => $session_id,
        complete_master_log       => $Whostmgr::Backup::Pkgacct::Logs::MASTER_LOG_FILE_NAME,
        complete_master_error_log => $Whostmgr::Backup::Pkgacct::Logs::MASTER_ERROR_LOG_FILE_NAME,
    };
}

sub _generate_session_id {
    my ($user) = @_;

    my $max_template = substr( $user || '', 0, 15 ) . Cpanel::Time::time2condensedtime();

    $max_template =~ s{[^0-9A-Za-z_]}{}g if length $max_template;

    my $rand = Cpanel::Rand::Get::getranddata( 36 - length $max_template, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z' ] );

    return $max_template . $rand;
}

1;
