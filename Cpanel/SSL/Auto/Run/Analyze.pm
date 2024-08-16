package Cpanel::SSL::Auto::Run::Analyze;

# cpanel - Cpanel/SSL/Auto/Run/Analyze.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::Analyze

=head1 SYNOPSIS

    ( $dcv_domains_ar, $dsets_ar ) = Cpanel::SSL::Auto::Run::Analyze::analyze_domain_sets_ssl_status(
        username => 'bobuser',
        provider_obj => $provider_obj,
        problems_obj => $problems_obj,
        webvhosts_report => $ssl_report_ar,
        dynamicdns_report => $ddns_report_ar,
    );

=head1 DESCRIPTION

This module contains individual pieces of logic for AutoSSL that are
complex enough to warrant maintenance and testing as dedicated interfaces.

=cut

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::ClassDispatch                         ();
use Cpanel::Context                               ();
use Cpanel::LocaleString                          ();
use Cpanel::UserZones::User                       ();
use Cpanel::SSL::Auto::Config::Read               ();
use Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS ();
use Cpanel::SSL::Auto::Run::Vhost                 ();

use constant NON_CRITICAL_IMPEDIMENTS => (
    'CERTIFICATE_HAS_MAX_DOMAINS',
    'CERTIFICATE_IS_EXTERNALLY_SIGNED',
    'COMPLETELY_EXCLUDED',
);

=head1 FUNCTIONS

=head2 ( $DCV_DOMAINS_AR, $VHOSTS_AR ) = analyze_domain_sets_ssl_status( %OPTS )

This does an initial analysis of the user’s SSL coverage.

%OPTS is:

=over

=item * C<username>

=item * C<provider_obj> - An instance of the appropriate
L<Cpanel::SSL::Auto::Provider> subclass.

=item * C<problems_obj> - An instance of L<Cpanel::SSL::Auto::Problems>.

=item * C<webvhosts_report> - arrayref, the results of C<Cpanel::SSL::VhostCheck::get_report_for_user()>

=item * C<dynamicdns_report> - arrayref of L<Cpanel::SSL::DynamicDNSCheck::Item> instances

=back

The return is two arrayrefs:

=over

=item * All AutoSSL-eligible domains that need DCV, in one big list.
This includes domains for web vhosts that aren’t already fully SSL-covered
(but I<not> including reducer-wildcard domains)
B<as> B<well> B<as> dynamic DNS subdomains for which the account lacks
a suitable valid certificate.

=item * All domain set objects (i.e., instances of
L<Cpanel::SSL::Auto::Run::DomainSet>) whose domains are to be DCVed.

=back

=cut

sub analyze_domain_sets_ssl_status {
    my %opts = @_;

    my ( $username, $provider_obj, $problems_obj ) = @opts{
        'username',
        'provider_obj',
        'problems_obj',
    };

    Cpanel::Context::must_be_list();

    my @domains_to_dcv;
    my @domain_sets_to_renew;

    my $user_zones_hr = _get_user_zones_hr($username);

    my @domain_set_objs = map {
        Cpanel::SSL::Auto::Run::Vhost->new(
            $provider_obj,
            $username,
            $_,
            $user_zones_hr,
        );
    } @{ $opts{'webvhosts_report'} };

    push @domain_set_objs, map {
        my $item_obj = $_;

        Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS->new(
            $provider_obj,
            $username,
            { map { $_ => $item_obj->$_() } qw( domain certificate ) },
        );
    } @{ $opts{'dynamicdns_report'} };

    for my $dset_obj (@domain_set_objs) {
        _log_analyzing($dset_obj);

        my $indent = $provider_obj->create_log_level_indent();

        try {

            # If there are more domains in the set than we can put on
            # the certificate, then log about it.
            if ( $dset_obj->eligible_domains() > $provider_obj->MAX_DOMAINS_PER_CERTIFICATE() ) {
                log_domain_set_domain_counts($dset_obj);

                log_cert_domain_count_limit($provider_obj);

                # Hopefully this will be rare …
                $provider_obj->log( warn => locale()->maketext( '“[_1]” cannot secure all of “[_2]”’s domains. Remove domains from “[_2]” to fix this.', $provider_obj->DISPLAY_NAME(), $dset_obj->name() ) );
            }

            log_exclusions($dset_obj);

            # Excluded domains should not be in the problems DB.
            # This is just in case any “stragglers” are in there.
            $problems_obj->unset_domains(
                $dset_obj->user_excluded_domains(),
                $dset_obj->provider_excluded_domains(),
            );

            my $tls_state = $dset_obj->determine_tls_state();

            log_tls_state( $provider_obj, $dset_obj, $tls_state );

            if ( $dset_obj->get_certificate_object() ) {
                log_expiry_time( $dset_obj, $provider_obj );
            }

            if ( $tls_state ne 'ok' ) {
                my $skip_yn;

                if ( $tls_state eq 'defective' ) {
                    for my $defect ( $dset_obj->get_defects() ) {
                        $provider_obj->log(
                            'error',
                            locale()->maketext( 'Defect: [_1]', $defect ),
                        );
                    }
                }

                if ( $dset_obj->certificate_is_externally_signed() ) {
                    if ( $tls_state ne 'defective' || !_clobber_externally_signed_yn() ) {
                        log_impediment( $provider_obj, 'CERTIFICATE_IS_EXTERNALLY_SIGNED' );
                        $skip_yn = 1;
                    }
                }

                my @eligible_domains = $dset_obj->eligible_domains();

                if (@eligible_domains) {
                    if ( !$skip_yn && $tls_state eq 'incomplete' ) {
                        $skip_yn = !incomplete_domain_set_can_add_ssl_domains($dset_obj);
                    }
                }
                else {
                    log_impediment( $provider_obj, 'COMPLETELY_EXCLUDED' );
                    $skip_yn = 1;
                }

                if ( !$skip_yn ) {
                    push @domains_to_dcv,       $dset_obj->eligible_domains();
                    push @domain_sets_to_renew, $dset_obj;
                }
            }
        }
        catch {
            warn $_;
        };
    }

    return ( \@domains_to_dcv, \@domain_sets_to_renew );
}

