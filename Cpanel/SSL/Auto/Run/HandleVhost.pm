package Cpanel::SSL::Auto::Run::HandleVhost;

# cpanel - Cpanel/SSL/Auto/Run/HandleVhost.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::HandleVhost

=head1 SYNOPSIS

    handle_defective( $vh_obj, $problems_obj, $dcv_result_obj );

    handle_default_key_mismatch( $vh_obj, $problems_obj, $dcv_result_obj );

    handle_renewal( $vh_obj, $problems_obj, $dcv_result_obj );

    handle_incomplete( $vh_obj, $problems_obj, $dcv_result_obj );

=head1 DESCRIPTION

This module examines local DCV results and determines whether there is
any impediment to requesting a certificate.

Note that this module no longer handles cases where no DCV is done
on the vhost. This applies, e.g., when an incomplete-state vhost has
already maxed out its domains per certificate (i.e., the
C<CERTIFICATE_HAS_MAX_DOMAINS> impediment), or if C<clobber_externally_signed>
is disabled.

The handler states (i.e., C<defective>, C<renewal>, C<default_key_mismatch>,
C<incomplete>) correspond with the return value of
C<Cpanel::SSL::Auto::Run::Vhost::determine_tls_state()>.

This does NOT do notifications; for that, see
L<Cpanel::SSL::Auto::Run::Notify>.

=cut

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Set                          ();
use Cpanel::Time::ISO                    ();

=head1 HANDLER FUNCTIONS

The functions below determine if AutoSSL should request a
new certificate based on their respective statuses.

None of these return anything; instead, RUN_VHOST_OBJ’s C<impediment>
attribute (cf. L<Cpanel::AttributeProvider>) is set.

=head2 handle_defective( RUN_VHOST_OBJ, PROBLEMS_OBJ, DCV_RESULT_OBJ )

The arguments are instances of L<Cpanel::SSL::Auto::Run::Vhost>,
L<Cpanel::SSL::Auto::Problems>, and L<Cpanel::SSL::DCV::Run::DCVResult>,
respectively.

No impediments are given as long as B<at least one>
domain on the vhost passes DCV. (Caveat: see below about externally-signed
certificates.)

Rationale: SSL is defective on the vhost—e.g., no certificate, expired,
self-signed, or what not. Any valid certificate is better than an
invalid (or missing) one, even if that means going from total SSL coverage
to only a single domain.

=cut

sub handle_defective {
    my ( $vh_report, $problems_obj, $dcv_result_obj ) = @_;

    _catch_impediment(
        $vh_report,
        $problems_obj,
        $dcv_result_obj,
        sub {
            _do_provider_dcv_if_supported(
                $vh_report,
                $dcv_result_obj,
            );

            if ( $vh_report->certificate_is_externally_signed() ) {
                my $provider_obj = $vh_report->get_provider_object();

                $provider_obj->log( 'warn' => locale()->maketext('Replacing an externally-signed certificate …') );
            }
        }
    );

    return;
}

#----------------------------------------------------------------------

=head2 handle_renewal( RUN_VHOST_OBJ, PROBLEMS_OBJ, DCV_RESULT_OBJ )

Will indicate to request a certificate only if the following are true:

=over

=item * B<All currently-secured> domains pass DCV.

If this check fails, we set RUN_VHOST_OBJ’s C<impediment> attribute to
either C<TOTAL_DCV_FAILURE> or C<SECURED_DOMAIN_DCV_FAILURE> as appropriate.

=item * The certificate is not externally signed.

If this check fails, we set RUN_VHOST_OBJ’s C<impediment> attribute to
C<CERTIFICATE_IS_EXTERNALLY_SIGNED>.

=back

Rationale: Nothing is “wrong”, but it’s about to be if we don’t get a
fresh certificate because the current certificate is approaching expiry.
It’s not (yet) worth accepting a loss in coverage, so we don’t move unless
we’ll keep the same (or better) coverage.

=cut

sub handle_renewal {
    my ( $vh_report, $problems_obj, $dcv_result_obj ) = @_;

    _catch_impediment(
        $vh_report,
        $problems_obj,
        $dcv_result_obj,
        sub {
            _dcv_for_noncritical_state( $vh_report, $dcv_result_obj );
        },
    );

    return;
}

