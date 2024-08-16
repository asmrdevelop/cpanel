package Cpanel::ObjCache;

# cpanel - Cpanel/ObjCache.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::URL         ();
use Cpanel::SafeFile    ();
use Cpanel::HttpRequest ();
use Cpanel::Logger      ();
use Cpanel::PwCache     ();

$Cpanel::ObjCache::VERSION = '1.1';

my $logger = Cpanel::Logger->new();

sub fetch {
    my ( $url, $key, $ttl, $signed, $speedcheck ) = @_;

    # Default return values
    my $script = '';
    my $mtime  = 0;

    # Ensure storage directories exist
    my $key_dir = _check_key_dir($key);

    # Ensure valid URL argument
    my $resource = Cpanel::URL::parse($url);
    return if !$resource;

    # Minimum TTL of 15 seconds
    if ( !$ttl ) {
        $ttl = 15;
    }
    else {
        $ttl = int $ttl;
        if ( $ttl < 15 ) {
            $ttl = 15;
        }
    }

    my $key_fullpath = "$key_dir/$resource->{'file'}";

    # Check cache first and fetch if necessary
    my $now = time;
    if ( !-e $key_fullpath || -z _ || ( ( stat(_) )[9] + $ttl ) < $now ) {
        $mtime = $now;
        my $httpClient = Cpanel::HttpRequest->new();
        $httpClient->{'hideOutput'}      = 1;
        $httpClient->{'speed_test_file'} = $speedcheck if defined $speedcheck;
        $script                          = $httpClient->request(
            'host'     => $resource->{'host'},
            'url'      => $resource->{'uri'},
            'protocol' => 0,
            'signed'   => $signed ? 1 : 0,
        );

        if ($script) {
            if ( !$key_dir ) {
                return { 'data' => $script, 'mtime' => 0, };
            }

            my $slock = Cpanel::SafeFile::safeopen( \*CFILE, '>', $key_fullpath );
            if ( !$slock ) {
                $logger->warn("Could not write to $key_fullpath: $!");
                return { 'data' => $script, 'mtime' => 0, };
            }
            print CFILE $script;
            Cpanel::SafeFile::safeclose( \*CFILE, $slock );
        }
        else {
            $logger->warn("Object fetch failed for $resource->{'host'}/$resource->{'uri'}");
            return { 'data' => '', 'mtime' => 0, };
        }
    }

    # Cache object is OK, used cached version
    else {
        $mtime = ( stat(_) )[9];
        my $slock = Cpanel::SafeFile::safeopen( \*CFILE, '<', $key_fullpath );
        if ( !$slock ) {
            $logger->warn("Could not read $key_fullpath: $!");
            return { 'data' => '', 'mtime' => 0, };
        }
        $script = do { local $/; <CFILE> };
        Cpanel::SafeFile::safeclose( \*CFILE, $slock );
    }

    return { 'data' => $script, 'mtime' => $mtime };
}

sub fetchcachedobj { goto &fetch; }

sub _check_key_dir {
    my ($key) = @_;
    if ( !defined $key || $key eq '' ) {
        $logger->warn('Invalid arguments, key missing.');
        return;
    }
    else {
        $key =~ s/\.\.//g;
        $key =~ s/\///g;
        if ( !$key ) {
            $logger->warn('Invalid key argument.');
            return;
        }
    }

    my $obj_dir = ( Cpanel::PwCache::getpwuid($>) )[7] . '/.cpobjcache';
    if ( !-e $obj_dir ) {
        unless ( mkdir( $obj_dir, 0700 ) ) {
            $logger->warn("Conflict detected during cache directory initialization. Failed to create $obj_dir directory: $!");
            return;
        }
    }
    elsif ( !-d _ ) {
        $logger->warn("Conflict detected during cache directory initialization. $obj_dir item already exists and is not a directory");
        return;
    }

    my $obj_fullpath = "$obj_dir/$key";
    if ( !-e $obj_fullpath ) {
        unless ( mkdir( $obj_fullpath, 0700 ) ) {
            $logger->warn("Conflict detected in cache directory $obj_dir. Failed to create $key directory: $!");
            return;
        }
    }
    elsif ( !-d _ ) {
        $logger->warn("Conflict detected in cache directory $obj_dir. Target $key already exists.");
        return;
    }
    return $obj_fullpath;
}

1;
