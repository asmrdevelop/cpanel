package Cpanel::CloudLinux::CageFS;

# cpanel - Cpanel/CloudLinux/CageFS.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::CloudLinux::CageFS - Utility functions related to CloudLinux CageFS

=head1 SYNOPSIS

  use Cpanel::CloudLinux::CageFS ();

  my $cagefs_is_enabled = Cpanel::CloudLinux::CageFS::is_enabled();

  foreach my $user ( Cpanel::CloudLinux::CageFS::enabled_users() ) {
      ...
  }

  if ( Cpanel::CloudLinux::CageFS::is_enabled_for_user($user) ) {
      ...
  }

=head1 NOTES

It is not strictly necessary to check the status of L</"is_enabled()"> before calling the L</"enabled_users()"> or L</"is_enabled_for_user($user)"> functions.
When CageFS is not installed or is disabled system-wide these functions will return an empty list or report that the user is disabled, respectively.

=cut

use cPstrict;

use Cpanel::CachedCommand   ();
use Cpanel::FileUtils::Dir  ();
use Cpanel::SafeRun::Object ();

use constant {
    CAGEFSCTL                    => '/usr/sbin/cagefsctl',
    CAGEFSCTL_ENABLED_ARGS       => ['--cagefs-status'],
    CAGEFSCTL_ENABLED_USERS_ARGS => ['--list-enabled'],
    CAGEFS_ETC_DIR               => '/etc/cagefs',
    CAGEFS_VAR_DIR               => '/var/cagefs',
    CAGEFS_SHARE_DIR             => '/usr/share/cagefs',
    MAX_CACHE_AGE                => 3540,                    # 59 minutes
};

use constant {
    CAGEFS_ENABLED_USERS_DIR  => CAGEFS_ETC_DIR() . '/users.enabled',
    CAGEFS_DISABLED_USERS_DIR => CAGEFS_ETC_DIR() . '/users.disabled',
};

=head1 FUNCTIONS

=head2 is_enabled()

Returns C<0> if CageFS is disabled, and C<1> if CageFS is enabled.

=cut

sub is_enabled () {
    return 0 unless -x CAGEFSCTL();

    my $result_cr = Cpanel::CachedCommand::cachedcommand_no_errors( 'binary' => CAGEFSCTL(), 'args' => CAGEFSCTL_ENABLED_ARGS(), 'mtime' => _latest_status_timestamp(), 'ttl' => MAX_CACHE_AGE() );
    return ( ref $result_cr eq 'SCALAR' && index( ${$result_cr}, 'Enabled' ) == 0 ) ? 1 : 0;
}

=head2 enabled_users()

Returns a list of all users that have CageFS enabled.
If you only need to check a few users or require the most up-to-date CageFS status for a user at any given time, consider using L</"is_enabled_for_user($user)"> instead.

=cut

sub enabled_users () {
    return unless is_enabled();
    my @enabled;

    my $result_cr = Cpanel::CachedCommand::cachedcommand_no_errors( 'binary' => CAGEFSCTL(), 'args' => CAGEFSCTL_ENABLED_USERS_ARGS(), 'mtime' => _latest_users_timestamp(), 'ttl' => MAX_CACHE_AGE() );
    if ( ref $result_cr eq 'SCALAR' && defined ${$result_cr} ) {
        @enabled = split( /\n/, ${$result_cr} );

        # Check first line and throw away "123 enabled user(s)"
        if ( @enabled && $enabled[0] =~ m{\A\d+ \s+ enabled}xms ) {
            shift @enabled;
        }
    }
    return @enabled;
}

=head2 is_enabled_for_user($user)

Returns C<1> if CageFS is enabled for C<$user>, or C<0> if disabled.
This has some overhead each time it is called to be sure the user's status is up-to-date (but is much faster than calling cagefsctl directly), so if you want to avoid any overhead consider grabbing the L</"enabled_users()"> list instead.

=cut

sub is_enabled_for_user ($user) {
    return 0 unless is_enabled();
    state $last = 0;
    state %users;

    my $current = _latest_users_timestamp();
    if ( $last != $current ) {
        %users = map { $_ => 1 } enabled_users();
        $last  = $current;
    }
    return $users{$user} ? 1 : 0;
}

=head2 force_cagefs_update()

This calls the cagefsctl script using the '--force-update' option in order to update cagefs for
all users on the system.

NOTE:  It is safe to call if cagefs is not installed/enabled as it will just be a noop

=cut

sub force_cagefs_update {
    return 0 unless Cpanel::CloudLinux::CageFS::is_enabled();

    my $run = Cpanel::SafeRun::Object->new(
        program => CAGEFSCTL(),
        args    => ['--force-update'],
    );

    if ( $run->CHILD_ERROR() ) {
        require Cpanel::Logger;
        my $logger = Cpanel::Logger->new();

        my $out = $run->stdout() . $run->stderr();
        $logger->info("Cpanel::CloudLinux::CageFS::force_cagefs_update -- Failed to update CageFS: $out");
    }

    return;
}

sub _latest_status_timestamp {

    # CAGEFS_ETC_DIR modify+change timestamps are updated when CageFS is enabled or disabled.
    return _latest_mtime_ctime( CAGEFS_ETC_DIR() );
}

sub _latest_users_timestamp {

    # We must check the timestamps on all of the enabled (or disabled) user subdirs (not the individual user files) to detect that a change has occurred with 100% reliability and that the cache needs to be refreshed.
    # There may be anywhere between 2 and 102 stat calls as a result of this. Even so, the performance with a fresh cache is ~1700 times faster (0.4ms per call) vs. executing cagefsctl every time (700ms per call).
    return _latest_mtime_ctime( _latest_users_dirs() );
}

sub _latest_users_dirs {

    # One of CAGEFS_{ENABLED,DISABLED}_USER_DIR will exist depending on CageFS user mode (cagefsctl --display-user-mode).
    # That dir is dynamically split into up to 100 subdirs using only the *last two* digits of the user ID.
    state $last_ts = 0;
    state @dirs;
    foreach my $dir ( CAGEFS_ENABLED_USERS_DIR(), CAGEFS_DISABLED_USERS_DIR() ) {
        my $current_ts = _latest_mtime_ctime($dir);
        if ( $current_ts > $last_ts && ( my $nodes = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($dir) ) ) {
            @dirs    = ( $dir, map { $dir . q{/} . $_ } @{$nodes} );    # Convert to absolute paths
            $last_ts = $current_ts;
            last;
        }
    }
    return @dirs;
}

sub _latest_mtime_ctime (@paths) {
    my $latest = 0;
    foreach my $path (@paths) {
        my ( $mtime, $ctime ) = ( stat($path) )[ 9, 10 ];
        if ( $mtime && $mtime > $latest ) {
            $latest = $mtime;
        }
        if ( $ctime && $ctime > $latest ) {
            $latest = $ctime;
        }
    }
    return $latest;
}

1;