#----------------------------------------------------------------------

=head2 handle_default_key_mismatch( RUN_VHOST_OBJ, PROBLEMS_OBJ, DCV_RESULT_OBJ )

Identical behavior to C<handle_renewal()>.

The rationale is similar: we should replace the certificate as long as
we retain coverage of all currently-secured, currently-eligible domains.

=cut

*handle_default_key_mismatch = *handle_renewal;

#----------------------------------------------------------------------

sub _stop_if_any_secured_domains_fail_dcv {
    my ( $vh_report, $dcv_result_obj ) = @_;

    # Avoid external DCV if any currently-secured domains
    # have already failed DCV.
    # (i.e., “SECURED_DOMAIN_DCV_FAILURE”)
    my $has_secured_failure = Cpanel::Set::intersection(
        [ $vh_report->secured_domains() ],
        [ $dcv_result_obj->get_failed_domains() ],
    );

    if ($has_secured_failure) {
        _throw_impediment('SECURED_DOMAIN_DCV_FAILURE');
    }

    return;
}

#----------------------------------------------------------------------

=head2 handle_incomplete( RUN_VHOST_OBJ, PROBLEMS_OBJ, DCV_RESULT_OBJ )

Will indicate to request a certificate only if all of the following are true:

=over

=item * The same conditions that C<handle_renewal()> imposes are met.
(The same attributes on RUN_VHOST_OBJ are set if this fails.)

=item * The provider is able to issue a certificate with more domains
than are on the current certificate. If not, RUN_VHOST_OBJ’s C<impediment>
attribute is set to C<CERTIFICATE_HAS_MAX_DOMAINS>.

=item * At least B<one unsecured> domain passes DCV. If not, RUN_VHOST_OBJ’s
C<impediment> attribute is set to C<NO_UNSECURED_DOMAIN_PASSED_DCV>.

=back

Rationale: Nothing is “wrong” or close to being so, but there are domains
on the virtual host that the current certificate doesn’t secure. It’s not
worth losing anything that we secure currently (e.g., if DCV fails for a
currently-secured domain), but if we can improve our position without any
loss, then let’s do it.

=cut

sub handle_incomplete {
    my ( $vh_report, $problems_obj, $dcv_result_obj ) = @_;

    _catch_impediment(
        $vh_report,
        $problems_obj,
        $dcv_result_obj,
        sub {

            #Incomplete is the same process as for renewal except we impose the
            #additional requirement that at least one unsecured domain must pass;
            #i.e., there has to be a good reason to request a new certificate
            #before it’s time to renew the one we have.
            #
            _stop_if_no_gained_domains( $vh_report, $dcv_result_obj );

            #This will DCV all of the secured domains plus any unsecured that
            #the provider could secure.
            my $did_provider_dcv = _dcv_for_noncritical_state( $vh_report, $dcv_result_obj );

            if ($did_provider_dcv) {

                # Re-check after provider DCV.
                _stop_if_no_gained_domains( $vh_report, $dcv_result_obj );
            }
        },
    );

    return;
}

#----------------------------------------------------------------------

use constant _IMPEDIMENT_CLASS => __PACKAGE__ . '::_impediment';

sub _catch_impediment {
    my ( $vh_report, $problems_obj, $dcv_result_obj, $todo_cr ) = @_;

    try {
        if ( !$dcv_result_obj->get_successful_domains() ) {
            _throw_impediment('TOTAL_DCV_FAILURE');
        }

        $todo_cr->();
    }
    catch {
        if ( try { $_->isa( _IMPEDIMENT_CLASS() ) } ) {
            $vh_report->set_attr( impediment => $$_ );
        }
        else {
            local $@ = $_;
            die;
        }
    }
    finally {

        # Always report DCV failures to the problems DB.
        _sync_dcv_failures_to_problems_db(
            $vh_report->get_username(),
            $dcv_result_obj,
            $problems_obj,
        );
    };

    return;
}

sub _throw_impediment {
    my ($type) = @_;

    die bless \$type, _IMPEDIMENT_CLASS();
}

