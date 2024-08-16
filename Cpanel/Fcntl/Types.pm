package Cpanel::Fcntl::Types;

# cpanel - Cpanel/Fcntl/Types.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Fcntl::Type - Lookup the file type from the mode

=head1 SYNOPSIS

    use Cpanel::Fcntl::Type;

    my $mode = (stat($file))[2];

    my $type_of_file = $Cpanel::Fcntl::Types::FILE_TYPES{ $Cpanel::Fcntl::Constants::S_IFMT & $mode } );

=cut

use Cpanel::Fcntl::Constants ();

our %FILE_TYPES = (
    $Cpanel::Fcntl::Constants::S_IFREG  => 'file',
    $Cpanel::Fcntl::Constants::S_IFDIR  => 'dir',
    $Cpanel::Fcntl::Constants::S_IFCHR  => 'char',
    $Cpanel::Fcntl::Constants::S_IFBLK  => 'block',
    $Cpanel::Fcntl::Constants::S_IFIFO  => 'fifo',
    $Cpanel::Fcntl::Constants::S_IFLNK  => 'link',
    $Cpanel::Fcntl::Constants::S_IFSOCK => 'socket',
);
1;
