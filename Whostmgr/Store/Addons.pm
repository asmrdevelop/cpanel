package Whostmgr::Store::Addons;

# cpanel - Whostmgr/Store/Addons.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $cache_file = '/var/cpanel/caches/store_licenses.json.cache';

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub get_license_with_cache {
    my $response_content;

    # Use the cached data if it was modified within the last 12 hours
    if ( -f $cache_file && -s _ && ( time - ( stat(_) )[9] < 43200 ) ) {
        $response_content = _load_results_from_cache();
    }
    else {
        require Cpanel::LicenseAuthn;
        local $@;
        my @secret   = Cpanel::LicenseAuthn::get_id_and_secret('cpstore');
        my $response = eval {
            require Cpanel::HTTP::Client;
            my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
            require Cpanel::Config::Sources;

            # For testing on some KVM sandboxes, we need to pass the ip= arg (only avail to internal IPs) since the mainserverip and IP you get from http://branch-build.dev.cpanel.net/myip
            # can differ.

            my $license_url;
            if ( -f '/var/cpanel/tmp/testing' ) {

                # Testing URL (ip= arg only available to internal network machines)
                require Cpanel::DIp::LicensedIP;
                my $mainserverip = Cpanel::DIp::LicensedIP::get_license_ip();
                $license_url = sprintf( "%s/api/addons?ip=%s", Cpanel::Config::Sources::get_source('VERIFY_URL'), $mainserverip );
            }
            else {
                # Public URL
                $license_url = sprintf( "%s/api/addons", Cpanel::Config::Sources::get_source('VERIFY_URL') );
            }
            $http->get(
                $license_url,
                { headers => { 'Authorization' => "License @secret" } }
            );
        };
        return ( 0, $@ ) if $@;

        $response_content = $response->{'content'};

        # Save response to cache file
        _save_response_to_cache($response_content);
    }
    require JSON::XS;
    my $results = eval { JSON::XS::decode_json($response_content) };

    return ( 0, $@ ) if $@;
    if ( ( ref $results ) ne 'HASH' ) {
        return ( 0, "Invalid response in results\n" );
    }
    return ( 1, $results );
}

sub _load_results_from_cache {
    my $data;
    if ( open( my $cache_fh, '<', $cache_file ) ) {
        while (<$cache_fh>) {
            $data .= $_;
        }
        close($cache_fh);
    }
    else {
        return '';
    }
    return $data;
}

sub _save_response_to_cache {
    my ($data) = @_;
    if ( open( my $cache_fh, '>', $cache_file ) ) {
        print $cache_fh $data;
        close($cache_fh);
    }
    else {
        return 0;
    }
    return 1;
}

sub expire_license_cache {
    unlink $cache_file;
    return 1 if !-e $cache_file;
    return 0;
}

1;

__END__

=head1 NAME

Whostmgr::Store::Addons - Handles getting and caching queries to the store license server

=head1 SYNOPSIS

  my $handler = Whostmgr::Store::Addons->new();

  my( $rc, $results ) = $handler->get_license_with_cache();

=head1 DESCRIPTION

This module handles the query to the store license server (/api/addons) with caching of results.
The main purpose of this is to limit the number of requests to the license server to 1 in any 12 hour period, so
that regardless of how many addons we are checking for, we don't melt the license server with requests.

=head1 METHODS

=over 4

=item new

Constructor method used normally, takes no arguments

=item get_license_with_cache

Checks the cache size and time and returns it if younger than 12 hours.
If the cache is older than 12 hours, it will make the request to the server and cache the result.

=item expire_license_cache

Deletes the cache file

=item _save_response_to_cache

Private function to save the data from the query to the cache file

=item _load_results_from_cache

Private function to load the data from the cache file

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2022, cPanel, L.L.C. All rights reserved.
