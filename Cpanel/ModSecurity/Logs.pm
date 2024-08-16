
# cpanel - Cpanel/ModSecurity/Logs.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ModSecurity::Logs;

use strict;
use warnings;

use File::Basename ();
use File::Find     ();
use File::Path     ();

use Cpanel::AccessIds          ();
use Cpanel::PwCache            ();
use Cpanel::FileUtils::Copy    ();
use Cpanel::FileUtils::Link    ();
use Cpanel::Logd               ();
use Cpanel::Logs               ();
use Cpanel::PwCache            ();
use Cpanel::Config::User::Logs ();
use Cpanel::Exception          ();
use POSIX                      ();

my $cpconf;

=head1 NAME

Cpanel::ModSecurity::Logs

=head1 DESCRIPTION

This module implements useful routines for manipulation of per-user ModSecurity logs.

=head1 CONSTANTS

=head2 $MODSECURITY_LOG_ROOT

The directory tree where per-user ModSecurity logs are kept

=head1 SUBROUTINES

=head2 archive_logs( user )

=head3 Description

Archive a user's ModSecurity logs.

=head3 Arguments

  - user: The user whose logs are to be archived

=head3 Returns

Returns 1 if the archiving succeeded, 0 if failed (probably because of quota
problems)

=head2 remove_modsecurity_logs( user )

=head3 Description

Delete a user's ModSecurity per-user logs

=head3 Arguments

  - user: The user whose logs are to be archived

=head3 Returns

  undef

=head2 user_logdir_is_safe( user )

=head3 Description

Checks the existence, filesystem type and ownership of a user's modsec_audit directory.

=head3 Arguments

  - user: The user to check

=head3 Returns

Return 1 is safe, 0 if not.

=head2 _get_modsecurity_log_directory

=head3 Description

Returns the location of the ModSecurity per-user log tree. Useful for
mocking in tests.

=head3 Arguments

None.

=head3 Returns

Returns the value of $MODSECURITY_LOG_ROOT.

=cut

my $MODSECURITY_LOG_ROOT = '/usr/local/apache/logs/modsec_audit';
our @MonthName = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub archive_logs {
    my ( $user, $cpuser_ref ) = @_;

    my $directory_to_archive = _get_modsecurity_log_directory() . "/$user";
    return 1 if ( !-e $directory_to_archive );

    return 0 unless user_logdir_is_safe($user);

    my $homedir = Cpanel::PwCache::gethomedir($user);

    return 0 if ( !Cpanel::Logd::checkDiskSpaceOk( $user, $homedir ) );

    my ( $day, $month, $year ) = (localtime)[ 3, 4, 5 ];    # use $day later
    my $archive_name = _get_archive_name( $user, $month, $year );
    my $archive_dir  = _get_home_archive_directory($homedir);
    my $archive_file = qq{$archive_dir/$archive_name};

    my $archive_backup_file = $archive_file . '.backup';
    my $ret                 = Cpanel::AccessIds::do_as_user(
        $user,
        sub {
            my $success = 1;

            if ( -f $archive_file ) {
                Cpanel::FileUtils::Copy::safecopy( $archive_file, $archive_backup_file );
            }

            File::Find::find(
                {
                    wanted => sub {
                        if ( $_ !~ /\.offset$/ && -f $_ ) {
                            if ( !Cpanel::Logs::archive_file( $File::Find::name, $archive_file, $user ) ) {
                                $success = 0;
                            }
                        }
                    },
                    no_chdir => 1,
                },
                $directory_to_archive
            );

            if ( !$success ) {
                rename( $archive_backup_file, $archive_file );
            }
            Cpanel::FileUtils::Link::safeunlink($archive_backup_file);

            return $success;
        }
    );

    return $ret if not $ret;    # preserve behavior if the above archiving fails for some reason

    my ( $archive_ok, $remove_ok ) = Cpanel::Config::User::Logs::load_users_log_config( [ Cpanel::PwCache::getpwnam($user) ] );    # prefers cPanel setting, falls back to tweak setting
    return $ret if not $remove_ok;                                                                                                 # $archive_ok is necessarily captured, but not used here

    $ret = remove_user_archives( { day => $day, month => $month, year => $year, user => $user, archive_name => $archive_name, archive_dir => $archive_dir } );

    return $ret;
}

sub _get_home_archive_directory {
    my $homedir = shift;
    return qq{$homedir/logs};
}

sub _get_archive_name {
    my ( $user, $month, $year ) = @_;
    my $archive_name = 'modsec2_' . $user . '_' . $MonthName[$month] . '_' . ( $year + 1900 ) . '.gz';
    return $archive_name;
}

sub remove_user_archives {
    my $opts         = shift;
    my $day          = $opts->{day};
    my $month        = $opts->{month};
    my $year         = $opts->{year};
    my $user         = $opts->{user};
    my $archive_name = $opts->{archive_name};
    my $archive_dir  = $opts->{archive_dir};

    # Handle the event the month is january, due to us using strftime rather than DateTime
    my $month_adjusted = $month == 0 ? 11 : $month - 1;

    # Handle garbage input - if cPanel is still a thing in 3800AD, change this to % 3800, lol
    my $year_adjusted = ( $year % 1900 ) - 1;

    my $prev_month        = int POSIX::strftime( "%m", 0, 0, 2, 1, $month_adjusted, $year_adjusted );
    my $prev_year         = int POSIX::strftime( "%Y", 0, 0, 2, 1, $month_adjusted, $year_adjusted );
    my $prev_archive_name = _get_archive_name( $user, $prev_month, $prev_year );

    my $keep = {
        "$archive_name"      => 1,
        "$prev_archive_name" => 1,
    };

    opendir my $dh, $archive_dir or die Cpanel::Exception::create( 'IO::FileOpenError', 'The system could not open “[_1]” to remove old ModSecurity logs.', [$archive_dir] );

  CHECK_AND_UNLINK:
    while ( my $item = readdir($dh) ) {
        chomp $item;
        next CHECK_AND_UNLINK if $item !~ m/^modsec2_/;    # we only care obout modsec2_ related files
        if ( not defined $keep->{$item} ) {
            unlink qq{$archive_dir/$item};
        }
    }
    close $dh;

    return 1;
}

sub remove_modsecurity_logs {
    my $user = shift;

    return unless user_logdir_is_safe($user);

    my $directory_to_clean = _get_modsecurity_log_directory() . "/$user";
    Cpanel::AccessIds::do_as_user(
        $user,
        sub {
            chdir "/tmp";
            if ( -e $directory_to_clean ) {
                File::Path::remove_tree( $directory_to_clean, { safe => 1, keep_root => 1 } );
            }
        }
    );

    # Specified keep_root on the remove_tree because inside the do_as_user the process
    # won't have permission to remove the top directory (since its parent is not owned
    # by the user). Just do a final rmdir as root here to take care of that.
    rmdir $directory_to_clean;

    return;
}

sub user_logdir_is_safe {
    my $user = shift;

    return 0 unless defined $user && length $user;

    my $user_logdir = _get_modsecurity_log_directory() . "/$user";
    my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];

    return 0 unless defined $uid && defined $gid;

    my @st = lstat($user_logdir);
    if ( -d _ && $st[4] == $uid && $st[5] == $gid ) {
        return 1;
    }
    return 0;
}

sub _get_modsecurity_log_directory {

    return $MODSECURITY_LOG_ROOT;
}

1;
