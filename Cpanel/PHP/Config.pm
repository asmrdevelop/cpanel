package Cpanel::PHP::Config;

# cpanel - Cpanel/PHP/Config.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule                  ();
use Cpanel::PwCache                     ();
use Cpanel::PwCache::Build              ();
use Cpanel::PHPFPM::Constants           ();
use Cpanel::Config::userdata::Cache     ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::CachedDataStore             ();
use Cpanel::Exception                   ();

# Made local since we accessing an our in another module is slow
# in tight loops
use constant FIELD_PHP_VERSION   => $Cpanel::Config::userdata::Cache::FIELD_PHP_VERSION;
use constant FIELD_DOMAIN_TYPE   => $Cpanel::Config::userdata::Cache::FIELD_DOMAIN_TYPE;
use constant FIELD_PARENT_DOMAIN => $Cpanel::Config::userdata::Cache::FIELD_PARENT_DOMAIN;
use constant FIELD_DOCROOT       => $Cpanel::Config::userdata::Cache::FIELD_DOCROOT;
use constant FIELD_USER          => $Cpanel::Config::userdata::Cache::FIELD_USER;
use constant FIELD_OWNER         => $Cpanel::Config::userdata::Cache::FIELD_OWNER;

=pod

=encoding utf-8

=head1 NAME

Cpanel::PHP::Config - Fetch the php config for the system and each domain

=head1 SYNOPSIS

 my $php_version_info = Cpanel::PHP::Config::get_php_version_info();
 my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains( [$domain] );
 my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_users( [$user] );
 my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_all_domains();
 my $php_impacted_domains = Cpanel::PHP::Config::get_impacted_domains( domains => \@domains );
 my $php_impacted_domains = Cpanel::PHP::Config::get_impacted_domains( system_default => 1 );

=head1 DESCRIPTION

This module provides a fast way to fetch the php configuration for multiple
users and domains.

=head1 NOTES

This modules requires EasyApache4 and will return empty results if it
is not installed.

=head1 METHODS

=head2 get_php_version_info

Get the current available php versions and the default version

=head3 Arguments

none

=head3 Return Value

A hashref similar to the below:

 {
    'versions' => ['ea-php99','ea-php70'],
    'default'  => 'ea-php99'
 }

=cut

sub get_php_version_info {
    my $php_conf = Cpanel::CachedDataStore::load_ref($Cpanel::PHPFPM::Constants::php_conf_path);
    return {
        'versions' => [ grep ( m{^ea-php[0-9]+}, sort keys %{$php_conf} ) ],
        'default'  => $php_conf->{'default'},
    };
}

=head2 get_impacted_domains()

e.g.

    my $domain_ar = get_impacted_domains( domains => \@domains, system_default => <boolean> );

Get the domains that are impacted by the given domains’ PHP settings and/or the system’s default PHP setting.

Must supply at least one domain or the system as true (otherwise why are you calling this‽).

Passing in the argument exclude_children as true will exclude domains that inherit from the given
domain(s).

Returns an array reference of domains, representing the domains that would be impacted, in the pre-order tree
transversal of the file system. The results do not include domains that were in the domains argument.

e.g.

    get_impacted_domains(domains => ['domain.com']))

Would return something like this:

    [
       'sub.domain.com',
       'another.sub.domain.com',
       'under.another.sub.domain.com',
       'some.sub.domain.com',
        …
    ]

=cut

