
# cpanel - Cpanel/Quota/Test.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Test;

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Finally ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::PwCache ();

=head1 NAME

Cpanel::Quota::Test

=head1 FUNCTIONS

=head2 quotatest()

Perform a test write of a 1 MiB file under the current user's home directory.
The file will be cleaned up after the test is complete.

=head3 Arguments

n/a

=head3 Returns

List:

- status (boolean)

- reason (string)

=head3 Side channel inputs

If running in an area which has $Cpanel::context set, this determines where
error messages will be stashed. If not set, then errors will not be stored,
only returned.

=head3 Side channel outputs (i.e. side effects of this function)

On error, sets CPERROR value for the current context to the appropriate message.
This may be helpful for API responses and should be harmless for other applications.
If $Cpanel::context is not set, then this step is skipped.

C<$!> is also set.

=cut

my $TESTSIZE = 1048576;    # one mebibyte

our $_last_write_op;

sub quotatest {
    my $suffix   = sprintf( "%x.%x.%x", time(), $$, rand(1e8) );
    my $homedir  = $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    my $testfile = $homedir . '/.cPquotatest.' . $suffix;

    my $unlink_at_end = Cpanel::Finally->new( sub { unlink $testfile } );

    if ( !_write($testfile) ) {
        my $err   = "$_last_write_op: $!";
        my $error = lh()->maketext( 'The disk-write test failed to write [format_bytes,_1] to a temporary file ([_2]) because of an error: [_3] ([asis,EUID]: [_4]).', $TESTSIZE, $testfile, $err, $> );

        $Cpanel::CPERROR{$Cpanel::context} = $error if $Cpanel::context;
        return 0, $error;
    }

    #This used to check for file size, but it can’t write out an incomplete
    #buffer without a failure, so there’s no reason to check for that.

    return 1;
}

sub _write {
    my ($testfile) = @_;

    open my $quotatest_fh, '>', $testfile or do {
        $_last_write_op = "open($testfile)";
        return;
    };

    #Don’t use PerlIO (i.e., print()) here because we want to
    #get an error up-front.
    syswrite( $quotatest_fh, "\0" x $TESTSIZE ) or do {
        $_last_write_op = "write($testfile)";
        return;
    };

    #shouldn’t fail except in catastrophic cases
    close $quotatest_fh or warn "close($testfile): $!";

    return 1;
}

=head2 quotatest_or_die

Same as quotatest, but throws an exception instead of communicating the status
as return values.

=head3 Arguments

n/a

=head3 Returns

Returns true on success.

=head3 Throws

On failure, an exception will be thrown.

=cut

sub quotatest_or_die {
    my ( $status, $reason ) = quotatest();
    if ( !$status ) {
        die $reason . "\n";
    }
    return 1;
}

1;
