package Cpanel::BandwidthDB::Read::BackupParser;

# cpanel - Cpanel/BandwidthDB/Read/BackupParser.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Parser::Base );

=encoding utf-8

=head1 NAME

Cpanel::BandwidthDB::Read::BackupParser

=head1 SYNOPSIS

use Cpanel::BandwidthDB::Read::BackupParser ();

open( my $json_stream_fh, '>', 'path/to/json/stream/out.json' );
my $parser = Cpanel::BandwidthDB::Read::BackupParser->new( stream_fh => $json_stream_fh );
...

$parser->process_data(@data);

=head1 DESCRIPTION

This module extends the base class Cpanel::Parser::Base and is meant to be used to parse a data stream
of json rows of bandwidth data from a /var/cpanel/bandwidth database. Each row is newline delimited.

=head1 FUNCTIONS

=head2 new( KEY => VALUE )

This function instantiates a Cpanel::BandwidthDB::Read::BackupParser object.

=head3 Arguments

=over 4

=item stream_fh    - required OUTPUT FILEHANDLE - This should be the filehandle to the JSON stream output file. The file will receive new line delimited JSON encoded arrayrefs of hashrefs.

=item stream_line_length    - optional SCALAR - The number of bytes to reach before dumping a JSON stream line.

=back

=head3 Returns

A Cpanel::BandwidthDB::Read::BackupParser object.

=head3 Exceptions

An exception is thrown if stream_fh isn't passed.

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    $self->{_stream_fh}          = $OPTS{stream_fh}          || die "Need stream_fh!";
    $self->{_stream_line_length} = $OPTS{stream_line_length} || 1024**2 * 2;             # Backup restore is faster with larger numbers
    $self->{_item_buffer}        = '';

    return $self;
}

=head2 process_data( SCALAR )

This function accepts chunks of text from a database dump where each line is newline delimited and inside each
line is a row of json data. This function will buffer the data and process the lines.  This data is then
serialized as long JSON arrayref line once enough (stream_line_length) entries are available.

=head3 Arguments

=over 4

=item data    - required SCALAR - A chunk of text from a dumped

=back

=head3 Returns

This function returns 1.

=head3 Exceptions

None.

=cut

sub process_data {
    my ( $self, $data ) = @_;
    $self->{'_buffer'} .= $data;
    if ( my $idx = rindex( $self->{'_buffer'}, "\n" ) ) {
        $self->process_lines( substr( $self->{'_buffer'}, 0, 1 + $idx, '' ) ) || return 0;
    }
    return 1;
}

=head2 process_lines( SCALAR )

This function collects lines into a buffer and will write them out as a single long
JSON line once C<stream_line_length> has been reached

=head3 Arguments

=over 4

=item lines    - required SCALAR - See function description for format of these streamed lines from a bandwidth database.

=back

=head3 Returns

Returns 1.

=head3 Exceptions

None.

=cut

sub process_lines {
    my ( $self, $lines ) = @_;

    return if !defined $lines;

    $self->{_item_buffer} .= $lines;

    if ( length $self->{_item_buffer} >= $self->{_stream_line_length} ) {
        $self->_dump_item_buffer();
    }

    return 1;
}

=head2 finish()

This function is meant to process the last bit of data in the buffer and perform cleanup after the stream
of database rows has completed.

=head3 Returns

Returns 1.

=head3 Exceptions

None.

=cut

sub finish {
    my ($self) = @_;

    $self->process_lines( $self->{_buffer} );

    $self->clear_buffer();

    $self->_dump_item_buffer();

    return 1;
}

sub _dump_item_buffer {
    my ($self) = @_;

    return if !$self->{_item_buffer};

    chop $self->{_item_buffer} if substr( $self->{_item_buffer}, -1 ) eq "\n";

    print { $self->{_stream_fh} } '[' . $self->{_item_buffer} =~ tr{\n}{,}r . "]\n";

    $self->{_item_buffer} = '';

    return 1;
}

1;
