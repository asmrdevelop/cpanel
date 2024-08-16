
# cpanel - Cpanel/InterfaceLock/Remove.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

package Cpanel::InterfaceLock::Remove

=cut

package Cpanel::InterfaceLock::Remove;

use strict;
use Cpanel::InterfaceLock::Tiny ();
use Cpanel::FileUtils::Dir      ();

=head2 remove_lock

Remove a lock if it exists.

ARGUMENTS

  name - String - name of the lock.
  opts - Hash Ref - with the following properties:
    path - String - optional path to the lock file. If provided the lock path with be
                    <path>/.application-locks. If not provided the lock path
                    defaults to /var/cpanel/.application-locks.
    user - String - optional user. If provided, the lock only applies to this user.

=cut

sub remove_lock {
    my ( $name, $opts ) = @_;
    my $lock_path = Cpanel::InterfaceLock::Tiny::get_lock_path_by_options( $name, $opts );
    if ( -e $lock_path ) {
        return unlink $lock_path;
    }
    return 1;
}

=head2 remove_user_locks

Removes all the locks belonging to the passed in user in the path passed or
the standard path if path is not passed.

ARGUMENTS

  opts - Hash Ref - with the following properties:
    path      - String - optional path to the lock file. If provided the lock path with be
                    <path>/.application-locks. If not provided the lock path
                    defaults to /var/cpanel/.application-locks.
    user      - String - optional user. If provided, the lock only applies to this user.

=cut

sub remove_user_locks {
    my ($opts)      = @_;
    my $user        = $opts->{user};
    my @directories = ( Cpanel::InterfaceLock::Tiny::make_lock_path( $opts->{path} ) );
    @directories = grep { -d $_ } @directories;

    return unless scalar @directories;

    my $user_colon_line_end        = ":$user";
    my $user_colon_line_end_length = length $user_colon_line_end;
    foreach my $check_dir (@directories) {
        foreach my $node ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($check_dir) } ) {
            next                      if $user_colon_line_end ne substr( $node, -1 * $user_colon_line_end_length );
            unlink "$check_dir/$node" if -f "$check_dir/$node";
        }
    }
    return;
}

1;
