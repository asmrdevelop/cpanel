package Cpanel::Domain::Mail;

# cpanel - Cpanel/Domain/Mail.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

my %cache;

sub is_mail_subdomain {
    my ($domain) = @_;
    return index( $domain, 'mail.' ) == 0 ? 1 : 0;
}

sub make_mail_subdomain {
    my ($domain) = @_;
    return is_mail_subdomain($domain) ? $domain : 'mail.' . $domain;
}

sub mail_subdomain_exists {
    my ($domain) = @_;

    return $cache{$domain} if exists $cache{$domain};

    require Cpanel::AcctUtils::DomainOwner::Tiny if !$INC{'Cpanel/AcctUtils/DomainOwner/Tiny.pm'};
    my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => '' } );
    return 0 if !$owner;
    my $mail_subdomain = make_mail_subdomain($domain);
    my $domain_data;
    require Cpanel::Config::userdata::Constants;

    if ( -x "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$owner" ) {
        require Cpanel::Config::userdata::Load if !$INC{'Cpanel/Config/userdata/Load.pm'};
        if ( Cpanel::Config::userdata::Load::user_has_domain( $owner, $domain ) ) {
            $domain_data = Cpanel::Config::userdata::Load::load_userdata( $owner, $domain );
        }
        else {
            my $real_domain = try { Cpanel::Config::userdata::Load::get_real_domain( $owner, $domain ); };

            # If we cannot read the userdata, return 0.
            return 0 unless defined $real_domain;
            if ( $real_domain eq $domain ) {
                return ( $cache{$domain} = 0 );
            }
            $domain_data = Cpanel::Config::userdata::Load::load_userdata( $owner, $real_domain );
        }
        return ( $cache{$domain} = ( grep { $_ eq $mail_subdomain } split( m{ }, $domain_data->{'serveralias'} ) ) ? 1 : 0 );
    }

    # If we cannot read the userdata we have to make our best guess if its a subdomain
    my @parent = split( m{\.}, $domain );
    shift @parent;
    my $parent_domain       = join( '.', @parent );
    my $parent_domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $parent_domain, { default => '' } );
    return $parent_domain_owner eq $owner ? 0 : 1;
}

sub clear_cache {
    %cache = ();
    return 1;
}

1;
