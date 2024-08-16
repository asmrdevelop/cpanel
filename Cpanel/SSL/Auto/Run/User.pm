package Cpanel::SSL::Auto::Run::User;

# cpanel - Cpanel/SSL/Auto/Run/User.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::User

=head1 SYNOPSIS

    my $obj = Cpanel::SSL::Auto::Run::User->new(
        user => 'bobuser',
        provider_obj => $provider_obj,
        problems_obj => $problems_obj,
    );

    my ( $dset_doms_hr, $dcv_hr ) = $obj->determine_new_certs_to_request(
        \@sets_to_renew,
        $dcv_obj,
    );

=head1 DESCRIPTION

This module encapsulates AutoSSL’s work with a single user.

=cut

use Cpanel::Imports;

use Cpanel::ClassDispatch               ();
use Cpanel::Context                     ();
use Cpanel::Exception                   ();
use Cpanel::Set                         ();
use Cpanel::SSL::Auto::Run::Analyze     ();
use Cpanel::SSL::Auto::Run::HandleVhost ();
use Cpanel::SSL::Auto::Run::Notify      ();
use Cpanel::SSL::Auto::Wildcard         ();
use Cpanel::SSL::DynamicDNSCheck        ();
use Cpanel::SSL::VhostCheck             ();
use Cpanel::Set                         ();
use Cpanel::Try                         ();

=head1 METHODS

=head2 I<CLASS>->new( %opts )

Returns an instance of CLASS.

%opts are:

=over

=item * C<username>

=item * C<provider_obj> - L<Cpanel::SSL::Auto::Provider> subclass instance

=item * C<problems_obj> - L<Cpanel::SSL::Auto::Problems> instance

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    my @expected = qw( username  provider_obj  problems_obj );

    my @missing = grep { !defined $opts{$_} } @expected;
    die "$class missing: [@missing]" if @missing;

    my %self = %opts{@expected};

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 ($domains_ar, $vhosts_ar) = I<OBJ>->determine_dcv_needs()

This analyzes each web vhost’s SSL coverage and determines which domains
hould be DCVed to try to add to a certificate.

The return is the same as L<Cpanel::SSL::Auto::Run::Analyze>’s
C<analyze_domain_sets_ssl_status()> return.

=cut

sub determine_dcv_needs {
    my ($self) = @_;

    # Any caller into this function should be able to work with any
    # provider, whether that provider has get_vhost_dcv_errors() or not.
    Cpanel::Context::must_be_list();

    my @webvhosts_report = Cpanel::SSL::VhostCheck::get_report_for_user( $self->{'username'} );

    my @dynamicdns_report = Cpanel::SSL::DynamicDNSCheck::get_report_for_user( $self->{'username'} );

    return Cpanel::SSL::Auto::Run::Analyze::analyze_domain_sets_ssl_status(
        %{$self}{ 'username', 'provider_obj', 'problems_obj' },
        webvhosts_report  => \@webvhosts_report,
        dynamicdns_report => \@dynamicdns_report,
    );
}

#----------------------------------------------------------------------

=head2 ( $vh_doms_hr, $dcv_hr ) = I<OBJ>->determine_new_certs_to_request( \@domain_sets_to_renew, $dcv_obj )

This function analyzes the local DCV results and therefrom determines
a set of certificates to request. For each of the user’s web
vhosts, it:

=over

=item * Identifies any TLS defects. (This includes being “almost expired”;
cf. L<Cpanel::SSL::VhostCheck>)

=item * Examines expiry time to see if we’re in the range where we
should replace.

=item * Notes any incomplete TLS coverage.

=back

The given arguments are:

=over

=item * An array reference of L<Cpanel::SSL::Auto::Run::DomainSet> instances:
one for each domain set whose TLS state and DCV results should be considered.

=item * A L<Cpanel::SSL::Auto::Run::DCVResult>
that represents the result of local DCV against the user’s domains.

=back

This returns a list:

=over

=item * A reference to a hash of ( $domain_set_name => $domains_ar ).
In the case of web vhosts, such a pair is suitable for sending to an
AutoSSL provider’s C<renew_ssl()> method as C<vhost_domains>.

=item * If the OBJ’s provider B<lacks> the C<get_vhost_dcv_errors()> method,
then a reference to a hash of ( domain => dcv_method ) is returned as well.
This is suitable for sending to the provider’s C<renew_ssl()> method
as C<domain_dcv_method>.

(If the provider does implement C<get_vhost_dcv_errors()>,
then this hash reference is not returned.)

=back

Along the way, this method sends iContact notifications if:

=over

=item * AutoSSL can’t replace a “defective” certificate because every
domain in the domain set fails DCV. (type = C<CertificateExpiring>)

=item * AutoSSL won’t replace a certificate that’s ready for renewal
(but not yet “almost expired”) because at least one currently-secured
domain in the domain set fails DCV. (type = C<CertificateExpiringCoverage>)

