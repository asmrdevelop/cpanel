package Cpanel::Streamer::MysqlDump;

# cpanel - Cpanel/Streamer/MysqlDump.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::MysqlDump

=head1 DESCRIPTION

This module implements a L<Cpanel::Streamer::ReportUtilUser> subclass
on top of L<Cpanel::MysqlUtils::Dump>.

=head1 ATTRIBUTES

=over

=item * C<dbname> - The name of the database to stream.

=item * C<mode> - One of the C<stream_database_*> function names
from L<Cpanel::MysqlUtils::Dump>.

=item * C<get_exit_code_for_error> - Optional, coderef that accepts
an exception and returns a process exit code. Useful for reporting
specific error types to a caller.

=back

=cut

use parent 'Cpanel::Streamer::Base::ReportUtilUser';

use Cpanel::Streamer::ReportUtil ();
use Cpanel::MysqlUtils::Dump     ();

use constant _MODES => (
    'stream_database_data_utf8mb4',
    'stream_database_data_utf8',
    'stream_database_nodata_utf8mb4',
    'stream_database_nodata_utf8',
);

#----------------------------------------------------------------------

sub _init ( $self, %opts ) {
    my $dbname = $opts{'dbname'};
    die "Need “dbname”" if !length $dbname;

    my $dump_func = $opts{'mode'} || die 'Need “mode”';
    if ( !grep { $_ eq $dump_func } _MODES() ) {
        die "Bad “mode”: $dump_func";
    }
    $dump_func = Cpanel::MysqlUtils::Dump->can($dump_func) || die "BAD MODE LIST ($dump_func)";

    Cpanel::Streamer::ReportUtil::start_reporter_child(
        streamer => $self,
        todo_cr  => sub ($child_s) {
            $dump_func->( $child_s, $dbname );
        },
        %opts{'get_exit_code_for_error'},
    );

    return;
}

1;