=head2 incomplete_domain_set_can_add_ssl_domains( $DSET_OBJ )

$DSET_OBJ is an instance of L<Cpanel::SSL::Auto::Run::DomainSet>.

This returns a boolean that indicates whether the domain set
(which is understood to be in “incomplete” state) has any room to
add domains, relative to the domain set’s AutoSSL provider’s limit on
number of domains per certificate.

It also logs relevant details to the provider instance.

=cut

sub incomplete_domain_set_can_add_ssl_domains {
    my ($dset_report) = @_;

    my $provider_obj = $dset_report->get_provider_object();

    my $number_of_domains_left = $provider_obj->MAX_DOMAINS_PER_CERTIFICATE() - $dset_report->secured_domains();

    if ( $number_of_domains_left < 1 ) {

        # There’s no point in doing DCV when we know we
        # won’t get a certificate that improves on the
        # current one’s number of secured domains.
        log_impediment( $provider_obj, 'CERTIFICATE_HAS_MAX_DOMAINS' );

        return 0;
    }

    return 1;
}

=head2 log_expiry_time( $DSET_OBJ )

$VHOST_OBJ is an instance of L<Cpanel::SSL::Auto::Run::Vhost>.

This logs the domain set’s certificate’s expiry time to the provider
instance.

=cut

sub log_expiry_time {
    my ($dset_report) = @_;

    my $provider_obj = $dset_report->get_provider_object();

    if ( my $expiry_time = $dset_report->certificate_expiry_time() ) {
        my $time_msg;

        my $days_left = sprintf( '%.02f', ( $expiry_time - _time() ) / 86400 );

        my $log_level;

        if ( $days_left > 0 ) {
            $time_msg = locale()->maketext( '[quant,_1,day,days] from now', $days_left );

            if ( grep { index( $_, 'ALMOST_EXPIRED:' ) == 0 } $dset_report->get_defects() ) {
                $log_level = 'error';
            }
            elsif ( $dset_report->certificate_is_in_renewal_period() ) {
                $log_level = 'warn';
            }
            else {
                $log_level = 'info';
            }
        }
        else {
            $log_level = 'error';
            $time_msg  = locale()->maketext( '[quant,_1,day,days] ago', -$days_left );
        }

        $provider_obj->log(
            $log_level,
            locale()->maketext( 'Certificate expiry: [datetime,_1,datetime_format_short] [asis,UTC] ([_2])', $expiry_time, $time_msg ),
        );
    }

    return;
}

=head2 log_exclusions( $DSET_OBJ )

$DSET_OBJ is an instance of L<Cpanel::SSL::Auto::Run::DomainSet>.

This logs the domain set’s AutoSSL-excluded domains. It distinguishes
between user-excluded and provider-excluded domains.

=cut

