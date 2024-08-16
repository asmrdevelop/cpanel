package Cpanel::OpenSSL::Base;

# cpanel - Cpanel/OpenSSL/Base.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();
use Cpanel::Debug      ();

our @SSL_PATHS = qw(
  /usr/bin/openssl
  /usr/local/bin/openssl
  /opt/bin/openssl
  /opt/openssl/bin/openssl
  /usr/bin/ssleay
  /usr/local/ssl/bin/ssleay
  /usr/local/ssl/bin/openssl
);
our $CACHE_LIMIT = 7 * 86400;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    bless $self, $class;

    $self->{'sslbin'} = find_ssl();
    if ( !$self->{'sslbin'} ) {
        Cpanel::Debug::log_warn('No OpenSSL binary located');
        return;
    }

    if ( $args{'extended'} ) {

        Cpanel::LoadModule::load_perl_module('Cpanel::CachedCommand');

        # Limit this to 7 days since we no longer support cent5
        my $version_output = Cpanel::CachedCommand::cachedmcommand( $CACHE_LIMIT, $self->{'sslbin'}, 'version' );
        if ( $version_output =~ m/^openssl\s+(\S+)\s+/i ) {
            $self->{'version'} = $1;
        }
        else {
            $self->{'version'} = $version_output;
        }
    }
    return $self;
}

my $ssl_bin_cache;                                              # To prevent unnecessary stats
sub _reset_ssl_bin_cache { $ssl_bin_cache = undef; return; }    #for testing

sub find_ssl {
    my ($next_in_path) = @_;

    if ( $ssl_bin_cache && !$next_in_path ) {
        return $ssl_bin_cache;
    }

    # Strange "get next openssl" logic needed for 0.9.8h workaround
    my $prev_ssl_bin = $ssl_bin_cache;
    undef $ssl_bin_cache;

    my $locations = _get_ssl_locations($prev_ssl_bin);
    foreach my $ssl ( @{$locations} ) {
        if ( -x $ssl ) {
            $ssl_bin_cache = $ssl;
            return $ssl;
        }
    }
    if ( !$ssl_bin_cache && $prev_ssl_bin ) {
        $ssl_bin_cache = $prev_ssl_bin;
        Cpanel::Debug::log_warn("Unable to find alternative OpenSSL version.");
        return;
    }
    return;
}

sub _get_ssl_locations {
    my ($prev_ssl_bin) = @_;
    my @ssl_locations = @SSL_PATHS;

    # Workaround for 0.9.8h issues
    if ($prev_ssl_bin) {
        Cpanel::Debug::log_info("Searching for alternative to $prev_ssl_bin OpenSSL binary.");
        my @new_ssl_locations;
        my $found_last;
        foreach my $ssl (@ssl_locations) {
            if ( !$found_last ) {
                if ( $ssl ne $prev_ssl_bin ) {
                    next;
                }
                else {
                    $found_last = 1;
                    next;
                }
            }
            push @new_ssl_locations, $ssl;
        }
        if ($found_last) {
            @ssl_locations = @new_ssl_locations;
        }
        else {
            Cpanel::Debug::log_warn("Work around failed. Unable to find alternative OpenSSL binary.");
        }
    }

    return wantarray ? @ssl_locations : \@ssl_locations;
}

1;
