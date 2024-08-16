package Cpanel::SafeFileLock;

# cpanel - Cpanel/SafeFileLock.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

################################################################################
#
#   NOTE: This module does not perform file locking as expected.
#   See CPANEL-36074 for details.
#
#   If you need file locking, please use Cpanel::Transaction::*
#   instead as it does all the magic for you.
#
################################################################################

use constant {
    _ENOENT => 2,
    _EDQUOT => 122,
    DEBUG   => 0,

    MAX_LOCKFILE_SIZE => 8192,
};

##
## MEMORY REQUIREMENTS: this module is loaded into libexec/queueprocd
## Do not add new dependencies
##

#The $fh (filehandle) argument is optional.
sub new {
    my ( $class, $path_to_lockfile, $fh, $path_to_file_being_locked ) = @_;

    if ( scalar @_ != 4 ) {
        die 'Usage: Cpanel::SafeFileLock->new($path_to_lockfile, $fh, $path_to_file_being_locked)';
    }

    #Write out the PID and the program name to the filehandle.
    #
    #NB: The fact that this is done here seems a bit of tight coupling
    #since, with the change in COBRA-5214, we no longer necessarily want
    #to write anything to this filehandle on instantiation. So, we have
    #set_filehandle() to work around this.
    if ($fh) {
        write_lock_contents( $fh, $path_to_lockfile ) or return;
    }

    # The mtime must be stored AFTER the syswrite that happens in write_lock_contents()
    # or we will get an attempt to unlock file that was locked by another process because
    # the mtime could be off by one (time between the syswrite and stat)

    my $self = bless [
        $path_to_lockfile,
        $fh,
        $path_to_file_being_locked,
    ], $class;

    # Set the inode and mtime in the object
    push @$self, @{ $self->stat_ar() }[ 1, 9 ];

    return $self;
}

sub new_before_lock {
    my ( $class, $path_to_lockfile, $path_to_file_being_locked ) = @_;

    if ( scalar @_ != 3 ) {
        die 'Usage: Cpanel::SafeFileLock->new_before_lock($path_to_lockfile, $path_to_file_being_locked)';
    }

    # The mtime must be stored AFTER the syswrite that happens in write_lock_contents()
    # or we will get an attempt to unlock file that was locked by another process because
    # the mtime could be off by one (time between the syswrite and stat)
    #
    # When using new_before_lock the caller must always call
    # set_filehandle_after_lock() to ensure the mtime is set
    return bless [
        $path_to_lockfile,
        undef,
        $path_to_file_being_locked,
    ], $class;
}

# $_[0] = self
# $_[1] = file handle
# $_[2] = unlinker
sub set_filehandle_and_unlinker_after_lock {

    # set file handle
    $_[0][1] = $_[1];

    # Set the inode and mtime in the object
    push @{ $_[0] }, @{ $_[0]->stat_ar() }[ 1, 9 ];

    # set unlinker
    $_[0][5] = $_[2];
    return $_[0];
}

sub get_path {
    return $_[0]->[0];
}

sub get_path_to_file_being_locked {
    return $_[0]->[2] // die "get_path_to_file_being_locked requires the object to be instantiated with the path_to_file_being_locked";
}

#A kludge to get around the tight coupling between SafeFile and this module.
#See above re syswrite.
sub set_filehandle {
    $_[0][1] = $_[1];
    return $_[0];
}

sub get_filehandle {
    return $_[0]->[1];
}

sub get_inode {
    return $_[0]->[3];
}

sub get_mtime {
    return $_[0]->[4];
}

sub get_path_fh_inode_mtime {
    return @{ $_[0] }[ 0, 1, 3, 4 ];
}

#Does a stat() on the filehandle or, if the filehandle is closed,
#the filesystem path.
sub stat_ar {
    return [ stat( ( $_[0]->[1] && fileno( $_[0]->[1] ) ) ? $_[0]->[1] : $_[0]->[0] ) ];
}