sub log_exclusions ($dset_report) {

    my $provider_obj = $dset_report->get_provider_object();

    my $username = $dset_report->get_username();

    if ( my @user_excluded = $dset_report->user_excluded_domains() ) {
        $provider_obj->log(
            'info',
            locale()->maketext( 'User-excluded [numerate,_1,domain,domains]: [_2]', 0 + @user_excluded, format_domain_list_for_log( \@user_excluded, $username, $provider_obj ) ),
        );
    }

    if ( my @provider_excluded = $dset_report->provider_excluded_domains() ) {
        $provider_obj->log(
            'info',
            locale()->maketext( 'Provider-excluded [numerate,_1,domain,domains]: [_2]', 0 + @provider_excluded, format_domain_list_for_log( \@provider_excluded, $username, $provider_obj ) ),
        );
    }

    return;
}

=head2 log_domain_set_domain_counts( $DSET_OBJ )

$DSET_OBJ is an instance of L<Cpanel::SSL::Auto::Run::DomainSet>.

This logs the number of domains on the domain set as well as the number
of those domains which are (SSL-)secured.

=cut

sub log_domain_set_domain_counts {
    my ($dset_report) = @_;

    my $provider_obj = $dset_report->get_provider_object();

    $provider_obj->log(
        'info',
        locale->maketext( 'Number of domains: [numf,_1]', 0 + @{ [ $dset_report->domains() ] } ),
    );

    $provider_obj->log(
        'info',
        locale->maketext( 'Number of secured domains: [numf,_1]', 0 + @{ [ $dset_report->secured_domains() ] } ),
    );

    return;
}

=head2 log_cert_domain_count_limit( $PROVIDER_OBJ )

$PROVIDER_OBJ is an instance of a subclass of L<Cpanel::SSL::Auto::Provider>.

This logs the provider’s limit on the number of domains per certificate.

=cut

sub log_cert_domain_count_limit {
    my ($provider_obj) = @_;

    $provider_obj->log(
        'warn',
        locale()->maketext( 'Provider’s per-certificate domain count limit: [numf,_1]', $provider_obj->MAX_DOMAINS_PER_CERTIFICATE() ),
    );

    return;
}

#----------------------------------------------------------------------

=head2 log_tls_state( $PROVIDER_OBJ, $DSET_REPORT, $TLS_STATE )

$PROVIDER_OBJ is an instance of a subclass of L<Cpanel::SSL::Auto::Provider>.

$DSET_REPORT is a L<Cpanel::SSL::Auto::Run::DomainSet> instance.

$TLS_STATE is one of: C<ok>, C<incomplete>, C<renewal>,
C<default_key_mismatch>, C<defective>.

This logs the TLS state to the provider instance. It is assumed that this is
called from the context of a domain set and that the log’s indentation
clarifies to the reader which domain set’s state is being reported.

=cut

my %TLS_STATE;

sub log_tls_state ( $provider_obj, $dset_report, $tls_state ) {    ## no critic qw(ManyArgs) - mis-parse

    if ( !%TLS_STATE ) {
        %TLS_STATE = (
            defective            => [ error   => Cpanel::LocaleString->new('[asis,TLS] Status: Defective') ],
            default_key_mismatch => [ info    => Cpanel::LocaleString->new('[asis,TLS] Status: Default Key Type Mismatch') ],
            renewal              => [ info    => Cpanel::LocaleString->new('[asis,TLS] Status: Ready for Renewal') ],
            incomplete           => [ info    => Cpanel::LocaleString->new('[asis,TLS] Status: Incomplete') ],
            ok                   => [ success => Cpanel::LocaleString->new('[asis,TLS] Status: OK') ],
        );
    }

    if ( my $state_ar = $TLS_STATE{$tls_state} ) {
        my ( $level, $lstr ) = @$state_ar;

        $provider_obj->log( $level, $lstr->to_string() );

        my $indent = $provider_obj->create_log_level_indent();

        for my $detail ( $dset_report->get_tls_state_details() ) {
            $provider_obj->log( info => $detail );
        }
    }
    else {
        warn "Unknown TLS status: “$tls_state”";
    }

    return;
}

#----------------------------------------------------------------------

=head2 log_impediment( $PROVIDER_OBJ, $IMPEDIMENT )

$PROVIDER_OBJ is an instance of a subclass of L<Cpanel::SSL::Auto::Provider>.

$IMPEDIMENT is one of the various impediment types, e.g.,
C<TOTAL_DCV_FAILURE>. See the code for a full list of these.

This logs an impediment to the provider instance. It is assumed that this is
called from the context of a domain set and that the log’s indentation
clarifies to the reader which domain set’s impediment is being reported.

=cut

