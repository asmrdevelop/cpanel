package Cpanel::Config::Httpd::Vendor;

# cpanel - Cpanel/Config/Httpd/Vendor.pm                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::EA4 ();
use Cpanel::LoadFile           ();

our $LITESPEED_PATH               = '/usr/local/lsws/bin/lshttpd';
our $LITESPEED_BUILD_VERSION_FILE = '/usr/local/lsws/autoupdate/build';

=encoding utf-8

=head1 NAME

Cpanel::Config::Httpd::Vendor - Gather vendor and version information for the httpd vendor.

=head1 SYNOPSIS

    use Cpanel::Config::Httpd::Vendor;

    my($vendor, $version) = Cpanel::Config::Httpd::Vendor::httpd_vendor_info();

=head2 httpd_vendor_info();

Gather vendor and version information for the httpd vendor.

=over 2

=item Output

=over 3

Returns the vendor and version of the httpd vendor.

=back

=back

=cut

sub httpd_vendor_info {
    if ( -x $LITESPEED_PATH ) {
        require Cpanel::CachedCommand;
        my $lshttpd_v = Cpanel::CachedCommand::cachedcommand( $LITESPEED_PATH, '-v' );
        if ( $lshttpd_v =~ m{LiteSpeed/(\S+)\s+(\S+)} ) {
            my $version = $1;
            my $is_open = $2;
            $is_open =~ tr{A-Z}{a-z};
            if ( $is_open eq 'open' ) {
                return ( 'openlitespeed', $version );
            }
            my $patch_version = Cpanel::LoadFile::loadfile($LITESPEED_BUILD_VERSION_FILE) || "";
            chomp($patch_version);
            if ( length $patch_version && $patch_version !~ tr{0-9}{}c ) {
                $version .= '.' . $patch_version;
            }
            return ( 'litespeed', $version );
        }
    }

    if ( -r '/usr/local/lsws/VERSION' ) {
        my $version       = Cpanel::LoadFile::loadfile('/usr/local/lsws/VERSION');
        my $patch_version = Cpanel::LoadFile::loadfile($LITESPEED_BUILD_VERSION_FILE);
        if ( length $patch_version && $patch_version !~ tr{0-9}{}c ) {
            $version .= '.' . $patch_version;
        }
        return ( 'litespeed', $version );
    }

    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
        require Cpanel::ConfigFiles::Apache;    # because httpd_vendor_info() is called at BEGIN time so scripts/updatenow.static-cpanelsync INIT import is too late and the call the facade fails (CPANEL-28458 should address this)
        my $httpd = Cpanel::ConfigFiles::Apache->new->bin_httpd();
        if ( -x $httpd ) {
            require Cpanel::CachedCommand;
            my $httpd_v = Cpanel::CachedCommand::cachedcommand( $httpd, '-v' );
            if ( $httpd_v =~ m{Server\s+version:\s+Apache/([0-9]+\.[0-9]+\.[0-9]+)\s+\(cPanel\)} ) {
                my $apv = $1;
                return ( 'easyapache4', $apv );
            }
        }
    }

    return ( 'unknown', 'unknown' );
}

1;
