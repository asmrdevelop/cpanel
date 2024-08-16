package Cpanel::FileUtils::Equiv;

# cpanel - Cpanel/FileUtils/Equiv.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug ();

our $VERSION = '1.0';

sub equivalent_files {
    my $file1 = shift;
    my $file2 = shift;

    if ( !$file1 || !$file2 ) {
        Cpanel::Debug::log_warn('Invalid arguments for file_compare');
        return;
    }
    return 1 if $file1 eq $file2;

    my ( $dev1, $inode1, $size1 );
    if ( -e $file1 ) {
        ( $dev1, $inode1, $size1 ) = ( stat(_) )[ 0, 1, 7 ];
    }
    my ( $dev2, $inode2, $size2 );
    if ( -e $file2 ) {
        ( $dev2, $inode2, $size2 ) = ( stat(_) )[ 0, 1, 7 ];
    }

    if ( $dev1 == $dev2 && $inode1 == $inode2 && $size1 == $size2 ) {
        return 1;
    }
    return;
}

1;