=item * AutoSSL won’t replace a certificate that leaves some vhost domains
unsecured because at least one currently-secured domain in the domain set
fails DCV. (type = C<CertificateRenewalCoverage>)

=back

Historically, this has been the part of AutoSSL that poses the biggest
maintenance challenge.

NB: This is no longer called externally but is significant enough to
warrant a direct test. Prior to v84, this actually did the DCV as well
as the post-analysis, so it was kind of the “heart” of AutoSSL. As of
v84 this function is I<just> the DCV post-analysis, so it’s a bit more
scoped. (Whew!)

=cut

sub determine_new_certs_to_request {
    my ( $self, $domain_sets_to_renew_ar, $dcv_result_obj ) = @_;

    my ( $username, $provider_obj, $problems_obj ) = @{$self}{qw( username  provider_obj  problems_obj )};

    my ( @new_certs, %domain_dcv_method );

  VHOST:
    for my $dset_report (@$domain_sets_to_renew_ar) {

        # Now that DCV is not done here, it’s debatable whether we should
        # have this header here and indent. Would the gain from reducing
        # “noise” in the logs by removing this outweigh the hierarchical
        # clarity that it gives?
        $provider_obj->log( info => locale()->maketext( 'Analyzing “[_1]”’s [asis,DCV] results …', $dset_report->name() ) );

        my $indent = $provider_obj->create_log_level_indent();

        Cpanel::Try::try(
            sub {
                my $tls_state = $dset_report->determine_tls_state();

                my $handler_name = "handle_$tls_state";

                # Example handlers: handle_defective, handle_renewal, handle_incomplete
                my $handler_cr = Cpanel::SSL::Auto::Run::HandleVhost->can($handler_name) or do {

                    #shouldn’t happen--programming error
                    die "No handler for vhost TLS state “$tls_state”!";
                };

                # $all_dcv_result_obj is a DCVResult for all of the user’s domains.
                # We need a DCVResult for just this vhost.
                my @eligible_domains = $dset_report->eligible_domains();

                my $slice_fn   = $dset_report->can_wildcard_reduce() ? 'slice_for_domains_wc' : 'slice_for_domains';
                my $vh_dcv_obj = $dcv_result_obj->$slice_fn( \@eligible_domains );

                $handler_cr->( $dset_report, $problems_obj, $vh_dcv_obj );

                if ( my $why_not = $dset_report->get_attr('impediment') ) {
                    Cpanel::SSL::Auto::Run::Analyze::log_impediment( $provider_obj, $why_not );

                    # Example handlers: handle_TOTAL_DCV_FAILURE, handle_SECURED_DOMAIN_DCV_FAILURE
                    my $notifier_cr = Cpanel::SSL::Auto::Run::Notify->can("handle_$why_not");
                    if ($notifier_cr) {
                        $notifier_cr->($dset_report);
                    }
                }
                else {
                    my $dcv_method_hr = $vh_dcv_obj->get_domain_success_methods();

                    if ( !%$dcv_method_hr ) {

                        # This should never happen. Better to have an awkward,
                        # customer-visible warning than for a customer to have
                        # no idea why they don’t get a certificate.
                        die "ERROR: Neither an impediment nor DCV-succeeded domains … ???";
                    }

                    # NB: Even in the case of wildcard reduction, this contains
                    # the pre-reduction domains. It also contains any
                    # DCV-successful reducer wildcard domains.
                    my @dcv_ok_domains = keys %$dcv_method_hr;

                    my @succeeded_eligible = Cpanel::Set::intersection(
                        \@eligible_domains,
                        \@dcv_ok_domains,
                    );

                    # If the provider module can do its own DCV (e.g., Let’s Encrypt),
                    # then $dcv_method_hr is undef. But if the provider module can’t
                    # do its own DCV (e.g., Comodo/cPStore), then we have to give
                    # the domain DCV methods to the provider in renew_ssl().
                    if ( !$provider_obj->can('get_vhost_dcv_errors') ) {
                        @domain_dcv_method{@succeeded_eligible} = @{$dcv_method_hr}{@succeeded_eligible};
                    }

                    my @succeeded_reducer_wildcards = Cpanel::Set::difference(
                        \@dcv_ok_domains,
                        \@succeeded_eligible,
                    );

                    # This list informs the sort order of the eventual
                    # list of domains given to the CSR. We can’t sort that
                    # list directly because SORT_VHOST_FQDNS expects all
                    # domains given to it to exist on the vhost literally,
                    # and a wildcard-reduced list of domains will contain
                    # wildcard domains that aren’t on the vhost literally.
                    #
                    # NOTE: The default SORT_VHOST_FQDNS() logic will sort
                    # currently-secured domains before new ones. There’s
                    # no good reason for that here since the domains we have
                    # will *be* the new set of secured domains. It’s no big
                    # deal since the next time AutoSSL renews the certificate
                    # it will just give us the domains in the “true” order,
                    # but it’d be kinda nice if they sorted here the “right”
                    # way.
                    #
                    @succeeded_eligible = $provider_obj->SORT_VHOST_FQDNS( $username, @succeeded_eligible );

                    my @csr_domains = Cpanel::SSL::Auto::Wildcard::reduce_domains_by_wildcards(
                        \@succeeded_eligible,
                        @succeeded_reducer_wildcards,
                    );

                    if ( my $max_d = $provider_obj->MAX_DOMAINS_PER_CERTIFICATE() ) {
                        if ( my @removed = splice( @csr_domains, $max_d ) ) {
                            my $list_str = Cpanel::SSL::Auto::Run::Analyze::format_domain_list_for_log( \@removed, $username, $provider_obj );
                            $provider_obj->log( warn => locale()->maketext( '[numerate,_1,Domain,Domains] omitted because of the per-certificate domain limit: [_2]', 0 + @removed, $list_str ) );
                        }
                    }

                    push @new_certs, ( $dset_report->name() => \@csr_domains );

                    $provider_obj->log( info => locale()->maketext('[asis,AutoSSL] will request a new certificate.') );
                }
            },

            # Propagate this particular exception class.
            'Cpanel::Exception::AutoSSL::DeferFurtherWork' => sub { die },

            # Trap/warn everything else.
            q<> => sub { warn },
        );
    }

    return (
        {@new_certs},
        $provider_obj->can('get_vhost_dcv_errors') ? () : \%domain_dcv_method,
    );
}