sub get_impacted_domains {
    my (%args) = @_;

    if ( !$args{system_default} && ( !$args{domains} || !@{ $args{domains} } ) ) {
        die Cpanel::Exception::create( "AtLeastOneOf", [ params => [ "domains", "system_default" ] ] );
    }

    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache();
    my %filtered_cache = map { ( $userdata_cache->{$_}->[FIELD_DOMAIN_TYPE] eq 'parked' ) ? () : ( $_ => $userdata_cache->{$_} ) } keys %$userdata_cache;

    my @roots;
    if ( $args{system_default} ) {
        @roots = map {
            my $type = $filtered_cache{$_}->[FIELD_DOMAIN_TYPE];
            ( $type eq 'main' || $type eq 'addon' ) && ( $filtered_cache{$_}->[FIELD_PHP_VERSION] || 'inherit' ) eq 'inherit' ? $filtered_cache{$_}->[FIELD_DOCROOT] : ()
        } sort keys %filtered_cache;
    }

    for my $domain ( @{ $args{domains} } ) {
        if ( exists $filtered_cache{$domain} ) {
            push @roots, $filtered_cache{$domain}->[FIELD_DOCROOT];
        }
    }

    return [] if !@roots;

    my %docroots;
    my %dir_ver;
    for my $domain ( sort keys %filtered_cache ) {
        push @{ $docroots{ $filtered_cache{$domain}[FIELD_DOCROOT] } }, $domain;    # DO THIS BECAUSE A PATH CAN HAVE MORE THAN ONE DOMAIN!!!
        $dir_ver{ $filtered_cache{$domain}[FIELD_DOCROOT] } = $filtered_cache{$domain}[FIELD_PHP_VERSION];
    }

    my @domains;
    my %seen_paths;
    my %passed_in_domains;
    @passed_in_domains{ @{ $args{domains} } } = ();
    foreach my $root (@roots) {

        my @path_stack;
        push @path_stack, $root;

        while (@path_stack) {
            my $path = pop @path_stack;

            next if $seen_paths{$path};

            if ( exists $docroots{$path} ) {
                push @domains, map { !exists $passed_in_domains{$_} ? $_ : () } @{ $docroots{$path} };
                $seen_paths{$path} = 1;
            }

            next if ( $args{exclude_children} );

            my $depth      = $path =~ tr{/}{/};
            my %candidates = map { $_ =~ m{^\Q$path\E\/}                                               ? ( join( '/', ( split( '/', $_ ) )[ 0 .. $depth + 1 ] ) => 1 ) : () } keys %docroots;
            my @children   = map { !exists $docroots{$_} || ( $dir_ver{$_} || 'inherit' ) eq 'inherit' ? $_                                                            : () } sort keys %candidates;
            push @path_stack, @children;
        }
    }

    return \@domains;
}

=head2 get_php_config_for*

Get the current php configuration for a domain

=head3 Arguments

get_php_config_for_all_domains - none
get_php_config_for_users       - An arrayref of users
get_php_config_for_domains     - An arrayref of domains

=head3 Return Value

