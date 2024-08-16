package Cpanel::SafeFile::LockInfoCache;

# cpanel - Cpanel/SafeFile/LockInfoCache.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFileLock ();

=encoding utf-8

=head1 NAME

Cpanel::SafeFile::LockInfoCache

=head1 SYNOPSIS

    my $lock_cache = Cpanel::SafeFile::LockInfoCache->new($lockfile);

    my $rec = $lock_cache->get( $inode );

    my ($pid, $procname, $debug) = @$rec if $rec;

=head1 DESCRIPTION

This object caches the lookup of lock file contents for L<Cpanel::SafeFile>.

B<IMPORTANT:> See L<Cpanel::SafeFile::LockWatcher> for information
about how filesystems assign inode numbers.

=head1 METHODS

=head2 I<CLASS>->new( LOCKFILE_PATH )

Instantiates the object.

=cut

sub new {
    my ( $class, $pathname ) = @_;

    die 'need path!' if !$pathname;

    return bless { _path => $pathname }, $class;
}

=head2 $record_ar = I<OBJ>->get( $INODE, $MTIME )

Fetches the lock contents by inode number and mtime. The return is one of:

=over

=item * undef - If the object’s LOCKFILE_PATH hasn’t existed by the
given INODE.

=item * An array reference of:

=over

=item * The process ID (PID)

=item * The process name (i.e., C<$0>)

=item * debugging information, if any is saved with the lock

=back

=back

=cut

sub get {
    my ( $self, $inode, $mtime ) = @_;

    die 'Need an inode & an mtime!' if !defined $inode || !defined $mtime;

    if ( !exists $self->{"_inode_${inode}_$mtime"} ) {
        my ( $pid, $name, $obj, $fh ) = Cpanel::SafeFileLock::fetch_lock_contents_if_exists( $self->{'_path'} );

        #Only set a value if we got lock contents back.
        if ($pid) {

            #We want to set the values in the cache for the actual inode.
            #Even if we just queried with an outdated inode, we’re not
            #unlikely to query on the new inode shortly here.
            my ( $real_inode, $real_mtime ) = ( stat $fh )[ 1, 9 ];
            $self->{"_inode_${real_inode}_$real_mtime"} = [ $pid, $name, $obj ];
        }
    }

    return $self->{"_inode_${inode}_$mtime"} ||= undef;
}

1;
