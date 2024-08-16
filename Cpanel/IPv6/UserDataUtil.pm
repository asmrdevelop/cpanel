package Cpanel::IPv6::UserDataUtil;

# cpanel - Cpanel/IPv6/UserDataUtil.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::userdata::Guard    ();
use Cpanel::Config::userdata::Load     ();
use Cpanel::Config::WebVhosts          ();
use Cpanel::AcctUtils::Account         ();
use Cpanel::IPv6::Normalize            ();
use Cpanel::ConfigFiles::Apache::vhost ();
use Cpanel::IPv6::UserDataUtil::Key    ();
use Cpanel::LoadModule                 ();

my $locale;

#
# Add the new IPv6 address to the user data files
#
sub add_ipv6_for_user {
    my ( $user, $ipv6, $dedicated ) = @_;

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};

        $locale ||= Cpanel::Locale->get_handle();

        return ( 0, $locale->maketext('Account does not exist.') );
    }

    my ( $ret, $address ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ipv6);
    if ( $ret == 1 ) {
        $ipv6 = $address;
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};

        $locale ||= Cpanel::Locale->get_handle();

        return ( 0, $locale->maketext( "Not a valid IPv6 address: [_1]", ( defined $ipv6 ? $ipv6 : '<undef>' ) ) );
    }

    my $vhconf = Cpanel::Config::WebVhosts->load($user);

    # Get the main domain and test if they already have an ipv6.main-domain configured
    my $main_domain = $vhconf->main_domain();

    my $has_ipv6_subdomain = _vhconf_has_ipv6_sub($vhconf);

    # IPv6 Data ref
    $dedicated = $dedicated ? 1 : 0;
    my $ipv6_data = { 'dedicated' => $dedicated };

    foreach my $vhost ( $main_domain, $vhconf->subdomains() ) {

        # IPv6 alias which we add if this is the main domain
        # and they do not have a sub/parked/addon domain equal to it alreaqdy
        my $alias_to_add = ( $vhost eq $main_domain && !$has_ipv6_subdomain ) ? "ipv6.$main_domain" : 0;

        # Load the data file for that domain
        my $guard = Cpanel::Config::userdata::Guard->new( $user, $vhost );
        my $data  = $guard->data();

        _add_ipv6_info_to_user_data( $data, $ipv6, $ipv6_data, $alias_to_add );

        $guard->save();

        # If domain has an SSL config, enable it there too
        my $has_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $vhost );
        next unless $has_ssl;

        my $ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $user, $vhost );
        my $ssl_data  = $ssl_guard->data();

        _add_ipv6_info_to_user_data( $ssl_data, $ipv6, $ipv6_data, $alias_to_add );

        $ssl_guard->save();
    }

    require Cpanel::Config::userdata::UpdateCache;
    Cpanel::Config::userdata::UpdateCache::update($user);

    return 1;
}

#
# Remove any IPv6 addresses to the user data files
#
sub remove_ipv6_for_user {
    my ($user) = @_;

    if ( !Cpanel::AcctUtils::Account::accountexists($user) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
        $locale ||= Cpanel::Locale->get_handle();

        return ( 0, $locale->maketext('Account does not exist.') );
    }

    my $vhconf = Cpanel::Config::WebVhosts->load($user);

    # Get the main domain and test if they already have an ipv6.main-domain configured
    my $main_domain = $vhconf->main_domain();
    my $ipv6_alias  = "ipv6.$main_domain";

    my $has_ipv6_subdomain = _vhconf_has_ipv6_sub($vhconf);

    foreach my $vhost ( $main_domain, $vhconf->subdomains() ) {

        # Load the data file for that domain
        my $guard = Cpanel::Config::userdata::Guard->new( $user, $vhost );
        my $data  = $guard->data();

        _purge_ipv6_info_from_user_data( $data, $ipv6_alias );

        $guard->save();

        # Remove IPV6 for SSL as well if needed
        my $has_ssl = Cpanel::Config::userdata::Load::user_has_ssl_domain( $user, $vhost );
        next unless $has_ssl;

        my $ssl_guard = Cpanel::Config::userdata::Guard->new_ssl( $user, $vhost );
        my $ssl_data  = $ssl_guard->data();

        _purge_ipv6_info_from_user_data( $ssl_data, $ipv6_alias );

        $ssl_guard->save();
    }

    require Cpanel::Config::userdata::UpdateCache;
    Cpanel::Config::userdata::UpdateCache::update($user);

    return 1;
}