#Does a stat() on the filehandle or, if the filehandle is closed,
#an lstat() on the filesystem path.
sub lstat_ar {

    # Cannot lstat a filehandle
    return [ $_[0]->[1] && fileno( $_[0]->[1] ) ? stat( $_[0]->[1] ) : lstat( $_[0]->[0] ) ];
}

sub close {

    #This will always be true, even if the filehandle is closed,
    #but for now this class just copies logic that's already in place.
    return close $_[0]->[1] if ref $_[0]->[1];

    # trigger the unlinker
    # only after the lock is released
    # so we can defer the unlink operation
    # until after
    $_[0]->[5] = undef;

    return;
}

#----------------------------------------------------------------------
# Non-class functions:

sub write_lock_contents {    ## no critic qw(Subroutines::RequireArgUnpacking) -- only unpack on the failure case
                             # We want to optimize locking as much as possible since it blocks
                             # so many operations on the system.  The more time we spend in the locking
                             # code, the more the user has to suffer with contention
                             # We try to return right away
                             # if the syswrite is successful
    local $!;

    # Since DEBUG is a constant this block will be optimized
    # out most of the time
    if (DEBUG) {
        require Cpanel::Carp;
        return 1 if syswrite( $_[0], "$$\n$0\n" . Cpanel::Carp::safe_longmess() . "\n" );
    }
    return 1 if syswrite( $_[0], "$$\n$0\n" );

    # At this point the syswrite failed and we cleanup
    # and throw an exception
    my ( $fh, $path_to_lockfile ) = @_;
    my $write_error = $!;

    CORE::close($fh);
    unlink $path_to_lockfile;

    # Cpanel::Email::Accounts expects to be able to examine
    # error in the object.  If the exception type is ever
    # changed here, it must allow ->get('error')
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'IO::FileWriteError', [ 'path' => $path_to_lockfile, 'error' => $write_error ] );
}

sub fetch_lock_contents_if_exists {
    my ($lockfile) = @_;

    die 'Need lock file!' if !$lockfile;

    open my $lockfile_fh, '<:stdio', $lockfile or do {
        return if $! == _ENOENT();

        die "open($lockfile): $!";
    };

    my $buffer;
    my $read_result = read( $lockfile_fh, $buffer, MAX_LOCKFILE_SIZE );

    # CPANEL-16932:
    # Handle empty lock files that should never exists since we rename them in place
    # Empty lock file are likely the result of a system crash or disk corruption
    # In this case we return undef so SafeFile can handle these
    if ( !defined $read_result ) {
        die "read($lockfile): $!";
    }

    my ( $pid_line, $lock_name, $lock_obj ) = split( /\n/, $buffer, 3 );
    chomp($lock_name) if length $lock_name;
    my ($lock_pid) = $pid_line && ( $pid_line =~ m/(\d+)/ );

    return ( $lock_pid, $lock_name || 'unknown', $lock_obj || 'unknown', $lockfile_fh );
}

#----------------------------------------------------------------------

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SafeFileLock - Class for storing file lock data

=head1 DESCRIPTION

This class is a thin wrapper around file locks. The class provides
accessor methods so it’s clearer what’s going on when we access
components of the lock.

IMPORTANT: This class should be backward-compatible with code that expects to
mine file locks as array references.

NOTE: This module does not perform file locking as expected. See CPANEL-36074
for details.  If you need file locking, please use Cpanel::Transaction::* instead
as it does all the magic for you.

=head1 SYNOPSIS

    use Cpanel::SafeFileLock ();

    #NB: This will write out a bit of identifying information to the $fh.
    my $lock_obj = Cpanel::SafeFileLock->new($path_to_lockfile, $fh, $path_to_file_being_locked);

    my $path_from_lock = $lock_obj->get_path();

    my $path_to_file_being_locked = $lock_obj->get_path_to_file_being_locked();

    my $fh_from_lock = $lock_obj->get_filehandle();

    my $inode = $lock_obj->get_inode();

    my $mtime = $lock_obj->get_mtime();

    #----------------------------------------------------------------------
    #The following exists as a regular function, not a method:
    Cpanel::SafeFileLock::write_lock_contents( $fh, $original_path );

=cut
