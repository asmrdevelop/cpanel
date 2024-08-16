package Cpanel::Hulkd::QueuedTasks::Adder;

# cpanel - Cpanel/Hulkd/QueuedTasks/Adder.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::Adder

=head1 SYNOPSIS

    # Should not be used directly. You should always use a subclass instead.
    Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder->add($json_string);

=head1 DESCRIPTION

A generic subqueue “adder” module. See subclasses such as
L<Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser> for more detailed documentation.

=cut

use parent qw(
  Cpanel::TaskQueue::SubQueue::Adder
);

use Cpanel::Exception        ();
use Cpanel::Hash             ();
use Cpanel::JSON             ();
use Cpanel::TimeHiRes        ();
use Cpanel::FileUtils::Write ();

use constant {
    _ENOENT => 2,
    _EEXIST => 17,
};

=head1 METHODS

=head2 I<CLASS>->add($data_hr)

Creates a job for the data passed in.

The JSON-serialization of C<$data_hr> is hashed (C<Cpanel::Hash::get_fastest_hash()>)
and the hash is used as the job's filename to ensure that
duplicate data is not queued.

To preserve the 'order' in which items are harvested,
it also creates a timestamp'ed symlink to the actual
job file.

=cut

sub add {
    my ( $class, $data_hr ) = @_;

    my $json_string = Cpanel::JSON::canonical_dump($data_hr);
    my $job_name    = Cpanel::Hash::get_fastest_hash($json_string);

    # Creates the directory if it doesn't exist
    # SUPER::add() returns 0 if the file already exists -
    # in which case we do not need to queue a new item,
    # as it will be a dupe.
    return 0 if $class->SUPER::add($job_name) == 0;

    my $job_file = $class->_DIR() . '/' . $job_name;
    Cpanel::FileUtils::Write::overwrite( $job_file, $json_string );

    my $created_dir;

    for ( 1 .. 10 ) {
        my $link_path = $class->todo_dir() . '/' . _gen_job_name();
        last if symlink( $job_file, $link_path );

        if ( $! == _ENOENT() ) {
            if ( !$created_dir ) {
                require Cpanel::Mkdir;
                Cpanel::Mkdir::ensure_directory_existence_and_mode(
                    $class->todo_dir(),
                    $class->_DIR_MODE(),
                );
                $created_dir = 1;
                next;
            }
        }
        elsif ( $! == _EEXIST ) {
            Cpanel::TimeHiRes::sleep(0.001);
            next;
        }

        die Cpanel::Exception::create( 'IO::SymlinkCreateError', [ oldpath => $job_file, newpath => $link_path, error => $! ] );
    }

    return 1;
}

#
# Same as Directory::Queue::_name()
#
# return the name of a new element to (try to) use with:
#  - 8 hexadecimal digits for the number of seconds since the Epoch
#  - 8 hexadecimal digits for the nanoseconds part
#  - 1 random hexadecimal digit to further reduce name collisions
#
# properties:
#  - fixed size (17 hexadecimal digits)
#  - likely to be unique (with very high-probability)
#  - can be lexically sorted
#  - ever increasing (for a given process)
#  - reasonably compact
#  - matching $_ElementRegexp
#
sub _gen_job_name {
    return sprintf(
        "%08x%08x%01x",
        Cpanel::TimeHiRes::clock_gettime(),
        int( rand(16) )
    );
}

1;