A hashref similar to the below:

 {
    'DOMAIN' => bless( {
           'userdata_dir' => '/var/cpanel/userdata/nick',
           'documentroot' => '/home/nick/public_html',
           'phpversion' => 'ea-php99',
           'username' => 'nick',
           'phpversion_or_inherit' => 'inherit',
           'homedir' => '/home/nick',
           'domain_type' => 'main',
           'domain' => 'nickkoston.org',
           'scrubbed_domain' => 'nickkoston_org',
           'config_fname' => '/var/cpanel/userdata/nick/nickkoston.org.php-fpm.yaml'
         }, 'Cpanel::PHP::Config::Domain' ),
    'DOMAIN2' => bless ( {
        ...
    }
    ...
 }

=cut

# Input: none.  Returns all domains
sub get_php_config_for_all_domains {
    return _extract_php_config_from_userdata_cache( scalar Cpanel::Config::userdata::Cache::load_cache() );
}

# Input parameter 0 is a flag, if on it will replace subdomain in the input
# list with the addon equivalent
#
# Input parameter 1 an array of domains to get the php configuration
#
# Example
# [
#   'domain1', 'domain2', 'domain3',
# ]
sub _get_php_config_for_domains {
    my ( $consider_addons, $domains ) = @_;

    my $user;
    if ( scalar @$domains == 1 ) {
        require Cpanel::AcctUtils::DomainOwner::Tiny;
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domains->[0], { default => '' } );
    }
    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache($user);

    my %addons;
    if ($consider_addons) {
        foreach my $key ( keys %{$userdata_cache} ) {
            if ( $userdata_cache->{$key}->[FIELD_DOMAIN_TYPE] eq 'addon' ) {
                $addons{ $userdata_cache->{$key}->[FIELD_PARENT_DOMAIN] } = $key;
            }
        }

        my %list;
        foreach my $domain ( @{$domains} ) {
            $list{$domain} = 1;
        }

        foreach my $sub ( keys %addons ) {
            if ( exists $list{$sub} ) {
                delete $list{$sub};
                $list{ $addons{$sub} } = 1;
            }
        }

        my @ldomains = keys %list;
        $domains = \@ldomains;
    }

    my %wanted_cache    = map  { $_ => $userdata_cache->{$_} } @{$domains};
    my @missing_domains = grep { !$wanted_cache{$_} } @{$domains};
    if (@missing_domains) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Carp');
        die Cpanel::Carp::safe_longmess("Failed to find the domain(s): “@missing_domains”.");
    }

    # query must be converted to for_users query because inherited domains must
    # must have their parents available to resolve correctly.
    my %wanted_users = map { $wanted_cache{$_}->[FIELD_USER] => 1 } keys %wanted_cache;    # via hash == no dupes == not wasting time re-processing the same user for every domain they have
    my $user_domains = get_php_config_for_users( [ keys %wanted_users ] );

    # filter the user domains to just the queried ones.
    my %return_domains = map { $_ => $user_domains->{$_} } @{$domains};
    return \%return_domains;
}

# Input an array of domains to get the php configuration
#
# Example
# [
#   'domain1', 'domain2', 'domain3',
# ]
sub get_php_config_for_domains {
    return _get_php_config_for_domains( 0, @_ );
}

# Input an array of domains to get the php configuration
#
# Example
# [
#   'domain1', 'domain2', 'domain3',
# ]
#
# The difference with this sub and get_php_config_for_domains and
# get_php_config_for_domains_consider_addons, this one will replace
# the subdomain name in the domains list for the addon domain
# because that is needed for fpm

sub get_php_config_for_domains_consider_addons {
    return _get_php_config_for_domains( 1, @_ );
}

# Input: arrayref of users,  Returns all domains for the users
sub get_php_config_for_users {
    my ($users_ref) = @_;
    return _get_php_config_for_user( $users_ref->[0] ) if scalar @{$users_ref} == 1;

    my %wanted_users   = map { $_ => 1 } @{$users_ref};
    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache();
    my @wanted_domains = grep { $wanted_users{ $userdata_cache->{$_}->[0] } } keys %$userdata_cache;
    my %filtered_userdata;

    # CREATE A COPY INSTEAD OF MODIFYING THE CACHE!!!! modifying the cache for usera and userb means the data won't contain the info for userc anymore
    @filtered_userdata{@wanted_domains} = @{$userdata_cache}{@wanted_domains};
    return _extract_php_config_from_userdata_cache( \%filtered_userdata );
}

# Do not call directly
# Input is a single user
sub _get_php_config_for_user {
    my ($user) = @_;

    my $userdata_cache = Cpanel::Config::userdata::Cache::load_cache($user);

    # If the cache wasn’t available, try to build it, then retry:
    if ( !$userdata_cache ) {
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update($user);

        $userdata_cache = Cpanel::Config::userdata::Cache::load_cache($user);
    }

    if ( !$userdata_cache ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Failed to fetch userdata for “$user”");
    }

    return _extract_php_config_from_userdata_cache($userdata_cache);
}

