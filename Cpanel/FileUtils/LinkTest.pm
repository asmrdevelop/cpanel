package Cpanel::FileUtils::LinkTest;

# cpanel - Cpanel/FileUtils/LinkTest.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::LinkTest

=head1 SYNOPSIS

    my $exists = !!Cpanel::FileUtils::LinkTest::get_type('/path/to/node');

=head1 DESCRIPTION

C<stat()> is the typical system call used to determine existence of a
filesystem node. We can realize a small optimization by using C<readlink()>
for this purpose instead, however; since error responses to that call
distinguish between EINVAL (exists but not a symlink) and ENOENT (doesn’t
exist) we can effectively check existence this way.

This module implements that
logic. The downside is that you don’t get the file information like size,
mtime, etc. that C<stat()> returns.

=cut

use constant {
    _ENOENT => 2,
    _EINVAL => 22,
};

=head1 FUNCTIONS

=head2 get_type( PATH )

Returns one of:

=over

=item * C<link> - if the node is a symbolic link

=item * C<non_link> - if the node exists but is B<not> a symbolic link

=item * undef - if the node doesn’t exist

=back

An exception is thrown on error.

B<NOTE:> In the most immediate use case (i.e., existence checking) you
won’t care about C<link> versus C<non_link>; this function mostly
distinguishes between those two cases to avoid throwing away
potentially useful information.

=cut

sub get_type {
    local ( $!, $^E );
    readlink $_[0] // do {
        return undef      if $! == _ENOENT();
        return 'not_link' if $! == _EINVAL();    #non-symlink

        die Cpanel::Exception->create( 'The system failed to determine whether “[_1]” exists on the filesystem because of an error: [_2]', [ $_[0], $! ] );
    };

    return 'link';
}

1;
