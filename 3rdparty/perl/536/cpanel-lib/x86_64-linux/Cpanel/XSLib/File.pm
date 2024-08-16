package Cpanel::XSLib::File;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::XSLib::File - Perl interfaces to C file functions

=head1 SYNOPSIS

    my $pos = Cpanel::XSLib::File::ftell($fh);

    if (Cpanel::XSLib::File::feof($fh)) { ... }

=head1 DESCRIPTION

When interfacing with some C libraries it’s useful/necessary to interact
with a Perl filehandle’s underlying C C<FILE *> structure. This facilitates
that.

=cut

#----------------------------------------------------------------------

our $VERSION;

use XSLoader ();

BEGIN {
    $VERSION = '0.01';
    XSLoader::load();
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 C<feof()> and C<ftell()>

These mimic their C implementations but follow the usual Perl convention
for reporting failure/success: return 1 on success, or undef on
failure (with C<$!> being set).

=head3 When is this useful?

By default, Perl filehandles use PerlIO for buffering reads and writes.
You can bypass this to get at the OS’s raw I/O functionality via Perl’s
C<sysread()> and C<syswrite()> built-ins.

There’s a middle layer in between: C’s standard I/O functions like
L<feof(3)>. Generally we don’t need these in Perl since Perl has its own
I/O, but when interfacing with C code we sometimes need Perl to call the I/O
logic that our C code uses.

Ordinarily you could do something like C<open my $rfh, '<:stdio', $path>
then use Perl’s built-ins (e.g., C<eof()>); however, if your filehandle
comes from a file descriptor then there doesn’t appear to be a way to
set its PerlIO layer to C<:stdio>. (C<open my $dup, '+<&=:stdio', $fd>
silently ignores the C<:stdio>, and C<binmode $fh, ':stdio'> fails with
EINVAL. Those may be bugs in Perl.)

These functions provide a simple, reliable way to get at C’s standard I/O
functions for a given filehandle.

An example use case is parsing records iteratively via L<DNS::LDNS::RR>
rather than in one fell swoop via L<DNS::LDNS::Zone>.
When doing this we need to check L<feof(3)> between reads to see if we’ve
reached the end of the buffer; as of April 2021 we also (due to a bug in
LDNS) need L<ftell(3)> to know how many lines each read crossed.

=cut

1;
