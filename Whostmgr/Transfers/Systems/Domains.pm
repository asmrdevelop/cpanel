package Whostmgr::Transfers::Systems::Domains;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
# RR Audit: JNK
use Cpanel::DnsUtils::Install      ();
use Cpanel::Config::userdata::Load ();
use Cpanel::IPv6::User             ();

use Cpanel::Userdomains                      ();
use Cpanel::Domains                          ();
use Cpanel::AcctUtils::Account               ();
use Cpanel::Logger                           ();
use Cpanel::Config::userdata::Guard          ();
use Cpanel::Config::userdata::UpdateCache    ();
use Cpanel::Config::userdata::Utils          ();
use Cpanel::Validate::Domain                 ();
use Cpanel::Validate::Domain::Normalize      ();
use Cpanel::Validate::DomainCreation::Sub    ();
use Cpanel::Validate::DomainCreation::Parked ();
use Cpanel::Validate::DomainCreation::Addon  ();
use Cpanel::AcctUtils::DomainOwner::Tiny     ();
use Cpanel::Config::LoadCpConf               ();
use Cpanel::Config::ModCpUserFile            ();

use Cpanel::SSL::Setup     ();
use Cpanel::Sub            ();
use Cpanel::ParkAdmin      ();
use Cpanel::WildcardDomain ();

use Whostmgr::Transfers::ArchiveManager::Subdomains ();
use Cpanel::PHPFPM::Config                          ();
use Try::Tiny;

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 15;
}

sub get_prereq {
    return [ 'Homedir', 'IPAddress' ];
}

sub disable_options {
    return [ 'all', 'parkeddomains', 'subdomains' ];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores subdomains, parked domains, and addon domains.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext("The system will restore subdomains, parked domains, and addon domains if they pass the server’s domain creation rules. If the server rejects the restoration of an addon domain, it will still create a subdomain associated with that addon domain.") ];
}

my $MAX_RESTORABLE_DOMAINS = 32768;    # case 113333: Increased from 16384.

*unrestricted_restore = \&restricted_restore;

# We do not create the
# virtual hosts at this point.  Only the userdata
# is created.
# In Vhosts.pm we will create the actual virtual host
# entries in httpd.conf

# TODO: error checking for all opens and returns
sub restricted_restore {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - Fixing this should be done in a feature branch
    my ($self) = @_;

    local $Cpanel::SSL::Setup::DISABLED = 1;    #Prevent the best available cert from being installed before SSL.pm runs

    my $restoreparked = $self->disabled()->{'Domains'}{'parkeddomains'} ? 0 : 1;
    my $restoresubs   = $self->disabled()->{'Domains'}{'subdomains'}    ? 0 : 1;
    my ($cpuser_ref)  = $self->{'_utils'}->get_cpuser_data();
    my $cpconf        = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $restored_user = $self->newuser();

    # both of these are probably overly paranoid, but just in case
    return ( 0, "No user was indicated in the restoration process. This should not happen." ) if !$restored_user;
    if ( !$self->{'_utils'}->is_unrestricted_restore() ) {
        return ( 0, "Account $restored_user does not exist." ) if !Cpanel::AcctUtils::Account::accountexists($restored_user);
    }

    # We need to make sure the userdata cache is updated before attempting to restore domains
    Cpanel::Config::userdata::UpdateCache::update( $restored_user, { force => 1 } );

    my $extractdir = $self->extractdir();

    my ( $uid, $gid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7 ];

    my $abshomedir = Cwd::abs_path($user_homedir);

    my $main_domain = Cpanel::Validate::Domain::Normalize::normalize( $self->{'_utils'}->main_domain() );

    $self->start_action('Retrieving and sanitizing main userdata …');

    my $existing_domains = $self->_sanitize_main_userdata_fetch_existing_domains();
    $self->start_action('Parsing domain databases …');
    my %DOMAINRESTORE;
    $DOMAINRESTORE{$main_domain} = {
        'docroot'  => $user_homedir . '/public_html',
        'restored' => { 'status' => 1, 'result' => $self->_locale()->maketext( "The main domain, [_1], was restored when the account was created.", $main_domain ) },
        'type'     => 'maindomain',
    };

##
## Builds a list of subdomains and stores it in the DOMAINRESTORE HASH
##
    if ($restoresubs) {
        $self->start_action('…Subdomains…');
        my ( $sub_ok, $subdomains ) = Whostmgr::Transfers::ArchiveManager::Subdomains::retrieve_subdomains_from_extracted_archive( $self->archive_manager() );

        if ($sub_ok) {
            foreach my $subref ( @{$subdomains} ) {
                my $fullsubdomain = Cpanel::Validate::Domain::Normalize::normalize_wildcard( $subref->{'fullsubdomain'} );
                my $rootdomain    = Cpanel::Validate::Domain::Normalize::normalize( $subref->{'rootdomain'} );

                my ( $is_valid, $valid_msg ) = Cpanel::Validate::Domain::validwildcarddomain( $subref->{'fullsubdomain'} );
                if ( !$is_valid ) {
                    $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The subdomain “[_1]” is not a valid domain name: [_2]", $fullsubdomain, $valid_msg ) );
                    next;
                }

                # the 1 here means 'quiet' - we know this subdomain isn't a FQDN so we don't need to warn about it
                my $subdomain = Cpanel::Validate::Domain::Normalize::normalize_wildcard( $subref->{'subdomain'} );
                my $docroot   = $subref->{'docroot'};
                my $sub_count = 0;
                if ( !exists $DOMAINRESTORE{$fullsubdomain} ) {
                    if ( $sub_count++ < $MAX_RESTORABLE_DOMAINS ) {
                        $DOMAINRESTORE{$fullsubdomain} = {
                            'rootdomain' => $rootdomain,
                            'docroot'    => $docroot,
                            'subdomain'  => $subdomain,
                            'canoff'     => 0,
                            'required'   => $rootdomain,
                            'type'       => 'subdomain'
                        };
                    }
                    else {
                        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "Reached maximum amount of subdomains ([numf,_1]/[numf,_2]): [_3]", $sub_count, $MAX_RESTORABLE_DOMAINS, $fullsubdomain ) );
                    }
                }
            }

        }
        else {
            $self->{'_utils'}->add_skipped_item($subdomains);
        }
        #
    }
