package Cpanel::HttpUtils::PatchConf;

# cpanel - Cpanel/HttpUtils/PatchConf.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#   This module is 'born deprecated': it directly updates the httpd.conf file.
#   that's something we want to avoid doing in the future; we want httpd.conf
#   to be a write-only file that we regenerate from a definitive source (e.g.,
#   /var/cpanel/userdata) whenever we want to chagne anything.
#
#   This module exists strictly to support legacy scripts; please avoid using or
#   adding to this module.
#

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Debug    ();
use Cpanel::SafeFile ();
use IO::Handle       ();

sub remove_user_group {
    my ($bad_name) = @_;
    return if length($bad_name) < 2;

    my $httpd_path = apache_paths_facade->file_conf();

    # not going to create an empty httpd.conf
    my $httpd      = IO::Handle->new();
    my $httpd_lock = Cpanel::SafeFile::safeopen( $httpd, '+<', $httpd_path );
    if ( !$httpd_lock ) {
        Cpanel::Debug::log_die("Could not edit $httpd_path");
    }

    # Read the file, skipping lines with the bogus user/group name
    my @http =
      grep { !/^\s*Group\s+$bad_name$/i && !/^\s*User\s+$bad_name$/i && !/^\s*SuexecUserGroup\s+$bad_name\b/i } <$httpd>;

    # Write the file back out
    seek( $httpd, 0, 0 );
    print $httpd join( '', @http );
    truncate( $httpd, tell($httpd) );

    return Cpanel::SafeFile::safeclose( $httpd, $httpd_lock );
}

1;
