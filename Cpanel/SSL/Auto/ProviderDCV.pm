package Cpanel::SSL::Auto::ProviderDCV;

# cpanel - Cpanel/SSL/Auto/ProviderDCV.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::ProviderDCV

=head1 DESCRIPTION

This class represents a vhost’s DCV as it goes through an AutoSSL
provider’s C<get_vhost_dcv_errors()> function. That function should have
minimal need (ideally none) to interact with the provider module other
than via this object.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Context ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $PROVIDER_OBJ, $USERNAME, \%DOMAIN_DCV_METHOD, \@SORTED_DOMAINS )

Instantiates this class.

$PROVIDER_OBJ is an instance of a
L<Cpanel::SSL::Auto::Provider> subclass.

$USERNAME is the name of the user who owns the domains in question.

%DOMAIN_DCV_METHOD is ( DOMAIN => DCV_METHOD ), where
DCV_METHOD is either C<http> or C<dns>.

@SORTED_DOMAINS are the keys to %DOMAIN_DCV_METHOD in the order
that they should appear on the certificate. This is necessary
as of v88 because the introduction of wildcard reduction means
not every domain in %DOMAIN_DCV_METHOD is necessarily one of the
vhost’s domains. (i.e., it could be a wildcard substitution for
1+ of the vhost’s domains.)

=cut

sub new ( $class, $provider_obj, $username, $domain_dcv_hr, $sorted_domains_ar ) {    ## no critic qw(ManyArgs)

    my %self = (
        _provider       => $provider_obj,
        _username       => $username,
        _domain_dcv     => $domain_dcv_hr,
        _sorted_domains => $sorted_domains_ar,
    );

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 $username = I<OBJ>->get_username()

Returns the username given to the constructor.

=cut

sub get_username ($self) {
    return $self->{'_username'};
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->get_sorted_domains()

Returns the sorted domains as given to C<new()>.

=cut

sub get_sorted_domains ($self) {
    Cpanel::Context::must_be_list();

    return @{ $self->{'_sorted_domains'} };
}

#----------------------------------------------------------------------

=head2 $method = I<OBJ>->get_dcv_method_or_die( $DOMAIN )

Returns $DOMAIN’s indicated DCV method: either C<http> or C<dns>.
Throws an exception if there is none.

=cut

sub get_dcv_method_or_die ( $self, $domain ) {
    return $self->{'_domain_dcv'}{$domain} || die "$self: No DCV method for “$domain”!";
}

#----------------------------------------------------------------------

=head2 $method = I<OBJ>->get_domain_success_method( $DOMAIN )

Returns either undef (i.e., no DCV succeeded), C<http>, or C<dns>.

=cut

sub get_domain_success_method ( $self, $domain ) {
    return $self->{'_domain_ok'}{$domain};
}

#----------------------------------------------------------------------

=head2 $failures_ar = I<OBJ>->get_domain_failures( $DOMAIN )

If $DOMAIN has any registered failures, returns an array reference
of $DOMAIN’s DCV failures, in chronological order.

If $DOMAIN has no registered failures, returns undef.

=cut

sub get_domain_failures ( $self, $domain ) {
    return $self->{'_domain_error'}{$domain};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_http_success( $DOMAIN )

Registers a domain that passed DCV via HTTP and thus may be included
in a certificate request to the provider.

=cut

sub add_http_success ( $self, $domain ) {
    $self->{'_domain_ok'}{$domain} = 'http';

    $self->{'_provider'}->log(
        'success',
        locale()->maketext( '“[_1]” [asis,HTTP] [asis,DCV] OK: [_2]', $self->{'_provider'}->DISPLAY_NAME(), $domain ),
    );

    # In case this is ever, for whatever reason, done where
    # DNS fails then HTTP succeeds.
    $self->_clear_error($domain);

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_dns_success( $DOMAIN )

Like C<add_http_success()> but for DNS rather than HTTP.

=cut

sub add_dns_success ( $self, $domain ) {
    $self->{'_domain_ok'}{$domain} = 'dns';

    $self->{'_provider'}->log(
        'success',
        locale()->maketext( '“[_1]” [asis,DNS] [asis,DCV] OK: [_2]', $self->{'_provider'}->DISPLAY_NAME(), $domain ),
    );

    $self->_clear_error($domain);

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_general_success( $DOMAIN )

Like C<add_http_success()> but for a case where the DCV method is unknown.

=cut

sub add_general_success ( $self, $domain ) {
    $self->{'_domain_ok'}{$domain} = 'master';

    $self->{'_provider'}->log(
        'success',
        locale()->maketext( '“[_1]” [asis,DCV] OK: [_2]', $self->{'_provider'}->DISPLAY_NAME(), $domain ),
    );

    # In case this is ever, for whatever reason, done where
    # DNS fails then HTTP succeeds.
    $self->_clear_error($domain);

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_http_warning( $DOMAIN, $MESSAGE )

Indicates an HTTP DCV failure, but one that does B<NOT> indicate
a final DCV failure.

=cut

sub add_http_warning ( $self, $domain, $message ) {
    $self->{'_provider'}->log(
        'warn',
        locale()->maketext( '“[_1]” [asis,HTTP] [asis,DCV] error ([_2]): [_3]', $self->{'_provider'}->DISPLAY_NAME(), $domain, $message ),
    );

    push @{ $self->{'_domain_error'}{$domain} }, $message;

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_dns_failure( $DOMAIN, $MESSAGE )

Indicates a DNS DCV failure. Unlike C<add_http_failure_warning()>,
this failure is understood to mean a final DCV failure.

=cut

sub add_dns_failure ( $self, $domain, $message ) {
    $self->{'_provider'}->log(
        'error',
        locale()->maketext( '“[_1]” [asis,DNS] [asis,DCV] error ([_2]): [_3]', $self->{'_provider'}->DISPLAY_NAME(), $domain, $message ),
    );

    push @{ $self->{'_domain_error'}{$domain} }, $message;

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->add_general_failure( $DOMAIN, $MESSAGE )

Indicates a general (final) domain failure.

=cut

sub add_general_failure ( $self, $domain, $message ) {
    $self->{'_provider'}->log(
        'error',
        locale()->maketext( '“[_1]” general error ([_2]): [_3]', $self->{'_provider'}->DISPLAY_NAME(), $domain, $message ),
    );

    push @{ $self->{'_domain_error'}{$domain} }, $message;

    return $self;
}

#----------------------------------------------------------------------

sub _clear_error ( $self, $domain ) {
    $self->{'_domain_error'}{$domain} = undef;

    return;
}

1;
