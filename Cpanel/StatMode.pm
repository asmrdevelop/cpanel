package Cpanel::StatMode;

# cpanel - Cpanel/StatMode.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Fcntl;

=head1 NAME

Cpanel::StatMode - Use a single stat to determine file type

=head1 SYNOPSIS

    my $filetype = Cpanel::StatMode::filetype ($filename);

=head1 DESCRIPTION

This module calls lstat and determines the file type in a single call rather
than doing a set of -e, -f, -d, -l etc calls.

=head1 FUNCTIONS

=head2 filetype ($filepath)

Returns as follows:

    undef   - $filepath does not exist
    file    - $filepath is a regular file
    dir     - $filepath is a directory
    symlink - $filepath is a symlink
    block   - $filepath is a block device
    chr     - $filepath is a character device
    fifo    - $filepath is a fifo
    socket  - $filepath is a socket
    error   - $filepath exists but unknown type

=cut

sub filetype {
    my ($fullpath) = @_;

    my $mode = ( lstat($fullpath) )[2];
    return           if ( !defined $mode );
    return 'file'    if ( Fcntl::S_ISREG($mode) );
    return 'dir'     if ( Fcntl::S_ISDIR($mode) );
    return 'symlink' if ( Fcntl::S_ISLNK($mode) );
    return 'block'   if ( Fcntl::S_ISBLK($mode) );
    return 'chr'     if ( Fcntl::S_ISCHR($mode) );
    return 'fifo'    if ( Fcntl::S_ISFIFO($mode) );
    return 'socket'  if ( Fcntl::S_ISSOCK($mode) );
    return 'error';
}

1;
