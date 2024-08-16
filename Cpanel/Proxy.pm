package Cpanel::Proxy;

# cpanel - Cpanel/Proxy.pm                         Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile                     ();
use Cpanel::DnsUtils::AskDnsAdmin        ();
use Cpanel::DnsUtils::Constants          ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::Config::HasCpUserFile        ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::ConfigFiles                  ();
use Cpanel::DnsUtils::Install            ();
use Cpanel::IPv6::User                   ();
use Cpanel::Sys::Hostname                ();
use Cpanel::Proxy::Tiny                  ();
use Cpanel::Set                          ();

my $DOMAINS_PER_BATCH = Cpanel::DnsUtils::Constants::SYNCZONES_BATCH_SIZE();

*get_known_proxy_subdomains = *Cpanel::Proxy::Tiny::get_known_proxy_subdomains;

sub setup_all_proxy_subdomains {
    my %OPTS = @_;
    delete $OPTS{'user'};
    delete $OPTS{'domain'};

    my %localdomains = map { $_ => 1 } split( /\n/, Cpanel::LoadFile::loadfile($Cpanel::ConfigFiles::LOCALDOMAINS_FILE) );

    my $domains_for_proxy_subdomains = _collect_domains_for_proxy_subdomains();

    my %root_domains = map { $_ => ( ( $_ =~ tr/\.// ) > 1 ? ( join( '.', ( split( m/\./, $_ ) )[ -2, -1 ] ) ) : $_ ) }
      keys %$domains_for_proxy_subdomains;

    my @local_domains_to_process  = sort { $root_domains{$a} cmp $root_domains{$b} } grep { $localdomains{$_} } keys %$domains_for_proxy_subdomains;
    my @remote_domains_to_process = sort { $root_domains{$a} cmp $root_domains{$b} } grep { !$localdomains{$_} } keys %$domains_for_proxy_subdomains;

    my ( @all_results, @reload_list );

    while ( my @domain_batch = splice( @local_domains_to_process, 0, $DOMAINS_PER_BATCH ) ) {
        my ( $status, $errormsgs, $results ) = setup_proxy_subdomains(
            %OPTS,
            'domains'    => { map { $_ => $domains_for_proxy_subdomains->{$_} } @domain_batch },
            'skipreload' => 1
        );

        die $errormsgs if !$status;

        push @all_results, @{ $results->{'domain_status'} };
        push @reload_list, @{ $results->{'zones_modified'} };
    }

    while ( my @domain_batch = splice( @remote_domains_to_process, 0, $DOMAINS_PER_BATCH ) ) {
        my $subdomains_ref;
        if ( $OPTS{'subdomain'} ) {
            if ( ref $OPTS{'subdomain'} ) {
                $subdomains_ref = delete $OPTS{'subdomain'};
            }
            else {
                $subdomains_ref = [ delete $OPTS{'subdomain'} ];
            }
        }
        else {
            my $known_proxy_subdomains_ref = get_known_proxy_subdomains( \%OPTS );

            # If they did not specify subdomains explicitly
            # then we exclude autoconfig and autodiscover
            # for non-local domains
            $subdomains_ref = [ keys %{$known_proxy_subdomains_ref} ];
        }
        @{$subdomains_ref} = grep( !m{^(?:autoconfig|autodiscover)$}, @{$subdomains_ref} );
        last if !@{$subdomains_ref};
        my ( $status, $errormsgs, $results ) = setup_proxy_subdomains(
            %OPTS,
            'subdomain'  => $subdomains_ref,
            'domains'    => { map { $_ => $domains_for_proxy_subdomains->{$_} } @domain_batch },
            'skipreload' => 1
        );
        push @all_results, @{ $results->{'domain_status'} };
        push @reload_list, @{ $results->{'zones_modified'} };
    }

    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RELOADZONES', 0, join( ',', @reload_list ) )
      unless $OPTS{'skipreload'} || !@reload_list;

    return [ sort { $a->{'domain'} cmp $b->{'domain'} } @all_results ];
}

sub remove_all_proxy_subdomains {
    return setup_all_proxy_subdomains( @_, 'delete' => 1 );
}

sub remove_proxy_subdomains {
    return setup_proxy_subdomains( @_, 'delete' => 1 );
}

# XXX FIXME TODO: Refactor - CPANEL-29624
sub setup_proxy_subdomains {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my $user         = $OPTS{'user'};
    my $domain       = $OPTS{'domain'};
    my $domain_owner = $OPTS{'domain_owner'};

    my $domains = $OPTS{'domains'};
    my $delete  = $OPTS{'delete'};

    # This is a prepopulated list of zones
    my $zone_ref = ( $OPTS{'zone_ref'} || 0 );

    my $old_autodiscover_host = $OPTS{'old_autodiscover_host'};
    my $old_hostname          = $OPTS{'old_hostname'};

    # Deterimines if we should reload the server
    my $skipreload = ( $OPTS{'skipreload'} || 0 );
    my $noreplace  = defined $OPTS{'no_replace'} ? $OPTS{'no_replace'} : 0;

    my $delete_disabled = $OPTS{'delete_disabled'};

    my @relevant_service_subdomains;
    my @service_subdomains_to_delete;

    my %domains_for_proxy_subdomains;

    my $known_proxy_subdomains_ref;

    if ($delete_disabled) {

        # Currently we only enter this block when we are restoring service subdomains (AKA proxy subdomains)
        # during an account restore.  Since the target server (the one this code runs on) may have a different
        # set of service subdomains enabled than the source server we need to remove any superfluous service
        # subdomains at this time.
        if ( $OPTS{'include_disabled'} ) {
            die 'Can’t use “include_disabled” and “delete_disabled” together!';
        }
        elsif ( $OPTS{'subdomain'} ) {
            die 'Can’t use “subdomain” and “delete_disabled” together!';
        }

        $known_proxy_subdomains_ref = get_known_proxy_subdomains( { include_disabled => 1 } );

        my $enabled_hr = get_known_proxy_subdomains();

        @service_subdomains_to_delete = Cpanel::Set::difference(
            [ keys %$known_proxy_subdomains_ref ],
            [ keys %$enabled_hr ],
        );
    }
    else {
        $known_proxy_subdomains_ref = get_known_proxy_subdomains( \%OPTS );
    }

    if ( $OPTS{'subdomain'} ) {    # this is the service (formerly proxy) subdomain

        if ( ref $OPTS{'subdomain'} eq 'ARRAY' ) {
            foreach my $proxy_subdomain ( @{ $OPTS{'subdomain'} } ) {
                if ( exists $known_proxy_subdomains_ref->{$proxy_subdomain} ) {
                    push @relevant_service_subdomains, $proxy_subdomain;
                }
                else {
                    return ( 0, "$proxy_subdomain is not a known service subdomain" );
                }
            }
        }
        else {
            my $proxy_subdomain = $OPTS{'subdomain'};
            if ( exists $known_proxy_subdomains_ref->{$proxy_subdomain} ) {
                push @relevant_service_subdomains, $proxy_subdomain;
            }
            else {
                return ( 0, "$proxy_subdomain is not a known service subdomain" );
            }
        }
    }
    else {

        # If they don't tell us which ones do them all
        @relevant_service_subdomains = keys %{$known_proxy_subdomains_ref};
    }

    my ( $has_ipv6, $ipv6 );
    if ($user) {
        my $cpuser_ref;
        if ( Cpanel::Config::HasCpUserFile::has_cpuser_file($user) ) {
            $cpuser_ref                                              = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
            %domains_for_proxy_subdomains                            = map { $_ => 'all' } @{ $cpuser_ref->{'DOMAINS'} };
            $domains_for_proxy_subdomains{ $cpuser_ref->{'DOMAIN'} } = 'main';
        }
        else {
            return ( 0, "The user $user does not exist" );
        }
        ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::User::get_user_ipv6_address( $user, $cpuser_ref->{'DOMAIN'} );
    }
    elsif ($domain) {
        my $found_domain_type;
        $domain_owner ||= Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => '' } );
        if ($domain_owner) {
            my $cpuser_ref;
            require Cpanel::Config::LoadCpUserFile;
            if ( $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($domain_owner) ) {
                if ( $cpuser_ref->{'DOMAIN'} eq $domain ) {
                    $found_domain_type            = 1;
                    %domains_for_proxy_subdomains = ( $domain => 'all' );
                }
                elsif ( grep { $_ eq $domain } @{ $cpuser_ref->{'DOMAINS'} } ) {
                    $found_domain_type            = 1;
                    %domains_for_proxy_subdomains = ( $domain => 'all' );
                }
            }
            ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::User::get_user_ipv6_address( $domain_owner, $cpuser_ref ? $cpuser_ref->{'DOMAIN'} : undef );
        }
        unless ($found_domain_type) {
            require Cpanel::FileLookup;
            if ( Cpanel::FileLookup::filelookup( $Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE, 'key' => $domain ) ) {
                %domains_for_proxy_subdomains = ( $domain => 'main' );
            }
            elsif ( Cpanel::FileLookup::filelookup( $Cpanel::ConfigFiles::USERDOMAINS_FILE, 'key' => $domain ) ) {
                %domains_for_proxy_subdomains = ( $domain => 'all' );
            }
            else {
                return ( 0, "The domain $domain does not belong to any user on this system" );
            }
        }
    }
    elsif ($domains) {
        %domains_for_proxy_subdomains = %$domains;
    }
    else {
        %domains_for_proxy_subdomains = %{ _collect_domains_for_proxy_subdomains() };
    }

    #look for a wildcard, and if spotted suppress the error and pass it along so caller can continue to the rest
    if ( ( defined $domain ) && ( substr( $domain, 0, 1 ) eq "*" ) ) { return 1; }

    delete @domains_for_proxy_subdomains{ grep( m/\*/, keys %domains_for_proxy_subdomains ) };    #loaduserdomains has a default

    if ( !%domains_for_proxy_subdomains ) {
        return ( 0, 'No domains available to install service subdomains on' );
    }

    # We want to get the userdomains that already exist like
    # autoconfig.koston.org and make sure we don't recreate or remove them
    my $owner_of_domains = ( $user || $domain_owner );

    my $user_controlled_proxy_domains_ar;

    if ($owner_of_domains) {
        $user_controlled_proxy_domains_ar = _get_users_domains_that_match_proxy_subdomains($owner_of_domains);
    }
    else {
        $user_controlled_proxy_domains_ar = _get_all_user_controlled_domains_that_match_proxy_subdomains();
    }
    my %proxy_domains_to_skip = map { $_ => 1 } @$user_controlled_proxy_domains_ar;

    my @installlist;
    my $cpconf_ref                     = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $overwritecustomsrvrecords      = $cpconf_ref->{'overwritecustomsrvrecords'}      ? 1 : 0;
    my $overwritecustomproxysubdomains = $cpconf_ref->{'overwritecustomproxysubdomains'} ? 1 : 0;
    my $server_hostname                = Cpanel::Sys::Hostname::gethostname();

    foreach my $sub (@relevant_service_subdomains) {
        my $delete_this = $delete || grep { $_ eq $sub } @service_subdomains_to_delete;

        push @installlist,
          {
            'operation' => ( $delete_this ? 'delete' : 'add' ),
            'type'      => 'A',
            'domain'    => '%domain%',
            'record'    => $sub . '.%domain%',
            'value'     => '%ip%',
            ( $overwritecustomproxysubdomains                  ? ()                    : ( 'keep_duplicate' => 1 ) ),
            ( !$overwritecustomproxysubdomains && $delete_this ? ( 'match' => '%ip%' ) : () ),

            # We have to check each record because its possible to have
            # overwritecustomproxysubdomains turned on and
            # overwritecustomsrvrecords turned off and vise-versa
            'transform' => sub {
                my ( $zonefile_obj, $dnszone_entry, $template_obj ) = @_;

                # If we want to overwrite or the record is one of the old
                # records we modify it.
                if ($overwritecustomproxysubdomains) {
                    my $current_value = $zonefile_obj->get_zone_record_value($dnszone_entry);
                    my $value         = $template_obj->get_key('ip');
                    if ( $current_value ne $value ) {
                        $zonefile_obj->set_zone_record_value( $dnszone_entry, $value );
                    }
                }
                return 1;
            },

            'domains' => $known_proxy_subdomains_ref->{$sub}->{'domains'},
          };
        if ($has_ipv6) {
            push @installlist,
              {
                'operation' => ( $delete_this ? 'delete' : 'add' ),
                'type'      => 'AAAA',
                'domain'    => '%domain%',
                'record'    => $sub . '.%domain%',
                'value'     => $ipv6,
                'domains'   => $known_proxy_subdomains_ref->{$sub}->{'domains'},
              };
        }
        if ( $sub eq 'autodiscover' ) {
            my $autodiscover_host = _get_autodiscover_host($cpconf_ref);
            $autodiscover_host =~ s/\.$//;    # strip trailing dot as we will add it back
            my %matchers;

            # We only want to match ones we are 'allowed to overwrite'
            $matchers{"0 0 443 $autodiscover_host\."}                               = 1;
            $matchers{"0 0 443 $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST\."} = 1;
            $matchers{"0 0 443 $old_autodiscover_host\."}                           = 1 if $old_autodiscover_host;
            $matchers{"0 0 2079 $server_hostname\."}                                = 1;
            $matchers{"0 0 2080 $server_hostname\."}                                = 1;
            $matchers{"0 0 2079 $old_hostname\."}                                   = 1 if $old_hostname;
            $matchers{"0 0 2080 $old_hostname\."}                                   = 1 if $old_hostname;

            push @installlist, map {
                my $data = $_;
                {
                    'operation' => ( $delete_this ? 'delete' : 'add' ),                 #
                    'type'      => 'SRV',                                               #
                    'domain'    => '%domain%',                                          #
                    'record'    => '_' . $_->{service} . '._tcp' . '.' . '%domain%',    #
                    'value'     => "0 0 $_->{port} $_->{host}\.",                       #
                    'domains'   => $known_proxy_subdomains_ref->{$sub}->{'domains'},

                    # We have to check each record because its possible to have
                    # overwritecustomproxysubdomains turned on and
                    # overwritecustomsrvrecords turned off and vise-versa
                    'transform' => sub {
                        my ( $zonefile_obj, $dnszone_entry, $template_obj ) = @_;

                        # If we want to overwrite or the record is one of the old
                        # records we modify it.
                        my $current_value = $zonefile_obj->get_zone_record_value($dnszone_entry);
                        if ( $overwritecustomsrvrecords || $matchers{$current_value} ) {
                            my $value = "0 0 $data->{port} $data->{host}\.";
                            if ( $value ne $current_value ) {
                                $zonefile_obj->set_zone_record_value( $dnszone_entry, $value );
                            }
                        }
                        return 1;
                    },
                }
              } { service => 'autodiscover', port => 443, host => $autodiscover_host },
              { service => 'caldav',   port => 2079, host => $domain || '%domain%' },
              { service => 'caldavs',  port => 2080, host => $domain || '%domain%' },
              { service => 'carddav',  port => 2079, host => $domain || '%domain%' },
              { service => 'carddavs', port => 2080, host => $domain || '%domain%' };

            push @installlist, map {
                {
                    'operation' => ( $delete_this ? 'delete' : 'add' ),      #
                    'type'      => 'TXT',                                    #
                    'domain'    => '%domain%',                               #
                    'record'    => '_' . $_ . '._tcp' . '.' . '%domain%',    #
                    'value'     => 'path=/',

                    # We have to check each record because its possible to have
                    # overwritecustomproxysubdomains turned on and
                    # overwritecustomsrvrecords turned off and vise-versa
                    'transform' => sub {
                        my ( $zonefile_obj, $dnszone_entry, $template_obj ) = @_;

                        # If we want to overwrite or the record is one of the old
                        # records we modify it.
                        my $current_value = $zonefile_obj->get_zone_record_value($dnszone_entry);
                        if ($overwritecustomsrvrecords) {
                            if ( 'path=/' ne $current_value ) {
                                $zonefile_obj->set_zone_record_value( $dnszone_entry, 'path=/' );
                            }
                        }
                        return 1;
                    },
                    'domains' => $known_proxy_subdomains_ref->{$sub}->{'domains'},
                }
            } qw(caldav caldavs carddav carddavs);

        }
    }
    unless (@installlist) {
        return ( 1, ( $delete ? 'No Records to Uninstall' : 'No Records to Install' ) );
    }

    return Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
        'domains'           => \%domains_for_proxy_subdomains,
        'records'           => \@installlist,
        'reload'            => $OPTS{'skipreload'} ? 0 : 1,
        'no_replace'        => $noreplace,
        'pre_fetched_zones' => $zone_ref,
        'domain_owner'      => ( $domain_owner || '' ),
        keys %proxy_domains_to_skip ? ( 'records_to_skip' => \%proxy_domains_to_skip ) : (),
    );
}

