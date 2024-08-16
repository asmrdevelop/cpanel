package Whostmgr::Email::DomainForwarders;

# cpanel - Whostmgr/Email/DomainForwarders.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile                ();
use Cpanel::Exception               ();
use Cpanel::ConfigFiles             ();
use Cpanel::WildcardDomain::Tiny    ();
use Cpanel::Config::LoadUserDomains ();

sub list_domain_forwarders_for_domain {
    my $domain = shift;
    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['domain'] ) if !$domain;

    return _fetch_domain_forwarders( [$domain] );
}

sub list_domain_forwarders_for_user {
    my $user = shift;
    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['user'] ) if !$user;

    my $userdomains       = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my @this_user_domains = grep { $userdomains->{$_} eq $user } keys %{$userdomains};

    return _fetch_domain_forwarders( \@this_user_domains );
}

# This reimplements functionality available in a cPanel function because that
# code only works for the current user.  This reimplementation of
# Cpanel::API::Email::_listdforwards reseller to get the domain forwarders for
# a specific user.
#
# NOTE: This does not call Cpanel::Email::Config::Perms::secure_mail_db_file()
# so PERM validation should be done outside of this call.  This differs from
# Cpanel::API::Email::_listdforwards().
sub _fetch_domain_forwarders {
    my $domains_ar = shift;

    my $forwarders;
    foreach my $domain ( @{$domains_ar} ) {
        next if Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain);

        my $vllock = Cpanel::SafeFile::safeopen( my $vda_fh, '<', "$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/$domain" );
        next if !$vllock;

        while (<$vda_fh>) {
            s/[\s\n]*//g;
            my ( $dest, $finaldest ) = split( /:/, $_, 2 );
            if ( $dest eq $domain ) {
                $forwarders->{$dest} = $finaldest;
            }
        }
        Cpanel::SafeFile::safeclose( $vda_fh, $vllock );
    }
    return $forwarders;
}

1;