sub _do_provider_dcv_if_supported {
    my ( $vh_report, $dcv_result_obj ) = @_;

    my $provider_obj = $vh_report->get_provider_object();

    my $can_do_external = $provider_obj->can('get_vhost_dcv_errors');

    if ($can_do_external) {

        my @local_successes = $dcv_result_obj->get_successful_domains();

        # NB: This must run as root!!
        _do_provider_dcv_for_domains(
            $vh_report,
            $dcv_result_obj,
            $provider_obj,
        );

        # Total DCV failure is always a show-stopper, regardless
        # of the vhost state.
        if ( !$dcv_result_obj->get_successful_domains() ) {
            _throw_impediment('TOTAL_DCV_FAILURE');
        }
    }

    return $can_do_external;
}

sub _stop_if_no_gained_domains {
    my ( $vh_report, $dcv_result_obj ) = @_;

    my $gained_domains = Cpanel::Set::intersection(
        [ $vh_report->missing_domains() ],
        [ $dcv_result_obj->get_successful_domains() ],
    );

    if ( !$gained_domains ) {
        _throw_impediment('NO_UNSECURED_DOMAIN_PASSED_DCV');
    }

    return;
}

sub _log_certificate_issuer {
    my ($vh_report) = @_;

    require Cpanel::X500::DN;

    my $provider_obj = $vh_report->get_provider_object();

    my $dn_str = Cpanel::X500::DN::encode_kv_list_as_rdns(
        map { @$_ } @{ $vh_report->get_certificate_object()->issuer_list() },
    );

    $provider_obj->log(
        'info',
        locale()->maketext( 'Issuer: [_1]', $dn_str ),
    );

    return;
}

#This will DCV the entire batch of domains.
#$do_external_yn_cr is optional.
#Returns a two-arg list: ( $dcv_hr, $ok_yn )
sub _dcv_for_noncritical_state {
    my ( $vh_report, $dcv_result_obj ) = @_;

    _stop_if_any_secured_domains_fail_dcv( $vh_report, $dcv_result_obj );

    my $did_provider_dcv = _do_provider_dcv_if_supported(
        $vh_report,
        $dcv_result_obj,
    );

    if ($did_provider_dcv) {

        # Repeat the same check as before now that we’ve done provider DCV.
        _stop_if_any_secured_domains_fail_dcv( $vh_report, $dcv_result_obj );
    }

    return $did_provider_dcv;
}

sub _do_provider_dcv_for_domains {
    my ( $vh_report, $run_dcv, $provider_obj ) = @_;

    require Cpanel::SSL::Auto::Run::HandleVhost::ProviderDCV;

    Cpanel::SSL::Auto::Run::HandleVhost::ProviderDCV::do_provider_dcv(
        $provider_obj,
        $vh_report,
        $run_dcv,
    );

    return;
}

# TEMPORARILY called from User.pm.
# TODO: Refactor in v76 to remove problems DB manipulation from this module.
sub _sync_dcv_failures_to_problems_db {
    my ( $username, $dcv_obj, $problems_obj ) = @_;

    # $dcv_obj is a Cpanel::SSL::Auto::Run::DCVResult
    my $domain_failure_hr = $dcv_obj->get_domain_failure_reasons();

    my %domain_failure;

    for my $domain ( keys %$domain_failure_hr ) {
        my @failure_strs = map { ( $_->{'method'} =~ tr<a-z><A-Z>r ) . " DCV: $_->{'reason'}" } @{ $domain_failure_hr->{$domain} };

        $domain_failure{$domain} = join( '; ', @failure_strs );
    }

    $problems_obj->set(
        $username,
        Cpanel::Time::ISO::unix2iso(),
        \%domain_failure,
    );

    my @successes = Cpanel::Set::difference(

        # $dcv_obj is a Cpanel::SSL::Auto::Run::DCVResult
        [ $dcv_obj->get_domains() ],
        [ keys %domain_failure ],
    );

    $problems_obj->unset_domains( $username, @successes );

    return;
}

sub _drop_privileges {
    my ($username) = @_;

    return Cpanel::AccessIds::ReducedPrivileges->new($username);
}

1;