sub _collect_domains_for_proxy_subdomains {
    my $user_domains_ref      = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my $true_user_domains_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains();

    my %domains_for_proxy_subdomains = (
        ( map { $_ => 'all' } keys %{$user_domains_ref} ),
        ( map { $_ => 'main' } keys %{$true_user_domains_ref} )
    );
    delete $domains_for_proxy_subdomains{'*'};
    return \%domains_for_proxy_subdomains;
}

my $_get_proxy_regex_match;

sub _get_proxy_regex_match {
    return $_get_proxy_regex_match if $_get_proxy_regex_match;
    my $known_proxy_subdomains = get_known_proxy_subdomains();
    $_get_proxy_regex_match = '(?:' . join( '|', map { quotemeta($_) } keys %$known_proxy_subdomains ) . ')';

    return $_get_proxy_regex_match;
}

sub _get_all_user_controlled_domains_that_match_proxy_subdomains {
    my $user_domains_ref = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );

    my $proxy_regex_match = _get_proxy_regex_match();

    return [ grep { /^$proxy_regex_match\./o } keys %$user_domains_ref ];
}

sub _get_users_domains_that_match_proxy_subdomains {
    my ($user) = @_;

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    my $proxy_regex_match = _get_proxy_regex_match();

    return [ grep { /^$proxy_regex_match\./o } ( $cpuser_ref->{'DOMAIN'}, @{ $cpuser_ref->{'DOMAINS'} } ) ];
}

sub _get_autodiscover_host {
    my ($cpconf_ref) = @_;

    if ( $cpconf_ref->{'autodiscover_host'} ) {
        return $cpconf_ref->{'autodiscover_host'} if $cpconf_ref->{'autodiscover_host'} eq Cpanel::Sys::Hostname::gethostname();
        require Cpanel::Validate::Domain::Tiny;
        return $cpconf_ref->{'autodiscover_host'} if Cpanel::Validate::Domain::Tiny::validdomainname( $cpconf_ref->{'autodiscover_host'} );

    }
    return $Cpanel::Proxy::Tiny::DEFAULT_AUTODISCOVERY_HOST;
}
1;
