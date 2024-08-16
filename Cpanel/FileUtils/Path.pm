package Cpanel::FileUtils::Path;

# cpanel - Cpanel/FileUtils/Path.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FindBin         ();
use Cpanel::Path::Normalize ();

our $VERSION = '1.1';

sub findinpath {
    my $bin = shift;

    return '' if ( !$bin );

    my @paths = split( /:/, $ENV{'PATH'} );

    return cleanpath( Cpanel::FindBin::findbin( $bin, 'path' => \@paths ) );
}

*cleanpath = *Cpanel::Path::Normalize::normalize;

# Note: this normalizes the path as well by removing extra slashes
# In scalar context, this only returns the filename
sub dir_and_file_from_path {
    my ($file_path) = @_;

    my @PATH_TEMP = split /\/+/, $file_path;
    my $filename  = pop @PATH_TEMP;
    my $filedir   = join q{/}, @PATH_TEMP;
    $filedir = '/' if !length $filedir;

    return ( $filedir, $filename );
}

1;