sub _extract_php_config_from_userdata_cache {
    my ($userdata_cache) = @_;

    my $php_version_info = get_php_version_info();
    my %php_config_by_domain;

    my %HOMES;
    my %USERS = map { $userdata_cache->{$_}[FIELD_USER] => 1 } keys %{$userdata_cache};

    if ( scalar keys %USERS > 3 ) {
        %HOMES = map { $_->[0] => $_->[7] } @{ Cpanel::PwCache::Build::fetch_pwcache() };
    }
    else {
        %HOMES = map { ( $_, Cpanel::PwCache::gethomedir($_) )[ 0, 1 ] } keys %USERS;
    }

    my %excluded_domains = map {
        my $type = $userdata_cache->{$_}[FIELD_DOMAIN_TYPE];
        $type eq 'parked'
          ? ( $_ => 1 )                                                               # do not include parked domains
          : $type eq 'addon' ? ( $userdata_cache->{$_}[FIELD_PARENT_DOMAIN] => 1 )    # do not include addon domain's sub domain since they can't be set (only the addon domain can be set)
          : ()                                                                        # include everything else
    } keys %{$userdata_cache};

    my %docroots = map { $excluded_domains{$_} ? () : ( $userdata_cache->{$_}[FIELD_DOCROOT] => [ @{ $userdata_cache->{$_} }, $_ ] ) } keys %$userdata_cache;

    my %dirname_memory;
    foreach my $domain ( grep { !$excluded_domains{$_} } keys %$userdata_cache ) {
        my $userdata        = $userdata_cache->{$domain};
        my $user            = $userdata->[FIELD_USER];
        my $owner           = $userdata->[FIELD_OWNER];
        my $homedir         = $HOMES{$user} or next;
        my $scrubbed_domain = $domain;
        $scrubbed_domain =~ tr{.}{_};

        my $php_version    = $userdata->[FIELD_PHP_VERSION];
        my $version_source = { domain => $domain };
        if ( ( $userdata->[FIELD_PHP_VERSION] || 'inherit' ) eq 'inherit' ) {
            $php_version = 'inherit';
            my @dirs = split( m{/+}, $userdata->[FIELD_DOCROOT] );
            my $parent_dir;

            # This used to use dirname to walk up the path, however this was 2 orders of magnitude slower
            # so it made more sense to presplit the path
            while ( pop @dirs && $php_version eq 'inherit' ) {
                $parent_dir = join( '/', @dirs ) or last;
                if ( exists $docroots{$parent_dir} && ( ( $docroots{$parent_dir}->[FIELD_PHP_VERSION] || 'inherit' ) ne 'inherit' ) ) {
                    $php_version    = $docroots{$parent_dir}->[FIELD_PHP_VERSION];
                    $version_source = { domain => $docroots{$parent_dir}->[-1] };
                }
            }
        }
        if ( $php_version eq 'inherit' ) {
            $php_version    = $php_version_info->{'default'};
            $version_source = { "system_default" => 1 };
        }

        #
        # Each domain's php config is a Cpanel::PHP::Config::Domain object
        # The current design of this system makes it too slow for us to access
        # the attributes as accessors at this time.  The only accessor the object
        # currently provides is 'scrubbed_domain'
        #
        # The blessing of the data allows functions that consume this data
        # to ensure that the data being passed to them is being generated
        # by this module.  This reduces the risk that future development
        # will bypass this module and try to obtain the data directly
        # which would make this system less maintainable.
        #
        $php_config_by_domain{$domain} = bless {
            'scrubbed_domain'   => $scrubbed_domain,
            'domain'            => $domain,
            'username'          => $user,
            'owner'             => $owner,
            'userdata_dir'      => "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user",
            'config_fname'      => "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/${domain}.php-fpm.yaml",
            'domain_type'       => $userdata->[FIELD_DOMAIN_TYPE],
            'phpversion'        => $php_version,
            'phpversion_source' => $version_source,

            # I would like this to be deprecated
            'phpversion_or_inherit' => ( $userdata->[FIELD_PHP_VERSION] || 'inherit' ),
            'documentroot'          => $userdata->[FIELD_DOCROOT],
            'homedir'               => $homedir,
          },
          'Cpanel::PHP::Config::Domain';
    }

    return \%php_config_by_domain;
}

package Cpanel::PHP::Config::Domain;

sub scrubbed_domain { return $_[0]->{'scrubbed_domain'} }

1;
