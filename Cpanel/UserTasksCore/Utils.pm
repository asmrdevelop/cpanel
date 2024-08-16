package Cpanel::UserTasksCore::Utils;

# cpanel - Cpanel/UserTasksCore/Utils.pm           Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::UserTasksCore::Utils

=head1 SYNOPSIS

    use Cpanel::UserTasksCore::Utils ();

    Cpanel::UserTasksCore::Utils::queue_dir();

=head1 DESCRIPTION

Shared tools for C<Cpanel::UserTasks>.

=cut

=head2 $QUEUE_DIR

The queue is contained within the user's home directory, in a
subdirectory which is held within the C<$QUEUE_DIR> variable.  Default
value is '/.cpanel/user_tasks'.

=cut

use cPstrict;

use Cpanel::PwCache  ();
use File::Path::Tiny ();

our $QUEUE_DIR = '/.cpanel/user_tasks';

=head1 METHODS

=head2 queue_dir()

Returns the directory to use for the UserTasks queue.

=cut

sub queue_dir() {
    my $home = $Cpanel::homedir || $Cpanel::homedir || Cpanel::PwCache::gethomedir($>) or die;
    my $dir  = $home . $QUEUE_DIR;

    if ( !-d $dir ) {
        File::Path::Tiny::mk($dir) or die;
    }

    return $dir;
}

1;
