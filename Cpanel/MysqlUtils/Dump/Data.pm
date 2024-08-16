package Cpanel::MysqlUtils::Dump::Data;

# cpanel - Cpanel/MysqlUtils/Dump/Data.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Dump::Data - Resilient MySQL dump

=head1 DESCRIPTION

This class implements fault-tolerant MySQL data dumps.

This is a base class; do not instantiate it directly.

=cut

#----------------------------------------------------------------------

use Cpanel::Try ();

# accessed in tests
our $_MAX_ATTEMPTS = 3;

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->dump_data( %OPTS )

Dumps a MySQL database, with fault tolerance logic as described below.

%OPTS are:

=over

=item * C<dbname> - The DB’s name, e.g., C<bobs_stuff>.

=item * C<get_fh> - A coderef that returns a filehandle where the
output of the MySQL dump will be sent. This will be called on each
individual MySQL dump attempt.

=item * C<mode> - One of: C<all> (gives everything) or C<nodata>
(gives routines, triggers, events, and views, but not data).

=back

MySQL data dumps are error-prone, as a result of which over time we have
developed fault-tolerance mechanisms:

=over

=item * We default to MySQL’s C<utf8mb4> character encoding.
In the event of either C<ER_CANT_AGGREGATE_NCOLLATIONS> or
C<ER_CANT_AGGREGATE_3COLLATIONS>, we fall back to C<utf8>.

=item * We try multiple times, just in case a single dump failure is
transient.

=item * Prior to the final pair of C<utf8mb4>/C<utf8> backup attempts,
we attempt to repair the database.

=back

=cut

sub dump_data {
    my ( $class, %opts ) = @_;

    my $dbname = $opts{'dbname'};
    die "Need “dbname”!" if !length $dbname;

    if ( $opts{'mode'} ne 'all' && $opts{'mode'} ne 'nodata' ) {
        die "Invalid “mode”: “$opts{'mode'}”";
    }

    my $attempts = 0;

    my $err;

    while ( $attempts < $_MAX_ATTEMPTS ) {
        my $ok = eval {
            Cpanel::Try::try(
                sub {
                    my $fh = $opts{'get_fh'}->();

                    my $fn = $opts{'mode'} eq 'nodata' ? '_stream_utf8mb4_nodata' : '_stream_utf8mb4';

                    $class->$fn( $fh, $dbname );
                },
                'Cpanel::Exception::Database::MysqlIllegalCollations' => sub {
                    my $fh = $opts{'get_fh'}->();

                    my $fn = $opts{'mode'} eq 'nodata' ? '_stream_utf8_nodata' : '_stream_utf8';

                    $class->$fn( $fh, $dbname );
                },
            );

            1;
        };

        return if $ok;

        $err = $@;

        $attempts++;

        if ( $attempts < $_MAX_ATTEMPTS ) {
            warn;

            if ( $attempts == ( $_MAX_ATTEMPTS - 1 ) ) {
                warn "Failed $attempts times; repairing DB before final attempt.\n";

                warn if !eval { $class->_repair($dbname); 1 };
            }
        }
    }

    die "Failed after $attempts times; last error: $err";
}

1;
