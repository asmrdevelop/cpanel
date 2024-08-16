
# cpanel - Cpanel/Gunzip.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Gunzip;

use strict;
use warnings;

use Cpanel::Exception       ();
use Cpanel::Binaries        ();
use Cpanel::SafeRun::Object ();

use IO::Uncompress::Gunzip ();

=head1 MODULE

C<Cpanel::Gunzip>

=head1 DESCRIPTION

C<Cpanel::Gunzip> provides gunzip services. With this library you can validate
a gzip file, gunzip a file to another file or file handle.

=head1 FUNCTIONS

=head2 gunzip(IN, OUT)

Gunzip a file returning the file handle like object that can be used to read
in the gzip file in chunks. This helper wraps the IO::Uncompress::Gunzip constructor.
You can use any of the buffer techniques exposed by this object.

=head3 ARGUMENTS

=over

=item IN - string | file handle

Input file name or input file handle.

=item OUT - file handle

Output file handle.

=back

=head3 RETURNS

C<IO::Uncompress::Gunzip>

=head3 THROWS

=over

=item When the IN parameter is missing.

=item When the OUT parameter is missing.

=item When the IN parameter can not be used to create the input stream.

=back

=cut

sub gunzip {
    my ( $in, $out, %opts ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', ['in'] )  if !$in;
    die Cpanel::Exception::create( 'MissingParameter', ['out'] ) if !$out;
    die Cpanel::Exception::create( 'InvalidParameter', ['out'] ) if ref $out ne 'GLOB';

    my $gzip = IO::Uncompress::Gunzip->new( $in, %opts );
    if ( !$gzip ) {
        die Cpanel::Exception->create(
            'Failed to open “[_1]” with the error: [_2]',
            [ $in, $IO::Uncompress::Gunzip::GunzipError ]
        );
    }

    my $status;
    for ( $status = 1; $status > 0; $status = $gzip->nextStream() ) {
        my $buffer;
        while ( ( $status = $gzip->read($buffer) ) > 0 ) {
            print {$out} $buffer;
        }
    }

    return 1;
}

=head2 is_valid(FILE)

Checks if the requested file is a gzip compatible file.

=head3 ARGUMENTS

=over

=item FILE - string

Path to the file that we think is a gzip compatible file.

=back

=head3 RETURNS

1 if the file is a gzip archive. 0 otherwise.

=cut

sub is_valid {
    my ($file) = @_;
    die Cpanel::Exception::create( 'MissingParameter', [ name => $file ] )
      if !$file;

    my $gzip_bin = _get_gzip_bin();

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => $gzip_bin,
        args    => [ '-t', '-v', $file ]
    );
    return 0 if $run->CHILD_ERROR();
    return 1;
}

=head2 is_valid_or_die(FILE)

Checks if the requested file is a C<gzip> compatible file.

=head3 ARGUMENTS

=over

=item FILE - string

Path to the file that we think is a C<gzip> compatible file.

=back

=head3 THROWS

When the file is not a valid C<gzip> file.

=cut

sub is_valid_or_die {
    my ($file) = @_;
    if ( not eval { is_valid($file) } or $@ ) {
        die Cpanel::Exception->create( '“[_1]” is not a valid [asis,gzip] archive.', [$file] );
    }
}

=head2 _get_gzip_bin() [PRIVATE]

Get the full path to the C<gzip> binary.

=cut

sub _get_gzip_bin {
    my $gzip_bin = Cpanel::Binaries::path('gzip');

    die Cpanel::Exception->create('[asis,gzip] binary is unavailable on the system.')
      if !-x $gzip_bin;

    return $gzip_bin;
}

1;