#
# Add the ipv6 info and alias info to the user data
#
sub _add_ipv6_info_to_user_data {
    my ( $data, $ipv6, $ipv6_data, $ipv6_alias ) = @_;

    # Add the ipv6 info
    if ( ref $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} eq 'HASH' ) {
        $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key}{$ipv6} = $ipv6_data;
    }
    else {
        $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} = { $ipv6 => $ipv6_data };
    }

    # If an alias is supplied, add it to the server alias
    if ($ipv6_alias) {

        # add the alias to the server alias if it is not already present
        my %aliases = map { $_ => 1 } split( /\s/, $data->{'serveralias'} );
        $aliases{$ipv6_alias} = 1;
        $data->{'serveralias'} = join( ' ', keys %aliases );
    }

    return;
}

#
# Remove ipv6 info from the block of user data
#
sub _purge_ipv6_info_from_user_data {
    my ( $data, $ipv6_alias ) = @_;

    # Remove IPv6
    delete $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key};

    # If we specify an ipv6 alias, remove it from the list
    if ( $ipv6_alias and $data->{'serveralias'} ) {
        my %aliases = map { $_ => 1 } split( /\s/, $data->{'serveralias'} );
        delete $aliases{$ipv6_alias};
        $data->{'serveralias'} = join( ' ', keys %aliases );
    }

    return;
}

#
# If the new sub/parked domain is ipv6.main-domain, this will conflict with the
# ServerAlias and DNS info we will have already have had inplace for ipv6.main-domain
#
sub fix_possible_new_domain_issues {
    my ( $user, $domain ) = @_;

    my $vhconf = Cpanel::Config::WebVhosts->load($user);

    # Get the main domain and test if they already have an ipv6.main-domain configured
    my $main_domain = $vhconf->main_domain();

    my $ipv6_alias = 'ipv6.' . $main_domain;

    # If the new domain is not ipv6 (for a subdomain) or
    # ipv6.main-domain (for a parked domain) then we don't need to be doing this
    return unless ( $domain eq 'ipv6' or $domain eq $ipv6_alias );

    # Return if they already have an ipv6 domain,
    # If they are trying to add another identical domain, then it will error
    # out, and we do not want remove ServerAliases & DNS entries
    #
    # XXX: ^^ Huh? We’re about to remove ServerAlias entries …
    # presumably because there *is* now “ipv6.$domain” in userdata.
    return if _vhconf_has_ipv6_sub($vhconf);

    my $guard = Cpanel::Config::userdata::Guard->new( $user, $main_domain );
    my $data  = $guard->data();

    # If they don't have ipv6, then nothing to do either
    return unless $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key};

    # Remove the IPv6 alias
    my %aliases = map { $_ => 1 } split( /\s/, $data->{'serveralias'} );
    delete $aliases{$ipv6_alias};
    $data->{'serveralias'} = join( ' ', keys %aliases );

    # Save data & update cache
    $guard->save();
    require Cpanel::Config::userdata::UpdateCache;
    Cpanel::Config::userdata::UpdateCache::update($user);

    # Propagate changes to apache config
    Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);

    return;
}

#
# If the user had a sub/parked domain named ipv6.main-domain, then we would not
# have set up the special ServerAlias & dns info for it since this is taken
# care of otherwise with the existence of the domain.
# If they are later wanting to remove that domain, we need to put this all
# back in place
#
sub fix_possible_remove_domain_issues {
    my ( $user, $domain ) = @_;

    my $main_domain = Cpanel::Config::WebVhosts->load($user)->main_domain();

    my $ipv6_alias = 'ipv6.' . $main_domain;

    # If the new domain is not ipv6 (for a subdomain) or
    # ipv6.main-domain (for a parked domain) then we don't need to be doing this
    return unless ( $domain eq 'ipv6' or $domain eq $ipv6_alias );

    my $guard = Cpanel::Config::userdata::Guard->new( $user, $main_domain );
    my $data  = $guard->data();

    # If they don't have ipv6, then nothing to do either
    return unless $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key};

    my $ipv6_addr = ( keys %{ $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} } )[0];
    return unless $ipv6_addr;

    # Add our IPv6 alias
    my %aliases = map { $_ => 1 } split( /\s/, $data->{'serveralias'} );
    $aliases{$ipv6_alias} = 1;
    $data->{'serveralias'} = join( ' ', keys %aliases );

    # Save data & update cache
    $guard->save();
    require Cpanel::Config::userdata::UpdateCache;
    Cpanel::Config::userdata::UpdateCache::update($user);

    # Propagate changes to apache config
    Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);

    return;
}

sub _vhconf_has_ipv6_sub {
    my ($vhconf) = @_;

    my $ipv6_sub = 'ipv6.' . $vhconf->main_domain();

    return 0 + grep { $_ eq $ipv6_sub } @{ $vhconf->all_created_domains_ar() };
}

1;