##
## Builds a list of parkeddomains and stores it in the DOMAINRESTORE HASH
##
    my $parked_domain_count = 0;
    if ($restoreparked) {
        $self->start_action('…ParkedDomains…');
        my $destdomain = $main_domain;

        #TODO: What if this file isn't there?
        if ( !-e "$extractdir/pds" ) {
        }

        #TODO: error handling
        open( my $parkeddb, "<", "$extractdir/pds" ) or do {
            $self->warn("Failed to open($extractdir/pds): $!");
        };

        local $!;
        while ( my $parkeddomain = readline($parkeddb) ) {
            $parkeddomain =~ s/\n//g;
            $parkeddomain =~ m/^(\S+)/;
            $parkeddomain = $1;

            # domain may be in upper case, or alternating case - match www. no matter the casing
            if ( $parkeddomain =~ m/^[wW]{3}\./ || $parkeddomain eq '' ) {
                next;
            }

            $parkeddomain = Cpanel::Validate::Domain::Normalize::normalize($parkeddomain);

            my ( $is_valid, $valid_msg ) = Cpanel::Validate::Domain::validwildcarddomain($parkeddomain);
            if ( !$is_valid ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The parked domain “[_1]” is not a valid domain name: [_2]", $parkeddomain, $valid_msg ) );
                next;
            }

            if ( !exists $DOMAINRESTORE{$parkeddomain} ) {
                if ( $parked_domain_count++ < $MAX_RESTORABLE_DOMAINS ) {
                    $DOMAINRESTORE{$parkeddomain} = {
                        'destdomain' => $destdomain,
                        'required'   => $destdomain,
                        'type'       => 'parkeddomain',
                    };
                }
                else {
                    $self->{'_utils'}->add_skipped_item($parkeddomain);
                }
            }
        }
        if ($!) {

            #TODO: error handling
        }

        close($parkeddb) or do {

            #TODO: error handling
        };
    }
    else {
        $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext("The restoration of parked and addon domains has been disabled by request.") );
    }

