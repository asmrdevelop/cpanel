package Cpanel::Hulkd::QueuedTasks::Harvester;

# cpanel - Cpanel/Hulkd/QueuedTasks/Harvester.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::Harvester

=head1 SYNOPSIS

    # Should not be used directly. You should always use a subclass instead.
    my @notify_tasks;
    Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester->harvest(
        sub { push @notify_tasks, shift }
    );
    foreach my $ip (@notify_tasks) {
        _do_work($ip);
    }

=head1 DESCRIPTION

A generic subqueue “harvester” module. See subclasses such as
L<Cpanel::Hulkd::QueuedTasks::NotifyLogin> for more detailed documentation.

=cut

use parent qw(
  Cpanel::TaskQueue::SubQueue::Harvester
);

use Cpanel::JSON      ();
use Cpanel::Exception ();

use constant {
    _ENOENT => 2,
};

=head1 METHODS

=head2 I<CLASS>->harvest( CALLBACK )

Removes all items from the queue and calls CALLBACK immediately after
removing each one. The CALLBACK receives the deserialized data from the
JSON blob that was just removed.

This processes the timestamp'ed symlinks instead of the actual job files
in order to ensure that we process the jobs in the order they were queued.

=cut

sub harvest {
    my ( $self, $foreach_cr ) = @_;

    my $dir = $self->todo_dir();

    local $!;

    if ( opendir my $dh, $dir ) {

        #We have to read all of the names at once and then sort
        #because filesystem sorting is not necessarily lexicographical.
        local $! = 0;
        my @time_nodes = readdir($dh);
        if ($!) {
            die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $dir, error => $! ] );
        }

        #Lexicographical sort puts the nodes into the same order
        #in which they were queued. cf. Adder.pm’s _gen_job_name().

        for my $name ( sort @time_nodes ) {
            next if index( $name, '.' ) == 0;

            my $link        = "$dir/$name";
            my $actual_file = readlink($link) or do {
                warn "Failed to process job ($name). Failed to readlink('$link'): $!"
                  if $! != _ENOENT();
                next;
            };
            unlink $link or do {
                warn "Failed to process job ($name). Failed to unlink('$link'): $!"
                  if $! != _ENOENT();
                next;
            };

            eval {
                my $data = Cpanel::JSON::LoadFile($actual_file);
                unlink $actual_file or do {
                    warn "Failed to process job ($name). Failed to unlink('$actual_file'): $!"
                      if $! != _ENOENT();
                    die;
                };
                $foreach_cr->($data);
            };
            warn "Failed to process job ($name): $@"
              if $@;
        }
    }
    else {
        _handle_opendir_err($dir);
    }

    return;
}

sub _handle_opendir_err {
    my ($dir) = @_;

    if ( $! != _ENOENT() ) {
        die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $dir, error => $! ] );
    }

    return;
}

1;
