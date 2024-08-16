package Cpanel::Exim::Config::Template;

# cpanel - Cpanel/Exim/Config/Template.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile ();

sub getacltemplateversion {
    my $file        = shift;
    my $exim_config = Cpanel::LoadFile::loadfile($file);
    my $template_version;
    if ( defined $exim_config && $exim_config =~ m/^\s*\#\s*cPanel\s+.*\s+ACL\s+Template\s+Version:\s+([\d\.]+)/m ) {
        $template_version = sprintf( "%f", $1 );
    }
    return $template_version;
}

1;
