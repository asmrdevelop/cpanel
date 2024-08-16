package Cpanel::HttpUtils::AllIps;

# cpanel - Cpanel/HttpUtils/AllIps.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context                 ();
use Cpanel::Config::userdata::Cache ();
use Cpanel::Config::userdata::Load  ();
use Cpanel::Config::WebVhosts       ();

use constant USER_FOR_UNOWNED_DOMAINS => 'nobody';
use constant _BLACKLIST               => ( '*', '' );

=encoding utf-8

=head1 NAME

Cpanel::HttpUtils::AllIps

=head1 SYNOPSIS

    my @http_ipv4s = Cpanel::HttpUtils::AllIps::get_all_ipv4s();

=head1 FUNCTIONS

=head2 @ips = get_all_ipv4s()

Returns all IPv4 addresses that are in web vhost configurations.

=cut

sub get_all_ipv4s {
    Cpanel::Context::must_be_list();

    my $userdata   = Cpanel::Config::userdata::Cache::load_cache();
    my %ips_lookup = map { ( split( /:/, $userdata->{$_}->[5] ) )[0] => undef } keys %$userdata;

    # Move to Cpanel::Config::userdata::Exists::user_exists
    if ( Cpanel::Config::userdata::Load::user_exists(USER_FOR_UNOWNED_DOMAINS) ) {
        local $@;

        # CPANEL-24866: warn on failure to load WebVhosts for
        # USER_FOR_UNOWNED_DOMAINS instead of throw. This can be relevant if,
        # e.g., the user’s userdata dir exists but there is no “main” file.
        # This is an invalid configuration, but it does happen, and it
        # seems better to tolerate the error rather than to fail on it.
        eval { @ips_lookup{ _read_user_http_ips(USER_FOR_UNOWNED_DOMAINS) } = (); };
        if ( my $err = $@ ) {
            require Cpanel::Debug;
            Cpanel::Debug::log_warn($err);
        }
    }

    delete @ips_lookup{ _BLACKLIST() };

    return keys %ips_lookup;
}

sub _read_user_http_ips {
    my ($user) = @_;

    my @ips;

    my $wvh = Cpanel::Config::WebVhosts->load($user);
    for my $vh_name ( $wvh->main_domain(), $wvh->subdomains() ) {
        for my $fn ( 'load_userdata_domain', 'load_ssl_domain_userdata' ) {
            my $vh_conf = Cpanel::Config::userdata::Load->can($fn)->( $user, $vh_name );
            if ( $vh_conf && %$vh_conf && $vh_conf->{'ip'} ) {
                push @ips, $vh_conf->{'ip'};
            }
        }
    }

    return @ips;
}

1;
