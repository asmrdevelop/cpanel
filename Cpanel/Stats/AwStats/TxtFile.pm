package Cpanel::Stats::AwStats::TxtFile;

# cpanel - Cpanel/Stats/AwStats/TxtFile.pm         Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();

use Simple::Accessor qw{
  file

  _fh
  _map
};

=encoding utf8

=head1 NAME

C<Cpanel::Stats::AwStats::TxtFile>

=head1 DESCRIPTION

Parse a extract data from an awstats .txt file containing the monthly data.

=head1 SYNOPSIS

    use Cpanel::Stats::AwStats::TxtFile ();

=head1 FUNCTIONS

=head2 Cpanel::Stats::AwStats::TxtFile->new ( %opts )

Create one 'Cpanel::Stats::AwStats::TxtFile' object to parse a file
identified by 'file'.

List of options you can pass to new:

=over

=item file (string)

The full file path of the file to parse.

=back

=cut

sub _build_file ($self) {

    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['file'] );
}

sub _build__fh ($self) {
    open( my $fh, '<', $self->file ) or return;
    return $fh;
}

sub _build__map ($self) {

    my $fh = $self->_fh or return;

    my %map;
    my $map_entries;
    while ( my $line = readline($fh) ) {

        if ( $line =~ m{^BEGIN_MAP\s+(\d+)}a ) {
            $map_entries = int $1;
            last if $map_entries == 0;
            next;
        }
        next unless $map_entries;

        if ( $line =~ m{^POS_(\S+)\s+(\d+)} ) {
            $map{$1} = int $2;
        }

        last if $line =~ m{^END_MAP};
    }

    return \%map;
}

=head2 $self->get_section( $name )

Returns the content of a section identified by its name.
The return value is 'undef' when the section is unknown
or one ArrayRef with each entry representing a line in the
section.

=cut

sub get_section ( $self, $name ) {
    my $map = $self->_map or return;

    my $fh = $self->_fh or return;

    my $offset = $map->{$name};
    return unless defined $offset && $offset > 0;

    seek( $fh, $offset - tell($fh), 1 );

    my @section;
    while ( my $line = readline($fh) ) {
        next if $line =~ qr{^BEGIN_\Q$name\E};
        last if $line =~ qr{^END_\Q$name\E};
        chomp $line;
        push @section, $line;
    }

    return \@section;
}

=head2 $self->get_daily_stats()

Parse the 'DAY' section and returns the stats as one HashRef.

    {
        '20230401' => {
            pages     => 66,
            hits      => 99,
            bandwidth => 456,
            visits    => 42
        },
        ...
    }

=cut

sub get_daily_stats ($self) {
    my $data = $self->get_section('DAY') or return;

    my $stats = {};

    foreach my $line (@$data) {
        my ( $date, $pages, $hits, $bandwidth, $visits ) = split( /\s+/, $line );

        next unless $date;
        $stats->{$date} = {
            pages     => int $pages,
            hits      => int $hits,
            bandwidth => int $bandwidth,
            visits    => int $visits,
        };
    }

    return $stats;
}

1;
