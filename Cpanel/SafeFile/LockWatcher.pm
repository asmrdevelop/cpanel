package Cpanel::SafeFile::LockWatcher;

# cpanel - Cpanel/SafeFile/LockWatcher.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant _ENOENT => 2;

use constant _FILEHANDLE_TTL => 2;

=encoding utf-8

=head1 NAME

Cpanel::SafeFile::LockWatcher - state for watching a Cpanel::SafeFile lock

=head1 SYNOPSIS

    my $watcher = Cpanel::SafeFile::LockWatcher( $lockfile_path );

    $watcher->reload_from_disk();

    #For speed, these are documented for direct access.
    $watcher->{'inode'};
    $watcher->{'uid'};
    $watcher->{'mtime'};
    $watcher->{'size'};

    #1 if the file at the penultimate stat() was different from the last one
    #0 if the file did not change in that time
    #This includes changes from or to a state of nonexistence.
    $watcher->{'changed'};

    $watcher->can_access_lock();

=head1 DESCRIPTION

This is an attempt to modularize some of the lock-watching logic in
L<Cpanel::SafeFile>.

=head1 OF INODES AND FILEHANDLES

Inode numbers aren’t like PIDs. PIDs are assigned in a round-robin,
so you can compare two PIDs and be reasonably sure that, if they match,
they’re the same process. Inode numbers, though, are reassigned
IMMEDIATELY. So if you do this:

    open $fh, '>', 'foo';                   #1
    printf "inode 1: %d\n", (stat $fh)[1];

    open $fh, '>', 'foo.moveme';            #2
    printf "inode 2: %d\n", (stat $fh)[1];
    rename 'foo.moveme' => 'foo';           #3

    open $fh, '>', 'foo.moveme';            #4
    printf "inode 3: %d\n", (stat $fh)[1];

… the third inode printed is not unlikely to be the same inode as
the first. That’s because when you create the 2nd C<foo.moveme> (step 4
above), the filesystem reuses the inode that you freed up when you clobbered
the first C<foo> file (created at step 1, clobbered at step 3).

For this reason, this module always C<open()>s the files that it watches
and holds onto the file handles. (They’re indexed by inode number so we
don’t hold multiple file handles to the same inode.) This guarantees that
the C<change> flag is accurate and that, over the lifetime of this object,
no inode that we’ve watched will be reused.

B<UPDATE:> As of v70, we switched this to hold onto only the most recent
file handle rather than holding onto every file handle. That solves problems
with high contention that we’ve seen. It’s not important (we think?!?) that
inodes *never* get reused; we just need to make sure that the one we compare
against hasn’t been reused since we last open()ed it.

B<UPDATE:> As of v82, we noticed that the above-described change from v70
undermines L<Cpanel::SafeFile::LockInfoCache>’s fundamental assumption:
that an inode will always refer to the same file over its lifetime and thus
may be used as an index. To provide for an index that also avoids the
filehandles-limit problem that v70’s change addressed, C::SF::LIC now indexes
on both inode *and* mtime. and this file retains filehandles for up to
2 seconds. This way filesystems that lack high-resolution timestamp support
will work.

=head1 METHODS

=head2 I<CLASS>->new( LOCKFILE_PATH )

Instantiates the object.

=cut

sub new {
    my ( $class, $lockfile ) = @_;

    my $self = bless { _path => $lockfile, _new => 1 }, $class;

    return $self->reload_from_disk();
}

=head2 I<OBJ>->reload_from_disk()

Does a C<stat()> on the lockfile path and updates the
C<inode>, C<uid>, C<size>, and C<mtime> properties as well as the
value of C<changed>. Returns the I<OBJ>.

=cut

sub reload_from_disk {
    my ($self) = @_;

    my $old_inode = $self->{'inode'};
    @{$self}{qw( inode  uid  size mtime)} = $self->_get_inode_uid_size_mtime();

    if ( delete $self->{'_new'} ) {
        $self->{'changed'} = 0;
    }
    else {
        $self->{'changed'} = ( $self->{'inode'} || 0 ) != ( $old_inode || 0 ) ? 1 : 0;
    }

    return $self;
}

sub _get_inode_uid_size_mtime {
    my ($self) = @_;

    my ( $inode, $uid, $size, $mtime );

    local $!;

    if ( open my $fh, '<', $self->{'_path'} ) {
        ( $inode, $uid, $size, $mtime ) = ( stat $fh )[ 1, 4, 7, 9 ];

        #If $self->{'_path'} is the same file that it was before,
        #then we’ll close the old file handle. By virtue of holding
        #onto this filehandle we’ll ensure that the filesystem doesn’t
        #reclaim the inode, and the inode number won’t be reused, so
        #the inode number will be a reliable indicator of whether the
        #path has changed.
        $self->_add_fh_if_needed( $fh, $inode );
    }
    elsif ( $! != _ENOENT ) {
        die "open(<, $self->{'_path'}): $!";
    }

    return ( $inode, $uid, $size, $mtime );
}

sub _add_fh_if_needed {
    my ( $self, $fh, $inode ) = @_;

    my $now        = time;
    my $fhs_hr     = $self->{'_time_fhs'} //= {};
    my $seen_inode = 0;

    for my $time ( keys %$fhs_hr ) {

        # Reap any filehandles that have been in this object for
        # more than _FILEHANDLE_TTL() seconds.
        if ( ( $now - $time ) > _FILEHANDLE_TTL() ) {
            delete $fhs_hr->{$time};
            next;
        }

        # Before we hold onto $fh, ensure that it’s not the same
        # inode as any other filehandle that we have open.
        if ( !$seen_inode ) {
            foreach my $entry ( @{ $fhs_hr->{$time} } ) {
                if ( $entry->[1] == $inode ) {
                    $seen_inode = 1;
                    last;
                }
            }
        }
    }

    # we already have this inode open in one of the time
    # slots so we do not store it again
    return if $seen_inode;

    # Now we hold onto that filehandle.
    # (We call time() again so that we get the latest time possible.)
    push @{ $fhs_hr->{ time() } }, [ $fh, $inode ];

    return;
}

1;
