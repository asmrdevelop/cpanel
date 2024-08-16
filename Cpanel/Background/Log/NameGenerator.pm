
# cpanel - Cpanel/Background/Log/NameGenerator.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Background::Log::NameGenerator;

use strict;
use warnings;

use Cpanel::Imports;
use Cpanel::Time::ISO ();

=head1 MODULE

C<Cpanel::Background::Log::NameGenerator>

=head1 DESCRIPTION

C<Cpanel::Background::Log::NameGenerator> provides helpers that create unique unused filenames.

These are often used for log files for specific long running processes that need a unique
log file per run and other similar activities.

=head1 SYNOPSIS

  use Cpanel::Background::Log::NameGenerator ();
  my ($file, $path) = Cpanel::Background::Log::NameGenerator::get_available_filename_or_die('/logs', max_tries => 2);

=cut

=head1 FUNCTIONS

=head2 get_available_filename_or_die(PATH, extension => ..., max_tries => ...)

Tries to find a filename that is not currently present based on the
current date and the other arguments.

=head3 ARGUMENTS

=over

=item PATH - string

Directory where the file will be located.

=item OPTIONS - hash

Additional options where the following options are available.

=item extension - string

Extension for the file. Defaults to .log

=item max_tries - number

Number of times to attempt to find an available file name. Defaults to 10.

=back

=head3 RETURNS

list with the following items (NAME, PATH)

=over

=item NAME - string

The name of the unused file.

=item PATH - string

The full path to the unused file.

=back

=head3 THROWS

=over

=item When the path parameter is not provided.

=item When an available path can not be calculated.

=back

=cut

sub get_available_filename_or_die {
    my ( $path,      %opts )      = @_;
    my ( $extension, $max_tries ) = @opts{qw(extension max_tries)};

    die 'missing path' if !defined $path || $path eq '';    # developer only error.
    $extension //= 'log';
    $extension =~ s/^\.//;

    $max_tries //= 10;
    die 'max_tries must be a number' if $max_tries !~ m/[0-9]+/;    # developer only error.

    # find an unused file name in n tries
    my $count = 0;
    my ( $fullpath, $name, $available );

    my $formatted_date = Cpanel::Time::ISO::unix2iso( _now() );

    do {
        $count++;
        $name      = "${formatted_date}.${count}.${extension}";
        $fullpath  = "$path/$name";
        $available = -f $fullpath ? 0 : 1;
    } until ( $available || $count >= $max_tries );

    die locale()->maketext('The system failed to find an available file name.') if !$available;
    return ( $name, $fullpath );
}

# For mocking
sub _now {
    return time();
}

1;