##
## Builds a list of addondomains and stores it in the DOMAINRESTORE HASH
##
    if ( $restoreparked && $parked_domain_count < $MAX_RESTORABLE_DOMAINS ) {
        $self->start_action('…AddonDomains…');

        if ( !-e "$extractdir/addons" ) {

            #TODO: What when there's no file?
        }

        open( my $addondb, "<", "$extractdir/addons" ) or do {
            $self->warn("Failed to open($extractdir/addons): $!");
        };

        local $!;
        while ( my $addondata = readline($addondb) ) {
            chomp $addondata;

            my ( $parkeddomain, $destdomain ) = split( /=/, $addondata );
            next if !$parkeddomain;

            $destdomain =~ tr/_/./;

            $parkeddomain = Cpanel::Validate::Domain::Normalize::normalize($parkeddomain);

            my ( $is_valid, $valid_msg ) = Cpanel::Validate::Domain::validwildcarddomain($parkeddomain);
            if ( !$is_valid ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The addon domain “[_1]” is not a valid domain name: [_2]", $parkeddomain, $valid_msg ) );
                next;
            }

            $destdomain = Cpanel::Validate::Domain::Normalize::normalize($destdomain);

            ( $is_valid, $valid_msg ) = Cpanel::Validate::Domain::validwildcarddomain($destdomain);
            if ( !$is_valid ) {
                $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "The domain “[_1]” that the addon domain “[_2]” would be parked on top of is not a valid domain name: [_3]", $destdomain, $parkeddomain, $valid_msg ) );
                next;
            }

            # If subdomains are disabled we cannot set this flag
            # as we are not restoring them
            if ( $DOMAINRESTORE{$destdomain} ) {
                $DOMAINRESTORE{$destdomain}->{'canoff'} = 1;
            }

            if ( !exists $DOMAINRESTORE{$parkeddomain} ) {
                if ( $parked_domain_count++ < $MAX_RESTORABLE_DOMAINS ) {
                    $DOMAINRESTORE{$parkeddomain} = {
                        'destdomain' => $destdomain,
                        'required'   => $destdomain,
                        'type'       => 'addondomain',
                    };
                }
                else {
                    $self->{'_utils'}->add_skipped_item($parkeddomain);
                }
            }
        }

        if ($!) {

            #TODO: error handling
        }

        close($addondb) or do {

            #TODO: error handling
        };
    }

    if ( $DOMAINRESTORE{''} ) {
        $self->warn("Warning null domain defined!");
        delete $DOMAINRESTORE{''};
    }

##
## Cycles though the subdomains and makes all the subdomain's root domains the smallest possible
## ie bob_sam.frog.com becomes bob.sam_frog.com where
## subdomain_rootdomain is the format
##
##   For more information about why this is required see:
##
##    Case 93761: A user was unable to create a subdomain which had a dot (e.g.
##      why.not for blue.cow) because the userdata for the intermediate domain
##    (not.blue.cow) did not exist.  Validate that the userdata for the root
##    domain exists instead of trying to validate the intermediate domain, which
##    may or may not exist.
##
##
    foreach my $domain ( keys %DOMAINRESTORE ) {
        next if ( $DOMAINRESTORE{$domain}->{'type'} ne 'subdomain' );
        my $rootdomain = $DOMAINRESTORE{$domain}->{'rootdomain'};
        next if ( $rootdomain eq $main_domain );
        my @DNSPATH = split( /\./, $rootdomain );

        my @NEWROOT;
        while ( $#DNSPATH > -1 && !$DOMAINRESTORE{ join( ".", @NEWROOT ) } ) {
            unshift( @NEWROOT, pop(@DNSPATH) );
        }
        my $newroot = join( '.', @NEWROOT );
        if ( length $newroot < length $DOMAINRESTORE{$domain}->{'rootdomain'} ) {
            $DOMAINRESTORE{$domain}->{'rootdomain'} = $newroot;

            # Case 52792: Do not shorten the 'required' subdomain root if it is the main domain for the account.
            # Otherwise, if an addon domain is the root of the main domain, it would result in a circular 'required' dependency.
            unless ( $DOMAINRESTORE{$domain}->{'required'} eq $main_domain ) {
                $DOMAINRESTORE{$domain}->{'required'} = $newroot;
            }

            my @SUB = split( /\./, $DOMAINRESTORE{$domain}->{'subdomain'} );
            push( @SUB, @DNSPATH );
            $DOMAINRESTORE{$domain}->{'subdomain'} = join( '.', @SUB );
        }
    }

