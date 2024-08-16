package AcctLock;

# cpanel - AcctLock.pm                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

AcctLock - A “big”, generic lock

=head1 SYNOPSIS

    {
        my $lock = AcctLock::create();

        # Do stuff under this lock …

        {
            my $lock2 = AcctLock::create();

            # Still under the lock.
        }

        # Still under the lock.
    }

    # The lock is gone.

=head1 DESCRIPTION

This module implements a filesystem-based, reference-counting mutex.

=head1 CAVEATS

This expects all references to be held within the same process.
It doesn’t expect to deal with forking or other “interesting” uses.

=cut

#----------------------------------------------------------------------

use Cpanel::SafeFile ();
use Cpanel::Fcntl    ();
use Cpanel::Finally  ();
my $LOCKED               = 0;
my $accounting_lock_file = '/var/cpanel/accounting_big_lock';
my ( $lock, $lock_fh );

*unacctlock = \&acctunlock;

my $safety;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $lock_count = is_locked()

Returns a number that indicates the number of active references to the lock.
If the number is 0, we’re unlocked; otherwise we’re locked.

=cut

sub is_locked { return $LOCKED; }

=head2 $lock_obj = create()

Returns an opaque object that holds one reference to the lock. When
that returned object goes away that reference to the lock goes away
with it.

This throws an exception if we fail to acquire the lock.

=cut

sub create {
    require Cpanel::Context;
    Cpanel::Context::must_not_be_void();

    acctlock() or die 'Failed to lock!';

    return Cpanel::Finally->new( \&acctunlock );
}

=head2 $locked_yn = acctlock()

Increases the lock reference counter by one. Returns a boolean that
indicates success or failure; on failure the reason is printed to STDERR.

=cut

sub acctlock {
    local $Cpanel::SafeFile::LOCK_WAIT_TIME = 180;
    local $Cpanel::SafeFile::MAX_FLOCK_WAIT = 160;

    if ($LOCKED) {
        $LOCKED++;
        return 1;
    }

    $lock   = Cpanel::SafeFile::safesysopen( $lock_fh, $accounting_lock_file, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT )), 0700 );
    $LOCKED = 1 if $lock;
    $safety = Cpanel::Finally->new(
        sub {
            my $err = "Failed to acctunlock() before global destruction!";
            if ( $INC{'Carp.pm'} ) {
                print STDERR Carp::longmess($err);
            }
            else {
                print STDERR $err . "\n";
            }
            warn $err;
            acctunlock();
        }
    );
    return $lock ? 1 : 0;
}

=head2 $is_unlocked = acctunlock()

Returns a boolean (or possibly nothing at all) that indicates whether
the reference counter is empty, i.e., whether the lock itself is gone.

=cut

sub acctunlock {
    $safety->skip() if $safety;
    undef $safety;
    return if --$LOCKED;
    unlink($accounting_lock_file);
    Cpanel::SafeFile::safeclose( $lock_fh, $lock );
    $LOCKED = 0;
    return 1;
}

1;
