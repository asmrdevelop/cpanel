package Whostmgr::Templates::Chrome::Directory;

# cpanel - Whostmgr/Templates/Chrome/Directory.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

my $footer_dir = '/var/cpanel/caches/_generated_footer_files';
my $header_dir = '/var/cpanel/caches/_generated_header_files';

=head1 DESCRIPTION

Utility functions to handle directories for cached WHM chrome files

=cut

=head1 SUBROUTINES

=cut

=head2 get_footer_cache_directory

=head3 Purpose

Returns the cache directory for processed _deffooter.tmpl files.

=cut

sub get_footer_cache_directory {
    return $footer_dir;
}

=head1 SUBROUTINES

=cut

=head2 get_header_cache_directory

=head3 Purpose

Returns the cache directory for processed _defheader.tmpl files.

=cut

sub get_header_cache_directory {
    return $header_dir;
}

=head2 clear_cache_dir

=head3 Purpose

Clear cache files on disk

=cut

sub clear_cache_directories {
    Cpanel::LoadModule::load_perl_module('File::Path');
    File::Path::rmtree( get_footer_cache_directory() );
    File::Path::rmtree( get_header_cache_directory() );
    return;
}

1;