##
## Cycles though the DOMAINRESTORE hash we just built and restores each sub/parked/addon domain
## It checks to make sure the 'required' field is met before restoring the domain so we do not
## restore any domains that the underlying subdomain or parkeddomain that it is on top of is not there
## yet.  We cycle though 12 times as this should be enough to get all the domains.
##
## Will a user ever have more than 12 levels of domains?  probably not as this will violate the rfc.  10 might even be ok.
##
    #
    #  NOTE: Now that _augment_domainrestore_list_with_restoreorder has been added
    #  to sort the domains in restore order, this 12 try loop can likely be removed
    #  in 11.46
    #
    $self->start_action('Restoring Domains …');

    my @subdomain_dns_entries;
    my @restored_subdomains;

    _augment_domainrestore_list_with_restoreorder( \%DOMAINRESTORE, $main_domain );

    for ( my $trycount = 0; $trycount <= 12; $trycount++ ) {

        foreach my $domain ( sort { ( $DOMAINRESTORE{$a}{'restoreorder'} <=> $DOMAINRESTORE{$b}{'restoreorder'} ) || ( length $a <=> length $b ) } keys %DOMAINRESTORE ) {

            next if defined $DOMAINRESTORE{$domain}->{'restored'};

            if ( my $required = $DOMAINRESTORE{$domain}->{'required'} ) {
                my $required_domain_is_pending_restore      = ( $DOMAINRESTORE{$required} && !defined $DOMAINRESTORE{$required}->{'restored'} )                                                               ? 1 : 0;
                my $required_domain_is_restored             = ( $DOMAINRESTORE{$required} && $DOMAINRESTORE{$required}->{'restored'} && $DOMAINRESTORE{$required}->{'restored'}->{'status'} )                 ? 1 : 0;
                my $required_domain_already_exist_on_server = ( $required_domain_is_restored || Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $required, { default => '', 'skiptruelookup' => 1 } ) ) ? 1 : 0;

                if ( $required_domain_is_restored || $required_domain_already_exist_on_server ) {

                    # OK to proceed
                }
                elsif ($required_domain_is_pending_restore) {
                    $self->out( $self->_locale()->maketext( "The restoration of “[_1]” will happen after the prerequisite domain “[_1]” is processed.", $domain, $required ) );
                    next;
                }
                else {
                    my $msg = $self->_locale()->maketext( "Restoration of “[_1]” will be skipped because it requires that “[_2]” be created before it can be restored.", $domain, $required );
                    $self->warn($msg);
                    $self->warn( $self->_locale()->maketext( "Prerequisite domain, “[_1]” is not referenced in the restore file and does not preexist.", $required ) );
                    $DOMAINRESTORE{$domain}->{'restored'} = { 'status' => 0, 'result' => $msg };

                    next;
                }
            }

            my ( $status, $result );
            if ( $DOMAINRESTORE{$domain}->{'type'} eq 'subdomain' ) {
                $self->start_action( $self->_locale()->maketext( 'Restoring Subdomain “[_1]” …', $domain ) );
                {
                    my $adddns = 0;
                    my ( $subdomain, $rootdomain ) = @{ $DOMAINRESTORE{$domain} }{qw(subdomain rootdomain)};
                    my $fullsubdomain = "$subdomain.$rootdomain";
                    if ( $existing_domains->{'sub_domains'}{$domain} ) {
                        $status = 1;
                        $result = $self->_locale()->maketext( "The Subdomain “[_1]” is already configured for this account.", $domain );
                    }
                    elsif ( $self->{'_utils'}->is_unrestricted_restore() ) {
                        ( $status, $result ) = Cpanel::Sub::restore_subdomain(
                            'nodnsreload'         => 1,
                            'force'               => 1,
                            'rootdomain'          => $rootdomain,
                            'subdomain'           => $subdomain,
                            'usecannameoff'       => $DOMAINRESTORE{$domain}->{'canoff'},
                            'documentroot'        => $DOMAINRESTORE{$domain}->{'docroot'},
                            'user'                => $restored_user,
                            'cpuser_ref'          => $cpuser_ref,
                            'cpconf'              => $cpconf,
                            'skip_conf_rebuild'   => 1,
                            'skip_restart_apache' => 1,
                            'no_cache_update'     => 1,
                        );
                        $adddns = 1 if $status;
                    }
                    else {
                        ( $status, $result ) = $self->restricted_restore_sub_domain(
                            'rootdomain'    => $rootdomain,
                            'subdomain'     => $subdomain,
                            'usecannameoff' => $DOMAINRESTORE{$domain}->{'canoff'},
                            'documentroot'  => $DOMAINRESTORE{$domain}->{'docroot'},
                            'user'          => $restored_user,
                            'cpuser_ref'    => $cpuser_ref,
                            'cpconf'        => $cpconf,

                        );
                        $adddns = 1 if $status;
                    }

                    if ($adddns) {
                        push @subdomain_dns_entries, $fullsubdomain, 'www.' . $fullsubdomain;
                        push @restored_subdomains, $fullsubdomain;
                        if ( Cpanel::PHPFPM::Config::get_default_accounts_to_fpm() ) {
                            require Cpanel::PHPFPM::ConvertAll;
                            Cpanel::PHPFPM::ConvertAll::queue_convert_domain($fullsubdomain);
                        }
                    }
                }
            }
            elsif ( $DOMAINRESTORE{$domain}->{'type'} eq 'parkeddomain' || $DOMAINRESTORE{$domain}->{'type'} eq 'addondomain' ) {
                my $domain_to_park_on_top_of = $DOMAINRESTORE{$domain}->{'destdomain'};
                my $adddns                   = 0;
                if ( $DOMAINRESTORE{$domain}->{'type'} eq 'parkeddomain' ) {
                    $self->start_action( $self->_locale()->maketext( 'Restoring Parked Domain “[_1]” on to “[_2]” …', $domain, $domain_to_park_on_top_of ) );
                }
                else {
                    $self->start_action( $self->_locale()->maketext( 'Restoring Addon Domain “[_1]” on to “[_2]” …', $domain, $domain_to_park_on_top_of ) );
                }
                if ( $DOMAINRESTORE{$domain}->{'type'} eq 'parkeddomain' && $existing_domains->{'parked_domains'}{$domain} ) {
                    $status = 1;
                    $result = $self->_locale()->maketext( "The Parked Domain “[_1]” is already configured for this account.", $domain );
                }
                elsif ( $DOMAINRESTORE{$domain}->{'type'} eq 'addondomain' && $existing_domains->{'addon_domains'}{$domain} && $existing_domains->{'addon_domains'}{$domain} eq $domain_to_park_on_top_of ) {
                    $status = 1;
                    $result = $self->_locale()->maketext( "The Addon Domain “[_1]” is already configured for this account.", $domain );
                }
                elsif ( $self->{'_utils'}->is_unrestricted_restore() ) {
                    ( $status, $result ) = Cpanel::ParkAdmin::restore_park(
                        'domain'              => $domain_to_park_on_top_of,
                        'newdomain'           => $domain,
                        'user'                => $restored_user,
                        'skip_ssl_setup'      => ( $DOMAINRESTORE{$domain}->{'type'} eq 'parkeddomain' ? 1 : 0 ),
                        'cpuser_ref'          => $cpuser_ref,
                        'cpconf'              => $cpconf,
                        'skip_restart_apache' => 1,
                        'allowoverwrite'      => 1,
                        'no_cache_update'     => 1,
                    );
                    $adddns = 1 if $status;
                }
                else {
                    ( $status, $result ) = $self->restricted_restore_parked_domain(
                        'domain'         => $domain_to_park_on_top_of,
                        'newdomain'      => $domain,
                        'maindomain'     => $main_domain,
                        'user'           => $restored_user,
                        'skip_ssl_setup' => ( $DOMAINRESTORE{$domain}->{'type'} eq 'parkeddomain' ? 1 : 0 ),
                        'cpuser_ref'     => $cpuser_ref,
                        'cpconf'         => $cpconf,
                    );
                    $adddns = 1 if $status;
                }
                if ( $adddns && Cpanel::PHPFPM::Config::get_default_accounts_to_fpm() ) {
                    require Cpanel::PHPFPM::ConvertAll;
                    Cpanel::PHPFPM::ConvertAll::queue_convert_domain($domain);
                }
            }
            else {
                next;
            }

            if ($status) {
                $self->{'_utils'}->add_restored_domain($domain);
                $self->out($result);
            }
            else {
                $self->warn($result);
            }

            if ( my $err = $@ ) {
                $self->warn($err);
            }
            $DOMAINRESTORE{$domain}->{'restored'} = { 'status' => $status, 'result' => $result };
            $self->out("Done");

        }
    }

    my @restored_domains;
    foreach my $domain ( keys %DOMAINRESTORE ) {
        my $results = $DOMAINRESTORE{$domain}->{'restored'};
        if ( !ref $results ) { $results = { 'status' => $results, 'result' => $self->_locale()->maketext('Unknown') }; }
        my ( $status, $result ) = @{$results}{ 'status', 'result' };

        if ( $status == 1 ) {
            push @restored_domains, $domain;
        }
        else {
            $self->{'_utils'}->add_skipped_item( $self->_locale()->maketext( "Failed to restore the domain “[_1]”: [_2]", $domain, $result ) );
        }
    }

    if (@restored_domains) {
        if (@subdomain_dns_entries) {

            # TODO: move this into _add_address_records_for_subdomains()
            # Since subdomain dns entries always end up in their parent zone and
            # v72 Cpanel::DnsUtils::Install::install_records_for_multiple_domains is
            # smart enough to figure out which zone file to put the records in automaticlly
            # we can do all the subdomain A and AAAA entries in a single dns update which
            # makes this orders of magnitude faster!
            my $dns_userdata = Cpanel::Config::userdata::Load::load_userdata_real_domain( $restored_user, $main_domain );
            my $currentip    = $dns_userdata->{'ip'};
            my ( $has_ipv6, $ipv6 ) = Cpanel::IPv6::User::get_user_ipv6_address($restored_user);
            my %domains     = map { $_ => 'all' } @subdomain_dns_entries;
            my @installlist = {
                'operation' => 'add',
                'type'      => 'A',
                'domain'    => '%domain%',
                'record'    => '%domain%',
                'value'     => $currentip,
                'domains'   => 'all',
            };
            if ($has_ipv6) {
                push @installlist,
                  {
                    'operation' => 'add',
                    'type'      => 'AAAA',
                    'domain'    => '%domain%',
                    'record'    => '%domain%',
                    'value'     => $ipv6,
                    'domains'   => 'all',
                  };
            }
            $self->start_action('Installing DNS Entries for SubDomains…');
            my ( $ok, $msg, $results ) = Cpanel::DnsUtils::Install::install_records_for_multiple_domains(
                'domains'      => \%domains,
                'records'      => \@installlist,
                'reload'       => 1,
                'no_replace'   => 0,
                'domain_owner' => $restored_user,
            );
            foreach my $response ( sort { $a->{'domain'} cmp $b->{'domain'} } @{ $results->{'domain_status'} || [] } ) {
                $self->out("$response->{'domain'}: $response->{'msg'}");
            }
            if ( !$ok ) {
                $self->warn($msg);
            }
        }

        if (@restored_subdomains) {
            $self->start_action('Setting up Bandwidth databases for SubDomains…');
            require Cpanel::BandwidthDB;
            my $bwdb = Cpanel::BandwidthDB::get_writer($restored_user);
            my $dbh  = $bwdb->{'_dbh'};

            # Transaction if for performance reasons only
            $dbh->do('BEGIN TRANSACTION');
            my $domain_id_map_hr = $bwdb->get_domain_id_map();

            foreach my $fullsubdomain (@restored_subdomains) {
                if ( !$domain_id_map_hr->{$fullsubdomain} ) {
                    $bwdb->initialize_domain($fullsubdomain);
                }
            }
            $dbh->do('END TRANSACTION');
        }

        $self->start_action('Updating internal databases…');
        Cpanel::Config::ModCpUserFile::adddomainstouser( 'user' => $restored_user, 'domains' => \@restored_domains, 'type' => '' );
        Cpanel::Domains::del_deleted_domains( $restored_user, 'root', '', \@restored_domains );
        Cpanel::Userdomains::updateuserdomains();    # must happen before DKIM
    }

    return ( 1, "Domains restored" );
}

