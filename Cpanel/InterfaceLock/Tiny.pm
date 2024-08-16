
# cpanel - Cpanel/InterfaceLock/Tiny.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::InterfaceLock::Tiny;

use strict;
our $DEFAULT_LOCK_BASE_PATH = '/var/cpanel/';
our $LOCK_DIRECTORY         = '.application-locks/';

=head1 STATIC METHODS

=head2 lock_exists

Checks if the lock is in place given the lock name and optionally the lock path.

ARGUMENTS

  name          - String - name of the lock.
  opts          - Hash Ref - with the following properties:
    path            - String - optional path to the lock file. If provided the lock path with be
                                <path>/.application-locks. If not provided the lock path
                                defaults to /var/cpanel/.application-locks.
    user            - String - optional user. If provided, the lock only applies to this user.
    expire_time     - String - optional number of seconds from the mtime of the lock file that it should
                                be considered expired

=cut

sub lock_exists {
    my ( $name, $opts ) = @_;
    my $lock_path = get_lock_path_by_options( $name, $opts );

    # If the lock file exists, but we were given an expiration time to check against, expire the lock and carry on
    if ( defined( $opts->{'expire_time'} && -e $lock_path ) ) {
        my $lock_mtime = ( stat(_) )[9];
        if ( ( ( time - $lock_mtime ) > $opts->{'expire_time'} ) ) {

            # May or may not be successful depending on the user calling it, but we try to clean it up regardless
            unlink $lock_path;
            return 0;
        }
    }
    return -e $lock_path ? 1 : 0;
}

=head2 get_lock_path

Returns the full path to the lock.

ARGUMENTS

  name      - String - name of the lock.
  path      - String - optional path to the lock file. If provided the lock path with be
                  <path>/.application-locks. If not provided the lock path
                  defaults to /var/cpanel/.application-locks.

=cut

sub get_lock_path {
    my ( $name, $path ) = @_;
    my $lock_path = make_lock_path($path) . $name;
    return $lock_path;
}

=head2 get_lock_path_for_user

Returns the full path to the lock.

ARGUMENTS

  name - String - name of the lock.
  user - String - name of the user for a user based application lock.
  path - String - optional path to the lock file. If provided the lock path with be
                  <path>/.application-locks. If not provided the lock path
                  defaults to /var/cpanel/.application-locks.

=cut

sub get_lock_path_for_user {
    my ( $name, $user, $path ) = @_;
    my $lock_path = make_lock_path($path) . $name . ':' . $user;
    return $lock_path;
}

=head2 get_lock_path_by_options

Returns the full path to the lock based on the options.

ARGUMENTS

  name - String - name of the lock.
  opts - Hash Ref - with the following properties:
    path      - String - optional path to the lock file. If provided the lock path with be
                         <path>/.application-locks. If not provided the lock path
                         defaults to /var/cpanel/.application-locks.
    user      - String - optional user. If provided, the lock only applies to this user.

RETURNS

  string - Path to the lock file.

=cut

sub get_lock_path_by_options {
    my ( $name, $opts ) = @_;

    my $lock_path;
    if ( !$opts ) {
        $lock_path = get_lock_path($name);
    }
    elsif ( $opts->{user} ) {
        $lock_path = get_lock_path_for_user( $name, $opts->{user}, $opts->{path} );
    }
    elsif ( $opts->{path} ) {
        $lock_path = get_lock_path( $name, $opts->{path} );
    }

    return $lock_path;
}

sub make_lock_path {
    my ($path) = @_;
    $path = $DEFAULT_LOCK_BASE_PATH if !$path;
    $path .= '/' if $path !~ m/\/$/;
    $path .= $LOCK_DIRECTORY;
    return $path;
}

1;
