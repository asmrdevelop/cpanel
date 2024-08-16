package Cpanel::SSL::Auto::Run::DomainSet;

# cpanel - Cpanel/SSL/Auto/Run/DomainSet.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::DomainSet

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This is a base class for groups of domains that AutoSSL processes.
See subclasses for specifics on each group type.

=head1 DOMAIN LIST RELATIONSHIPS

The following should clarify the terminology for different domain
list categories:

The C<user_excluded_domains> and C<provider_excluded_domains>
lists may or may not intersect. (They probably won’t since a
user doesn’t have much incentive to exclude domains that the
provider already excludes.)

C<secured_domains> and C<unsecured_domains>
will union together to form C<domains>.

C<unsecured_domains> includes C<missing_domains>.

C<domains> includes C<eligible_domains>.

C<eligible_domains> includes C<missing_domains>.

=head1 SUBCLASS INTERFACE

Subclasses B<MUST> define the following:

=over

=item * C<_get_certificate_object()>

=item * C<_determine_specific_tls_state()>

=item * C<_name()>

=item * C<_domains_ar()>

=item * C<_unsecured_domains_ar()>

=item * C<_can_wildcard_reduce()>

=back

Subclasses B<MAY> define the following:

=over

=item * C<_init()>

=item * C<_get_tls_state_details()>

=back

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::AttributeProvider',
);

use Cpanel::SSL::Auto::Exclude::Get ();
use Cpanel::SSL::Auto::Providers    ();
use Cpanel::Set                     ();
use Cpanel::Validate::Punycode      ();
use Cpanel::WildcardDomain::Tiny    ();

#----------------------------------------------------------------------

=head1 PROTECTED METHODS

=head2 $state = I<OBJ>->_Get_key_types()

Returns the user’s default key type, and the certificate’s key type.

A call to this function assumes that there B<IS> a certificate!

=cut

sub _Get_key_types ($self) {
    my $provider_obj = $self->get_provider_object();

    my $user_key_type = $provider_obj->get_user_default_key_type(
        $self->get_username(),
    );

    my $cert_key_type = $self->get_certificate_object()->key_type();

    my @ret = ( $user_key_type, $cert_key_type );

    local ( $@, $! );
    require Cpanel::SSL::KeyTypeLabel;
    $_ = Cpanel::SSL::KeyTypeLabel::to_label($_) for @ret;

    return @ret;
}

#----------------------------------------------------------------------

=head1 PUBLIC METHODS

=head2 $obj = I<CLASS>->new( $PROVIDER_OBJ, $USERNAME, \%DATA, @SUBCLASS_ARGS )

Instantiates this class.

$PROVIDER_OBJ is an instance of a subclass of
L<Cpanel::SSL::Auto::Provider>.

$USERNAME is a string.

\%DATA is defined by the subclass.

=cut

sub new ( $class, $provider_obj, $username, $data_hr, @args ) {    ## no critic qw(ManyArgs) - mis-parse
    die "$class is a base class!" if $class eq __PACKAGE__;

    my $self = $class->SUPER::new();
    @{$self}{ keys %$data_hr } = values %$data_hr;

    $self->{'provider_obj'} = $provider_obj;
    $self->{'username'}     = $username;

    $self->_init(@args);

    return $self;
}

sub _init ($self) { return }

#----------------------------------------------------------------------

=head2 I<OBJ>->can_wildcard_reduce()

Returns a boolean that indicates whether the domain set is
compatible with wildcard reduction.

=cut