sub restricted_restore_sub_domain {
    my ( $self, %OPTS ) = @_;

    my ( $user, $root_domain, $sub_domain, $document_root, $can_off, $cpuser_ref, $cpconf ) = @OPTS{qw( user rootdomain subdomain documentroot can_off cpuser_ref cpconf)};

    my $fullsubdomain   = "$sub_domain.$root_domain";
    my @SPLITFULLDOMAIN = split( /\./, $fullsubdomain );
    shift @SPLITFULLDOMAIN;
    my $parent_domain = join( '.', @SPLITFULLDOMAIN );

    my $err_obj;
    try {
        my $subdomain_creation_validator = Cpanel::Validate::DomainCreation::Sub->new(
            {
                'sub_domain'    => $sub_domain,
                'target_domain' => $parent_domain,
                'root_domain'   => $root_domain,
            },
            { 'ownership_user' => $user, }
        );
        $subdomain_creation_validator->validate();
    }
    catch {
        $err_obj = $_;
    };
    if ($err_obj) {
        if ( ref $err_obj && $err_obj->isa('Cpanel::Exception') ) {
            return ( 0, $err_obj->to_locale_string() );
        }
        else {
            return ( 0, $err_obj );
        }
    }

    $document_root =~ s{\s+}{}g;
    $document_root =~ s/\\//g;
    $document_root =~ s{//+}{/}g;
    if ( !$document_root ) {
        $document_root = 'public_html/' . Cpanel::WildcardDomain::encode_wildcard_domain($sub_domain);
    }

    return Cpanel::Sub::restore_subdomain(
        'nodnsreload'         => 1,
        'force'               => 0,
        'rootdomain'          => $root_domain,
        'subdomain'           => $sub_domain,
        'usecannameoff'       => $can_off,
        'documentroot'        => $document_root,
        'user'                => $user,
        'skip_conf_rebuild'   => 1,
        'skip_restart_apache' => 1,
        'no_cache_update'     => 1,
        'cpuser_ref'          => $cpuser_ref,
        'cpconf'              => $cpconf,
    );
}

sub restricted_restore_parked_domain {
    my ( $self, %OPTS ) = @_;

    my ( $user, $target_domain, $park_domain, $maindomain, $skip_ssl_setup, $cpuser_ref, $cpconf ) = @OPTS{qw( user domain newdomain maindomain skip_ssl_setup cpuser_ref cpconf)};

    my $err_obj;
    try {
        if ( $target_domain eq $maindomain ) {
            my $parked_domain_creation_validator = Cpanel::Validate::DomainCreation::Parked->new(
                { 'domain' => $park_domain },
                {
                    'ownership_user'     => $user,                                                                           # The user who will own the domain once it is created.
                    'validation_context' => Cpanel::Validate::DomainCreation::Parked->VALIDATION_CONTEXTS()->{'WHOSTMGR'},
                }
            );
            $parked_domain_creation_validator->validate();
        }
        else {
            my $addon_domain_creation_validator = Cpanel::Validate::DomainCreation::Addon->new(
                {
                    'domain'        => $park_domain,
                    'target_domain' => $target_domain
                },
                {
                    'ownership_user'     => $user,                                                                           # The user who will own the domain once it is created.
                    'validation_context' => Cpanel::Validate::DomainCreation::Parked->VALIDATION_CONTEXTS()->{'WHOSTMGR'},
                }
            );
            $addon_domain_creation_validator->validate();
        }
    }
    catch {
        $err_obj = $_;
    };
    if ($err_obj) {
        my $message;
        if ( ref $err_obj && $err_obj->isa('Cpanel::Exception') ) {
            Cpanel::Logger::cplog( "Invalid domain [$park_domain]", 'info', __PACKAGE__, 1 ) if $err_obj->isa('Cpanel::Exception::InvalidDomain');
            $message = $err_obj->to_locale_string();
        }
        else {
            $message = $err_obj;
        }
        return ( 0, $message );
    }

    return Cpanel::ParkAdmin::restore_park(
        'domain'              => $target_domain,
        'newdomain'           => $park_domain,
        'user'                => $user,
        'skip_restart_apache' => 1,
        'skip_ssl_setup'      => $skip_ssl_setup,
        'allowoverwrite'      => 0,
        'no_cache_update'     => 1,
        'newdomain_exists'    => 0,
        'cpuser_ref'          => $cpuser_ref,
        'cpconf'              => $cpconf,

    );
}

sub _augment_domainrestore_list_with_restoreorder {
    my ( $domainrestore_ref, $maindomain ) = @_;

    my %to_order          = map { $_ => 1 } keys %{$domainrestore_ref};
    my %seen              = map { $_ => 0 } keys %{$domainrestore_ref};
    my $number_of_domains = scalar keys %to_order;
    my @restore_order     = ($maindomain);
    delete $to_order{$maindomain};

    while ( scalar keys %to_order ) {
        my @domains_to_order_sorted_by_length = sort { length($a) <=> length($b) || $a cmp $b } keys %to_order;

      DOMAIN:
        foreach my $domain (@domains_to_order_sorted_by_length) {
            my $prereq_domain = $domainrestore_ref->{$domain}->{'required'};
            if ( ++$seen{$domain} > $number_of_domains + 1 ) {
                push @restore_order, $domain;
                delete $to_order{$domain};
                next DOMAIN;
            }
            elsif ( !$prereq_domain ) {
                push @restore_order, $domain;
                delete $to_order{$domain};
                next DOMAIN;
            }
            elsif ( $prereq_domain eq $maindomain ) {

                # Insert right after the maindomain which is always at
                # position 0
                splice( @restore_order, 1, 0, $domain );
                delete $to_order{$domain};
                next DOMAIN;
            }
            else {
                for my $domnum ( 1 .. $#restore_order ) {
                    if ( $restore_order[$domnum] eq $prereq_domain ) {

                        # Insert right after the prereq_domain
                        splice( @restore_order, $domnum + 1, 0, $domain );
                        delete $to_order{$domain};
                        next DOMAIN;
                    }
                }
            }
        }
    }

    my $count = 0;
    $domainrestore_ref->{$_}{'restoreorder'} = $count++ for @restore_order;

    return 1;
}

sub _sanitize_main_userdata_fetch_existing_domains {
    my ($self)        = @_;
    my $restored_user = $self->newuser();
    my $main_domain   = Cpanel::Validate::Domain::Normalize::normalize( $self->{'_utils'}->main_domain() );

    my $modified_userdata = 0;
    my $guard             = Cpanel::Config::userdata::Guard->new( $restored_user, 'main' );
    my $userdata_main_ref = $guard->data;
    Cpanel::Config::userdata::Utils::sanitize_main_userdata($userdata_main_ref);

    if ( !$userdata_main_ref->{'main_domain'} ) {
        $userdata_main_ref->{'main_domain'} = $main_domain;
        $self->warn( $self->_locale()->maketext( "The system added the missing domain “[_1]” to repair the [asis,userdata] for “[_2]”.", $main_domain, $restored_user ) );
        $modified_userdata = 1;
    }
    elsif ( $userdata_main_ref->{'main_domain'} ne $main_domain ) {

        # Needed for HB-6430. So long as we allow account overwrite, we have
        # to do more strict validation of what domains already exist on server.
        require Cpanel::DnsUtils::Exists;
        if ( !Cpanel::DnsUtils::Exists::domainexists($main_domain) && !grep { $_ eq 'DNS' || $_ eq 'ALL' } $self->archive_manager()->{'_utils'}{'flags'}{'keep_local_cpuser_values'} ) {
            my $incorrect_main_domain = $userdata_main_ref->{'main_domain'};
            $userdata_main_ref->{'main_domain'} = $main_domain;
            $self->warn( $self->_locale()->maketext( "The system replaced the incorrect main domain “[_1]” with the domain “[_2]” from the [asis,cPanel] user file in order to repair the [asis,userdata] for “[_3]”.", $incorrect_main_domain, $main_domain, $restored_user ) );
            $modified_userdata = 1;
        }
    }

    my %existing_domains;
    foreach my $type ( keys %Cpanel::Config::userdata::Utils::DOMAIN_KEY_TYPE ) {
        my $data_type = $Cpanel::Config::userdata::Utils::DOMAIN_KEY_TYPE{$type};
        $existing_domains{$type} = ( $data_type eq 'HASH' ) ? $userdata_main_ref->{$type} : { map { $_ => 1 } @{ $userdata_main_ref->{$type} } };
    }

    if ($modified_userdata) {
        $guard->save();
    }
    else {
        $guard->abort();
    }

    return \%existing_domains;
}

1;