#accessed from tests
our %_impediment_phrases;

sub log_impediment {
    my ( $provider_obj, $impediment ) = @_;

    my $log_level;
    if ( grep { $_ eq $impediment } NON_CRITICAL_IMPEDIMENTS() ) {
        $log_level = 'info';
    }
    else {
        $log_level = 'error';
    }

    if ( !%_impediment_phrases ) {
        %_impediment_phrases = (
            CERTIFICATE_IS_EXTERNALLY_SIGNED => locale()->maketext('The certificate is neither self-signed nor from [asis,AutoSSL].'),
            TOTAL_DCV_FAILURE                => locale()->maketext('Every domain failed [asis,DCV].'),
            CERTIFICATE_HAS_MAX_DOMAINS      => locale()->maketext('The provider does not issue certificates that include more domains than the current certificate includes.'),
            NO_UNSECURED_DOMAIN_PASSED_DCV   => locale()->maketext('Every unsecured domain failed [asis,DCV].'),
            SECURED_DOMAIN_DCV_FAILURE       => locale()->maketext('One or more currently-secured domains failed [asis,DCV].'),
            COMPLETELY_EXCLUDED              => locale()->maketext('All domains are excluded from [asis,AutoSSL].'),
        );
    }

    #Cobra’s docs and dev went back and forth on the term “impediment”.
    #It’s unusual in the product because normally we’d prefer “error”;
    #however, “error” doesn’t apply in cases like COMPLETELY_EXCLUDED,
    #which isn’t a failure state.
    #
    #The idea of the “impediment” is that it’s a simple “reason for
    #stopping” that isn’t necessarily a failure. Since this isn’t a UI
    #control and there is already the ERROR/INFO indication in the log,
    #this uses the word “impediment” to indicate stoppage explicitly.
    $provider_obj->log(
        $log_level,
        locale()->maketext( 'Impediment: [_1]: [_2]', $impediment, $_impediment_phrases{$impediment} ),
    );

    return;
}

#----------------------------------------------------------------------

=head2 format_domain_list_for_log( \@DOMAINS, $USERNAME, $PROVIDER_OBJ )

@DOMAINS is a list of domain names. $PROVIDER_OBJ is an instance of a
subclass of L<Cpanel::SSL::Auto::Provider>.

This returns a string whose value is a formatted count and list of domains
for the $PROVIDER_OBJ’s log. It enforces a reasonable limit on the number
of domains to list; larger lists of domain names are truncated with an
ellipsis (“…”).

=cut

#overridden in tests
our $_FORMAT_DOMAIN_LIST_LIMIT = 10;

sub format_domain_list_for_log {
    my ( $domains_ar, $username, $provider_obj ) = @_;

    my @sorted = $provider_obj->SORT_VHOST_FQDNS( $username, @$domains_ar );

    my $count = @$domains_ar;
    my @display_list;

    my $list_str;

    if ( @sorted <= $_FORMAT_DOMAIN_LIST_LIMIT ) {

        $list_str = join( ', ', @sorted );
    }
    else {
        $list_str = join( ', ', @sorted[ 0 .. ( $_FORMAT_DOMAIN_LIST_LIMIT - 1 ) ], '…' );
    }

    return sprintf( '%d (%s)', 0 + @sorted, $list_str );
}

#----------------------------------------------------------------------

sub _log_analyzing ($dset_obj) {
    my $provider_obj = $dset_obj->get_provider_object();

    my $phrase = Cpanel::ClassDispatch::dispatch(
        $dset_obj,
        'Cpanel::SSL::Auto::Run::Vhost' => sub {
            locale()->maketext( 'Analyzing “[_1]” (website) …', $dset_obj->name() );
        },
        'Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS' => sub {
            locale()->maketext( 'Analyzing “[_1]” (dynamic [asis,DNS]) …', $dset_obj->name() );
        },
    );

    $provider_obj->log( info => $phrase );

    return;
}

sub _time { return time; }

#overwritten in tests
our $_CLOBBER_EXTERNALLY_SIGNED;

sub _clobber_externally_signed_yn {
    return $_CLOBBER_EXTERNALLY_SIGNED //= do {
        my $conf = Cpanel::SSL::Auto::Config::Read->new();
        !!$conf->get_metadata()->{'clobber_externally_signed'};
    };
}

sub _get_user_zones_hr {
    my ($username) = @_;
    my %user_zones;
    my @all_zones = Cpanel::UserZones::User::list_user_dns_zone_names($username);
    @user_zones{@all_zones} = ();
    return \%user_zones;
}

1;