=head2 I<OBJ>->determine_certs_and_renew_ssl( \@DOMAIN_SETS, $DCV_OBJ )

Handles all of AutoSSL for a user after local DCVs are done.

Arguments are:

=over

=item * a reference to L<Cpanel::SSL::Auto::Run::DomainSet> objects that each
represent a domain set that should ideally, for whatever reason, get a new
SSL certificate

=item * a L<Cpanel::SSL::Auto::Run::DCVResult> instance for the user’s local
DCV

=back

Nothing is returned.

This traps all errors except L<Cpanel::Exception::AutoSSL::DeferFurtherWork>
instances.

DCV

=cut

sub determine_certs_and_renew_ssl ( $self, $domain_sets_ar, $dcv_obj ) {    ## no critic qw(ManyArgs) - mis-parse
    my ( $username, $provider_obj ) = @{$self}{qw( username  provider_obj )};

    Cpanel::Try::try(
        sub {
            my ( $new_certs_hr, $domain_dcv_method_hr ) = $self->determine_new_certs_to_request( $domain_sets_ar, $dcv_obj );

            if (%$new_certs_hr) {
                my ( $single_names_ar, $vhost_names_ar ) = _split_domain_sets_by_type( $domain_sets_ar, $new_certs_hr );

                # Try to keep these on a single line so when a human
                # is scanning though the log it’s clear which statement
                # the names belong to :
                my @renew_cert_domain_by_domain_set = map { "($_: " . join( ' ', @{ $new_certs_hr->{$_} } ) . ")" } sort keys %$new_certs_hr;

                # The system will attempt to renew the SSL certificates for (bob.org: mail.bob.org frog.bob.org) and (frog.org: mail.frog.org cpanel.frog.org webmail.frog.org)
                $provider_obj->log( 'info', locale()->maketext( 'The system will attempt to renew the [asis,SSL] [numerate,_1,certificate,certificates] for [list_and,_2].', scalar @renew_cert_domain_by_domain_set, \@renew_cert_domain_by_domain_set ) );

                my @args_kv = (
                    username      => $username,
                    vhost_domains => {
                        %{$new_certs_hr}{@$vhost_names_ar},
                    },
                    single_domains => [
                        Cpanel::Set::intersection(
                            $single_names_ar,
                            [ keys %{$new_certs_hr} ],
                        ),
                    ],
                );

                if ($domain_dcv_method_hr) {
                    push @args_kv, dcv_method => $domain_dcv_method_hr;
                }

                $provider_obj->renew_ssl(@args_kv);
            }
        },

        # Propagate this particular exception class; catch everything else.
        'Cpanel::Exception::AutoSSL::DeferFurtherWork' => sub { die },

        q<> => sub {
            warn Cpanel::Exception::get_string($@);
        },
    );

    return;
}

sub _split_domain_sets_by_type ( $dset_objs, $cert_domains_hr ) {
    my @single_domain_sets;
    my @vhost_sets;

    for my $dset_obj (@$dset_objs) {
        my $setname = $dset_obj->name();

        next if !$cert_domains_hr->{$setname};

        my $ar;

        Cpanel::ClassDispatch::dispatch(
            $dset_obj,
            'Cpanel::SSL::Auto::Run::Vhost' => sub {
                $ar = \@vhost_sets;
            },
            'Cpanel::SSL::Auto::Run::DomainSet::DynamicDNS' => sub {
                $ar = \@single_domain_sets;
            },
        );

        push @$ar, $setname;
    }

    return ( \@single_domain_sets, \@vhost_sets );
}

1;