sub can_wildcard_reduce {
    return $_[0]->_can_wildcard_reduce();
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_provider_object()

Returns the provider object given at instantiation.

=cut

sub get_provider_object {
    return $_[0]->{'provider_obj'};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_username()

Returns the username given at instantiation.

=cut

sub get_username {
    return $_[0]->{'username'};
}

#----------------------------------------------------------------------

=head2 I<OBJ>->certificate_is_in_renewal_period()

Returns a boolean that indicates whether I<OBJ>’s certificate
is in the provider’s renewal period.

=cut

sub certificate_is_in_renewal_period ($self) {

    return $self->_certificate_is_within_days_to_expiration(
        $self->{'provider_obj'}->DAYS_TO_REPLACE(),
    );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->certificate_is_in_notify_period()

Returns a boolean that indicates whether I<OBJ>’s certificate
is in the provider’s notify period.

=cut

sub certificate_is_in_notify_period ($self) {

    return

      (
        $self->_certificate_is_within_days_to_expiration(
            $self->{'provider_obj'}->DAYS_TO_NOTIFY(),
          )

          # If the certificate has been expired for longer
          # than DAYS_TO_NOTIFY_AFTER_EXPIRE
          # which is currently set to 7 days, we no longer
          # send notifications because they likely do not care,
          # and it’s just noise at this point.
          && !$self->_certificate_has_been_expired_for_days(
            $self->{'provider_obj'}->DAYS_TO_NOTIFY_AFTER_EXPIRE(),

          )

      );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->get_certificate_object()

Returns the instance of
L<Cpanel::SSL::Objects::Certificate> given at instantiation.

=cut

sub get_certificate_object {

    # Subclass must define
    return $_[0]->_get_certificate_object();
}

#----------------------------------------------------------------------

=head2 I<OBJ>->determine_tls_state()

Returns one of the following states, in order of severity precedence:

=over

=item C<defective> - The vhost’s SSL has at least one defect; i.e.,
there is either no SSL on the vhost, or whatever is there is broken
(e.g., weak key, expired, etc.).

=item C<default_key_mismatch> - The vhost’s SSL certificate uses
encryption that mismatches the user’s preference.

=item C<renewal> - The vhost’s certificate is in its renewal period,
but otherwise nothing is wrong.

=item C<incomplete> - The vhost’s certificate is not in its renewal period
nor otherwise problematic, but it doesn’t secure all of the vhost’s
eligible domains.

Note that this includes the case where the number of eligible domains
exceeds the provider’s per-certificate domain count limit; e.g., if
the provider only does up to 100 domains per cert and the vhost has 105
domains, this vhost will always be “incomplete” (if it’s not one of the
“worse” states above, that is).

=item C<ok> - The vhost’s certificate is not in its renewal period,
has no defects, secures all of the vhost’s eligible domains, and matches
the user’s key type preference. Life is awesome!

=back

Note that a C<defective> state could also have a certificate that’s
ready for renewal or lacking domain coverage; likewise, C<renewal> could
also have incomplete domain coverage. The returned state is a reflection
of how AutoSSL should treat this vhost’s TLS coverage, not a complete
list of conditions for every context.

=cut

sub determine_tls_state ($self) {
    return 'defective' if $self->get_defects();

    my @kt = $self->_Get_key_types();
    return 'default_key_mismatch' if $kt[0] ne $kt[1];

    return $self->_determine_non_defective_tls_state() || 'ok';
}

# default implementation
sub _determine_non_defective_tls_state { }

#----------------------------------------------------------------------

=head2 @conditions = I<OBJ>->get_defects()

Returns the vhost’s current SSL defects as human-readable strings.

=cut

sub get_defects ($self) {
    return $self->_get_defects();
}

#----------------------------------------------------------------------

=head2 @phrases = I<OBJ>->get_tls_state_details()

Returns a list of human-readable phrases to report as details
of the state reported by C<determine_tls_state()>.

=cut

sub get_tls_state_details ($self) {
    return $self->_get_tls_state_details();
}

sub _get_tls_state_details { return }

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->user_excluded_domains()

Returns all domains on the vhost that the user has excluded from AutoSSL.

=cut

#for tests
*_get_user_excluded_domains = *Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains;

my $excluded_cache_user;
my $excluded_cache_lookup_hr;

sub user_excluded_domains ($self) {

    $self->{'_user_excluded'} ||= do {
        if ( ( $excluded_cache_user || q<> ) ne $self->{'username'} ) {
            my @excluded = _get_user_excluded_domains( $self->{'username'} );

            my %excluded_lookup;
            @excluded_lookup{@excluded} = ();
            $excluded_cache_lookup_hr = \%excluded_lookup;

            $excluded_cache_user = $self->{'username'};
        }

        [ grep { exists $excluded_cache_lookup_hr->{$_} } @{ $self->_domains_ar() } ];
    };

    return @{ $self->{'_user_excluded'} };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->provider_excluded_domains()

Returns all domains on the vhost that the provider cannot secure.
Currently this means:

=over

=item * wildcard domains (if the provider lacks support for them)

=item * invalid punycode

=item * invalid C<*.arpa> domains (cf. L<Cpanel::Validate::Domain::ARPA>)

=back

=cut

sub provider_excluded_domains ($self) {

    my $provider_can_wildcard = $self->{'provider_obj'}->SUPPORTS_WILDCARD();

    #For now we don’t actually do anything with the provider
    #since we assume no providers support wildcard.

    $self->{'_provider_excluded'} ||= do {
        my @unsecurable;

        for my $domain ( @{ $self->_domains_ar() } ) {
            my $is_bad = !Cpanel::Validate::Punycode::is_valid($domain);

            if ( !$is_bad && !$provider_can_wildcard ) {
                $is_bad = Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain);
            }

            if ( !$is_bad && '.arpa' eq substr( $domain, -5 ) ) {
                require Cpanel::Validate::Domain::ARPA;
                $is_bad = !Cpanel::Validate::Domain::ARPA::is_valid($domain);
            }

            push @unsecurable, $domain if $is_bad;
        }

        \@unsecurable;
    };

    return @{ $self->{'_provider_excluded'} };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->eligible_domains()

Returns C<vhost_domains()> minus the user and provider exclusions.
This doesn’t sort the domains.

In scalar context this returns a count of eligible domains.

=cut

sub eligible_domains ($self) {

    $self->{'_eligible'} ||= [
        Cpanel::Set::difference(
            $self->_domains_ar(),
            [ $self->user_excluded_domains() ],
            [ $self->provider_excluded_domains() ],
        ),
    ];

    return @{ $self->{'_eligible'} };
}

#----------------------------------------------------------------------

=head2 I<OBJ>->certificate_is_externally_signed()

Indicates whether the vhost has a certificate installed that is neither
a recognized AutoSSL certificate nor self-signed. Unless
C<clobber_externally_signed> is enabled, this should block AutoSSL from
any action on the vhost.

Note that this will return truthy for “testing” certificates—i.e.,
certificates that are signed by an intermediate that doesn’t connect
back to a trusted root certificate. (Such certificates will still show
as having failed verification.)

=cut

sub certificate_is_externally_signed ($self) {
    my $cert = $self->_get_certificate_object();

    return 0 if !$cert;

    return 0 if $cert->is_self_signed();

    $self->{'is_autossl'} //= do {
        my $installed_autossl_providers = Cpanel::SSL::Auto::Providers->new();
        !!$installed_autossl_providers->get_provider_object_for_certificate_object($cert);
    };

    return !$self->{'is_autossl'} ? 1 : 0;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->certificate_is_maximum_size()

Indicates whether the vhost’s current certificate has at least the maximum
number of domains that the AutoSSL provider allows—i.e., whether the
AutoSSL provider is unable to issue a certificate that includes more domains.

=cut

sub certificate_is_maximum_size ($self) {

    my $max_domains = $self->{'provider_obj'}->MAX_DOMAINS_PER_CERTIFICATE();
    return 0 if !$max_domains;

    my $domains_ar = $self->_get_certificate_object()->domains();

    return @$domains_ar >= $max_domains;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->certificate_expiry_time()

Returns a UNIX timestamp if there is a certificate installed,
or undef otherwise.

=cut

sub certificate_expiry_time ($self) {
    my $cert = $self->_get_certificate_object();

    return $cert && ( 1 + $cert->not_after() );
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->unsecured_domains()

All C<domains()> members that lack TLS coverage.

Note that this includes domains that the provider and/or the user
have excluded from coverage.

=cut

sub unsecured_domains ($self) {

    return @{ $self->_unsecured_domains_ar() };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->domains()

Returns the full set of domains in I<OBJ>.

=cut

sub domains ($self) {
    return @{ $self->_domains_ar() };
}

#----------------------------------------------------------------------

=head2 $name = I<OBJ>->name()

Returns the domain set’s name. (As of September 2020 that’s one of the
domains in the set.)

=cut

sub name ($self) {
    return $self->_name();
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->secured_domains()

Note that this includes domains that the provider and/or the user
have excluded from coverage.

=cut

sub secured_domains ($self) {

    $self->{'_secured_domains'} ||= [
        Cpanel::Set::difference(
            $self->_domains_ar(),
            $self->_unsecured_domains_ar(),
        ),
    ];

    return @{ $self->{'_secured_domains'} };
}

#----------------------------------------------------------------------

=head2 @domains = I<OBJ>->missing_domains()

Eligible-but-unsecured domains. This does not take into account
the number of secured domains and whether the provider can accommodate
all of the eligible domains; that requires a DCV result to compute.

=cut

sub missing_domains ($self) {

    $self->{'_missing'} ||= [
        Cpanel::Set::intersection(
            $self->_unsecured_domains_ar(),
            [ $self->eligible_domains() ],
        ),
    ];

    return @{ $self->{'_missing'} };
}

#----------------------------------------------------------------------

sub _time { return time; }

sub _certificate_is_within_days_to_expiration ( $self, $days_to_replace ) {

    #sanity check
    $self->_verify_has_certificate();

    #A provider can set DAYS_TO_REPLACE() to a falsey value to forgo
    #certificate replacement until the certificate is at critical.
    return if !$days_to_replace;

    my $secs_to_replace = 86400 * $days_to_replace;

    return $self->_get_certificate_object()->is_expired_at( _time() + $secs_to_replace );
}

sub _certificate_has_been_expired_for_days ( $self, $days_expired ) {

    #sanity check
    $self->_verify_has_certificate();

    my $seconds_expired = 86400 * $days_expired;
    my $expiry_time     = $self->certificate_expiry_time();

    return $expiry_time + $seconds_expired <= _time;
}

sub _verify_has_certificate ($self) {

    die 'no certificate!' if !$self->_get_certificate_object();

    return;
}

1;
