package Cpanel::Slurper;

# cpanel - Cpanel/Slurper.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception        ();
use Cpanel::LoadFile         ();
use Cpanel::FileUtils::Write ();

=encoding utf-8

=head1 NAME

Cpanel::Slurper - wrapper around common helpers to read/write files

=head1 SYNOPSIS

     # Reading files
     my $content = Cpanel::Slurper::read( '/path/to/file' );

     my @lines   = Cpanel::Slurper::read_lines( '/path/to/file' );

     # Writing to files
     Cpanel::Slurper::write( '/path/to/file' => 'my content' ); # throw an exception on errors;
     Cpanel::Slurper::write( '/path/to/file' => 'my content', 0655 );

=head1 DESCRIPTION

Provide basic helpers to read and write to files.
This is a thin wrapper arounds C<Cpanel::LoadFile::load> and C<Cpanel::FileUtils::Write::overwrite>

=head1 FUNCTIONS

=head2 read( $file )

Read a file and return the file content as a scalar.
Returns `undef` when the file does not exist.

=cut

sub read ($file) {
    return scalar Cpanel::LoadFile::load($file);
}

=head2 read_lines( $file )

Similar to read but return a list, split on newline.
The newline character is strip from each line.

=cut

sub read_lines ($file) {
    return split( qr{\n}, __PACKAGE__->can('read')->($file) );
}

=head2 read_dir( $path )

Open the directory C<path> and return a list of entries without C<.> and C<..>.

=cut

sub read_dir ($path) {
    my $dh;
    opendir( $dh, $path )    #
      or die Cpanel::Exception::create( "IO::DirectoryOpenError", [ path => $path, error => $! ] );
    return ( grep { defined $_ && $_ ne '.' && $_ ne '..' } readdir($dh) );
}

=head2 write( $filename, $content, [, $perms_or_optshr ])

Write the string $content to the file $filename.
Replace the content of the file if already exists.

$perms_or_optshr, if given, should be either:

=over

=item * An octal number. B<NOTE:> this is
 not a string made to look like an octal number.
 The default value is 0600. Note also that, unlike the value given to
 Perl’s C<syswrite> built-in, this is the
 B<real> value that will be written to disk;
 i.e., the process’s umask will have no effect.

=item * A hash reference of options (all optional):

=item * C<before_installation> - callback that will run immediately
 prior to the installation of the fully-written-out file. The callback
 receives the filehandle to the file.
 This is useful if you want to, e.g., C<chown()> the file prior to its being
 installed so that there is never any point at which an invalid filesystem
 state (e.g., a production file with improper ownership) exists.

=back

=cut

sub write ( $file, $content, $perms_or_callback = undef ) {
    return !!Cpanel::FileUtils::Write::overwrite( $file, $content, $perms_or_callback );
}

=head1 READ ALSO

=over

=item L<Cpanel::LoadFile>

=item L<Cpanel::FileUtils::Write>

=back

=cut

1;
