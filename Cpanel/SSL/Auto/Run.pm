package Cpanel::SSL::Auto::Run;

# cpanel - Cpanel/SSL/Auto/Run.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run

=head1 DESCRIPTION

This module contains generic run-time logic for AutoSSL.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Promise::ES6 ();

use Cpanel::Imports;

use Cpanel::DNS::Unbound::Async              ();
use Cpanel::Exception                        ();
use Cpanel::Config::LoadCpUserFile           ();
use Cpanel::PromiseUtils                     ();
use Cpanel::SSL::Auto::Run::CAA              ();
use Cpanel::SSL::Auto::Run::DomainManagement ();
use Cpanel::SSL::Auto::Run::DCV              ();
use Cpanel::SSL::Auto::Run::LocalAuthority   ();
use Cpanel::SSL::Auto::Run::User             ();
use Cpanel::SSL::Auto::Wildcard              ();
use Cpanel::Features::Check                  ();
use Cpanel::Set                              ();
use Cpanel::WebCalls::Datastore::Read        ();
use Cpanel::WildcardDomain::Tiny             ();

use constant _REQUIRED_FEATURES => qw(
  autossl
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @values = analyze_vhosts_and_do_http_dcv( $PROVIDER_OBJ, $PROBLEMS_OBJ, \@USERNAMES )

This iterates through each of @USERNAMES, for each user
verifying AutoSSL access before doing AutoSSL’s SSL analysis and,
if needed, HTTP DCV.

Along the way, the relevant entries in $PROVIDER_OBJ’s
log and $PROBLEMS_OBJ are created.

$PROVIDER_OBJ is a L<Cpanel::SSL::Auto::Provider> subclass instance.
$PROBLEMS_OBJ is a L<Cpanel::SSL::Auto::Problems> instance.

This returns a list of values:

=over

=item * Hash reference: username => L<Cpanel::SSL::Auto::Run::User> instance

=item * Hash reference: username => Array reference of domains that need DNS DCV (this preserves proper sort order)

=item * Hash reference: username => Array reference of names of vhosts that could use an SSL certificate

=item * Hash reference: username => L<Cpanel::SSL::Auto::Run::DCVResult> instance

=item * Array reference of L<Cpanel::SSL::DCV::DNS::Mutex> instances

=item * Array reference of zones that need DNS DCV.

=back

The username-keyed hash references should all contain the same keys;
any usernames that are missing indicate a user that does not have
access to AutoSSL.

=cut

sub analyze_vhosts_and_do_http_dcv {
    my ( $provider_obj, $problems_obj, $usernames_ar ) = @_;

    # Holds Cpanel::SSL::Auto::Run::User instances.
    my %user_obj;

    # Holds Cpanel::SSL::Auto::Run::DCVResult instances.
    my %user_dcv_obj;

    # Holds arrayrefs of domain set objects.
    my %user_domain_sets_to_renew;

    # Holds arrayrefs of domain names.
    my %user_dns_dcv_domains;

    my @dns_dcv_mutexes;

    my @dns_dcv_zones;

  USERNAME:
    for my $username (@$usernames_ar) {
        next if !_user_can_use_autossl( $provider_obj, $username );

        try {
            $provider_obj->log( info => locale()->maketext( 'Analyzing “[_1]”’s domains …', $username ) );

            my $indent = $provider_obj->create_log_level_indent();

            my $run_user_obj = Cpanel::SSL::Auto::Run::User->new(
                username     => $username,
                provider_obj => $provider_obj,
                problems_obj => $problems_obj,
            );

            my ( $created_domains_to_dcv_ar, $dsets_to_renew_ar ) = $run_user_obj->determine_dcv_needs();

            if ( !@$created_domains_to_dcv_ar ) {
                $provider_obj->log( success => locale()->maketext('This user’s [asis,SSL] coverage is already optimal.') );
            }
            else {

                # For a non-wildcard provider this just stays empty.
                my @reducer_wildcards;

                my @ddns_domains = _get_ddns_domains($username);

                if ( $provider_obj->SUPPORTS_WILDCARD() ) {

                    # Don’t attempt wildcard reduction on DDNS domains.
                    my @wc_reducible_domains = Cpanel::Set::difference(
                        $created_domains_to_dcv_ar,
                        \@ddns_domains,
                    );

                    @reducer_wildcards = Cpanel::SSL::Auto::Wildcard::find_reducer_wildcards(@wc_reducible_domains);

                    # Exclude user-created domains from this list.
                    @reducer_wildcards = Cpanel::Set::difference(
                        \@reducer_wildcards,
                        $created_domains_to_dcv_ar,
                    );
                }

                my $managed_and_caa_ok_domains = _handle_management_and_caa(
                    $provider_obj,
                    [ @$created_domains_to_dcv_ar, @reducer_wildcards ],
                );

                @$created_domains_to_dcv_ar = Cpanel::Set::intersection(
                    $created_domains_to_dcv_ar,
                    $managed_and_caa_ok_domains,
                );

                if ( !@$created_domains_to_dcv_ar ) {
                    $provider_obj->log( info => locale()->maketext( '[asis,AutoSSL] cannot increase “[_1]”’s [asis,SSL] coverage.', $username ) );
                }
                else {

                    my @user_created_wildcards = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @$created_domains_to_dcv_ar;

                    # For a non-wildcard provider this just stays empty.
                    my @user_created_wildcards_to_dcv;

                    if ( $provider_obj->SUPPORTS_WILDCARD() ) {
                        @user_created_wildcards_to_dcv = @user_created_wildcards;
                    }

                    my @http_dcv_domains = Cpanel::Set::difference(
                        $created_domains_to_dcv_ar,
                        \@ddns_domains,

                        # HTTP DCV is useless for wildcards as of Dec 2021.
                        #
                        \@user_created_wildcards,
                    );

                    if (@http_dcv_domains) {
                        $provider_obj->log( info => locale()->maketext( 'Performing [asis,HTTP] [output,abbr,DCV,Domain Control Validation] on [quant,_1,domain,domains] …', 0 + @http_dcv_domains ) );
                    }
                    else {

                        # This should only happen if the only domain sets
                        # that warrant new SSL are all DDNS.
                        $provider_obj->log( info => locale()->maketext('No domains need [asis,HTTP] [output,abbr,DCV,Domain Control Validation].') );
                    }

                    # This excludes reducer wildcard domains.
                    # See below for an explanation.
                    my $dcv_obj = Cpanel::SSL::Auto::Run::DCV::get_user_http_dcv_results(
                        $username,
                        $provider_obj,
                        \@http_dcv_domains,
                    );

                    $user_obj{$username} = $run_user_obj;

                    $user_domain_sets_to_renew{$username} = $dsets_to_renew_ar;

                    $user_dcv_obj{$username} = $dcv_obj;

                    $user_dns_dcv_domains{$username} = [];

                    my @ddns_domains_to_dcv = Cpanel::Set::intersection(
                        $created_domains_to_dcv_ar,
                        \@ddns_domains,
                    );

                    # NB: intersection() preserves $created_domains_to_dcv_ar’s sort order.
                    my @dns_dcv_domains = Cpanel::Set::intersection(
                        $created_domains_to_dcv_ar,
                        [
                            $dcv_obj->get_dns_pending_domains(),
                            @ddns_domains_to_dcv,
                            @user_created_wildcards_to_dcv,
                        ],
                    );

                    @reducer_wildcards = Cpanel::Set::intersection(
                        \@reducer_wildcards,
                        $managed_and_caa_ok_domains,
                    );

                    push @dns_dcv_domains, @reducer_wildcards;

                    if (@dns_dcv_domains) {
                        Cpanel::SSL::Auto::Run::LocalAuthority::filter_dns_dcv_domains_by_local_authority(
                            \@dns_dcv_domains,
                            $dcv_obj,
                            $provider_obj,
                        );
                    }

                    if (@dns_dcv_domains) {
                        require Cpanel::SSL::DCV::DNS;

                        try {
                            my ( $mutex, $zones_ar ) = Cpanel::SSL::DCV::DNS::get_mutex_and_domain_dcv_zones( $username, \@dns_dcv_domains );

                            push @{ $user_dns_dcv_domains{$username} }, @dns_dcv_domains;

                            push @dns_dcv_mutexes, $mutex;
                            push @dns_dcv_zones,   @$zones_ar;

                            $provider_obj->log( info => locale()->maketext( 'Enqueueing [quant,_1,domain,domains] ([quant,_2,zone,zones]) for local [asis,DNS] [asis,DCV] …', 0 + @dns_dcv_domains, 0 + @$zones_ar ) );
                        }
                        catch {
                            my $err = Cpanel::Exception::get_string($_);

                            $dcv_obj->add_dns( $_, $err ) for @dns_dcv_domains;
                        };
                    }
                    else {
                        $provider_obj->log( info => locale()->maketext('No local [asis,DNS] [asis,DCV] is necessary.') );
                    }
                }
            }
        }
        catch {

            # This should be very rare, so for now leave it untranslated:
            warn "Failed to begin “$username”’s DCV: $_";
        };
    }

    return ( \%user_obj, \%user_dns_dcv_domains, \%user_domain_sets_to_renew, \%user_dcv_obj, \@dns_dcv_mutexes, \@dns_dcv_zones );
}

sub _get_ddns_domains ($username) {
    my $id_entry = Cpanel::WebCalls::Datastore::Read->read_for_user($username);
    my @objs     = grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS'); } values %$id_entry;

    return map { $_->domain() } @objs;
}

# Ideally this function would return a list of promises that would indicate
# whether continuance to HTTP DCV is indicated for the individual domain.
# But that’s not all that useful unless we implement parallel HTTP DCV.
sub _handle_management_and_caa ( $provider_obj, $domains_ar ) {

    # This installs missing CAA records
    Cpanel::SSL::Auto::Run::CAA::apply_needed_caa_records(
        $provider_obj,
        $domains_ar,
    );

    my $resolver = Cpanel::DNS::Unbound::Async->new();

    # This sets up promises to see if domains are a check to see if a DNS has any functional
    # authoritative nameservers for a given domain.
    #
    # Historiclly we have called this the regsitered domain check
    my $mgt_promises_ar = Cpanel::SSL::Auto::Run::DomainManagement::find_unmanaged_domains(
        $resolver,
        $provider_obj,
        $domains_ar,
    );

    # Now we setup promises to chek if CAA records forbid issuance
    # by the currently active AutoSSL provider.
    my $caa_promises_ar = Cpanel::SSL::Auto::Run::CAA::find_forbidden_domains(
        $resolver,
        $provider_obj,
        $domains_ar,
    );

    my %is_insecurable;

    for my $d ( 0 .. $#$domains_ar ) {
        my $domain = $domains_ar->[$d];

        my $cb = sub ($failed) {
            $is_insecurable{$domain} = 1 if $failed;
        };

        $mgt_promises_ar->[$d]->then($cb);
        $caa_promises_ar->[$d]->then($cb);
    }

    # If we have thousands of domains, the time to generate the backtraces
    # for 'DNS::ErrorResponse' can take minutes and result in a 100% cpu condition
    # so we supress stack traces.
    my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

    my $all_p = Promise::ES6->all(
        [
            @$mgt_promises_ar,
            @$caa_promises_ar,
        ]
    );

    Cpanel::PromiseUtils::wait_anyevent($all_p);

    my @good = Cpanel::Set::difference(
        $domains_ar,
        [ keys %is_insecurable ],
    );

    return \@good;
}

# stubbed in tests
sub _user_can_use_autossl ( $provider_obj, $username ) {

    my $cpuser_conf;
    try {
        $cpuser_conf = Cpanel::Config::LoadCpUserFile::load_or_die($username);
    }
    catch {
        warn locale()->maketext( 'The system failed to load the “[_1]” account’s data file because of an error: [_2]', $username, Cpanel::Exception::get_string($_) ) . "\n";
    };

    return 0 if !$cpuser_conf;

    if ( $cpuser_conf->{'SUSPENDED'} ) {
        $provider_obj->log( info => locale()->maketext( '“[_1]” is suspended.', $username ) );
        return 0;
    }

    my @missing = grep { !Cpanel::Features::Check::check_feature_for_user( $username, $_, ( $cpuser_conf->{'FEATURELIST'} || 'default' ), $cpuser_conf ); } _REQUIRED_FEATURES;

    if (@missing) {
        $provider_obj->log( info => locale()->maketext( '“[_1]” does not possess the required [numerate,_2,feature,features] ([list_and_quoted,_3]).', $username, scalar(@missing), \@missing ) );
        return 0;
    }

    return 1;
}

1;
