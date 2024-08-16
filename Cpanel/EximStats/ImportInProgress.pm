package Cpanel::EximStats::ImportInProgress;

# cpanel - Cpanel/EximStats/ImportInProgress.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::EximStats::ImportInProgress

=head1 SYNOPSIS

    use Cpanel::PIDFile ();

    Cpanel::PIDFile::do(
        $Cpanel::EximStats::ImportInProgress::PATH,
        sub { ... },
    );

    my $progress = Cpanel::EximStats::ImportInProgress::read_if_exists();

=head1 CONSTANTS

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie   ();
use Cpanel::PIDFile   ();
use Cpanel::Time::ISO ();

=head2 $Cpanel::EximStats::ImportInProgress::PATH

The filesystem path of the in-progress marker.
Meant for injection into C<Cpanel::PIDFile::do()>.

=cut

#so this can be overridden in tests
our $PATH          = '/var/cpanel/eximstats_db_import_in_progress';
our $IMPORTED_FILE = '/var/cpanel/version/eximstats_imported_1164';

=head1 FUNCTIONS

=head2 read_if_exists()

Returns undef if there is no import in progress; otherwise, returns
a hash reference:

=over

=item * C<pid>: The ID of the process that’s doing the import.

=item * C<start_time>: The time when the import started, in ISO format.

=back

An exception is thrown if there is any error (e.g., permissions)
in determining whether an import is in progress.

=cut

sub read_if_exists {
    my $payload;

    my @stat;

    if ( Cpanel::Autodie::exists_nofollow($PATH) ) {
        @stat    = lstat _;
        $payload = { pid => Cpanel::PIDFile->get_pid($PATH) };
    }

    if ($payload) {
        $payload->{'start_time'} = Cpanel::Time::ISO::unix2iso( $stat[10] );
    }

    return $payload;
}

1;
