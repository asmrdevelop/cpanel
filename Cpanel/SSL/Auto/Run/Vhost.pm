package Cpanel::SSL::Auto::Run::Vhost;

# cpanel - Cpanel/SSL/Auto/Run/Vhost.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Run::Vhost

=head1 SYNOPSIS

    my $vhost_state = Cpanel::SSL::Auto::Run::Vhost->new(
        $provider_instance,
        $username,
        $vhost_check_hr,
    );

=head1 DESCRIPTION

This class decorates a vhost’s result from L<Cpanel::SSL::VhostCheck>
with methods that analyze that vhost’s status as regards AutoSSL.

It subclasses L<Cpanel::SSL::Auto::Run::DomainSet>.

B<NOTE:> All list methods of this class will, if called in scalar context,
return the number of items that would be returned in list context.

=cut

use parent (
    'Cpanel::SSL::Auto::Run::DomainSet',
);

use Cpanel::Imports;

# TODO: Find out what is creating the dupes in /var/cpanel/userdata files,
# fix it, then remove this code. (cf. CPANEL-20665)
use Cpanel::ArrayFunc::Uniq ();

# Sibling classes (e.g., DynamicDNS.pm) may set a different value:
use constant _can_wildcard_reduce => 1;

#----------------------------------------------------------------------

=head1 CONSTRUCTOR ARGUMENTS

The C<\%DATA> given to C<new()> B<MUST> be a reference to one of the
hashes returned from L<Cpanel::SSL::VhostCheck>.

The C<@SUBCLASS_ARGS> given to C<new()> are:

=over

=item * $USER_ZONES_HR - a hashref with the keys being
all of the zones the user owns. The values are all
undef.  Currently the only caller uses
C<Cpanel::SSL::Auto::Run::Analyze::_get_user_zones_hr()>
to generate this hashref.

=back

=cut

sub _init ( $self, $user_zones_hr ) {

    # For some time there was a bug where cP’s Apache configuration
    # distiller would put service subdomains into the web vhost config
    # (“userdata”) files. That should be auto-fixed soon enough, but just
    # in case it perdures, we accommodate it here silently.
    for my $key (qw( domains  unsecured_domains )) {
        my @uniq = Cpanel::ArrayFunc::Uniq::uniq( @{ $self->{$key} } );

        if ( @uniq != @{ $self->{$key} } ) {
            @{ $self->{$key} } = @uniq;
        }

        # NB: If we ever start to care about NOT_ALL_DOMAINS problems
        # in this module then we’ll need logic to prune NOT_ALL_DOMAINS
        # after this loop whenever `unsecured_domains` is empty. (Since
        # it’s possible that the only unsecured domains are unowned.)
        $self->{$key} = _log_and_filter_unowned_domains(
            $self->get_username(),
            $self->get_provider_object(),
            $self->{$key},
            $user_zones_hr
        );
    }

    return;
}

# This identifies all domains among @$domains_ar that the indicated user
# owns, and returns an array reference of those domains. This will log
# an error on the given $provider_obj (i.e., instance of a subclass of
# L<Cpanel::SSL::Auto::Provider>) for each unowned domain.
#
# This is here to accommodate cases where, for whatever reason, a domain
# exists in a vhost’s config file that doesn’t exist in the uesr’s main
# vhosts config file.
#
# NB: Tested directly.
sub _log_and_filter_unowned_domains {
    my ( $username, $provider_obj, $domains_ar, $user_zones_hr ) = @_;

    my @owned_domains;

    foreach my $domain (@$domains_ar) {
        if ( _domain_is_controlled_by_users_zones( $domain, $user_zones_hr ) ) {
            push @owned_domains, $domain;
        }
        else {
            my $why_failed = locale()->maketext( '“[_1]” does not control [asis,DNS] for the “[_2]” domain.', $username, $domain );
            $provider_obj->log( 'error', $why_failed );
        }
    }

    return \@owned_domains;
}

# This is more or less a duplication of
# Cpanel::DnsUtils::Name::get_longest_short_match(). On users with
# thousands of domains it can make a second or so of difference.
sub _domain_is_controlled_by_users_zones {
    my ( $domain, $user_zones_hr ) = @_;

    # There is a zone for the domain
    return 1 if $user_zones_hr->{$domain};
    my @pieces = split m<\.>, $domain;

    # Domain is a TLD (this should never happen)
    return 0 if scalar @pieces == 1;

    # Check to see if the domain is a subdomain of a user controlled zone
    for my $n ( 1 .. $#pieces ) {
        return 1 if ( exists $user_zones_hr->{ join( '.', @pieces[ ( $#pieces - $n ) .. $#pieces ] ) } );
    }
    return 0;
}

sub _get_certificate_object {
    return $_[0]->{'certificate'};
}

sub _determine_non_defective_tls_state ($self) {

    return 'renewal' if $self->certificate_is_in_renewal_period();

    return 'incomplete' if $self->missing_domains();

    return;
}

sub _get_tls_state_details ($self) {
    my @details;

    if ( $self->determine_tls_state() eq 'default_key_mismatch' ) {
        my ( $key_type, $cert_key_type ) = $self->_Get_key_types();

        @details = (
            locale()->maketext( 'Default Key Type: [_1]',       $key_type ),
            locale()->maketext( 'Certificate’s Key Type: [_1]', $cert_key_type ),
        );
    }

    return @details;
}

sub _name {
    my ($self) = @_;

    return $self->{'vhost_name'};
}

sub _domains_ar ($self) {
    return $self->{'domains'};
}

sub _unsecured_domains_ar ($self) {
    return $self->{'unsecured_domains'};
}

#----------------------------------------------------------------------

my %_IS_NONFATAL_PROBLEM = (
    NOT_ALL_DOMAINS => 1,
);

sub _get_defects {
    my ($self) = @_;

    $self->{'_defects'} ||= do {
        my @defects;

        for my $problem ( @{ $self->{'problems'} } ) {
            next if $_IS_NONFATAL_PROBLEM{$problem};

            my $problem_method = "_phrase_for_$problem";

            my $explanation;

            if ( $self->can($problem_method) ) {
                $explanation = $self->$problem_method();
            }
            else {
                my ( $base_problem, $problem_detail ) = split m<:>, $problem, 2;
                my $problem_method = "_phrase_for_$base_problem";

                if ( $self->can($problem_method) ) {
                    $explanation = $self->$problem_method($problem_detail);
                    $problem     = $base_problem;
                }
            }

            if ($explanation) {
                push @defects, "$problem: $explanation";
            }
            else {
                push @defects, $problem;
            }
        }

        \@defects;
    };

    return @{ $self->{'_defects'} };
}

#----------------------------------------------------------------------

sub _limit_domain_list_for_provider_max_domains {
    my ( $self, $domains_ar, $limit ) = @_;

    my $provider_obj = $self->{'provider_obj'};

    @$domains_ar = $provider_obj->SORT_VHOST_FQDNS( $self->{'username'}, @$domains_ar );

    splice( @$domains_ar, $limit );

    return;
}

sub _phrase_for_NO_SSL {
    my ($self) = @_;

    return locale()->maketext('No [asis,SSL] certificate is installed.');
}

sub _phrase_for_ALMOST_EXPIRED {
    my ($self) = @_;

    return locale()->maketext('The certificate will expire very soon.');
}

sub _phrase_for_CA_CERTIFICATE_ALMOST_EXPIRED {

    return locale()->maketext('The certificate’s chain of trust will expire very soon.');
}

sub _phrase_for_WEAK_KEY {
    my ($self) = @_;

    return locale()->maketext('The certificate’s key is too weak to provide adequate encryption.');
}

sub _phrase_for_WEAK_SIGNATURE {
    my ($self) = @_;

    return locale()->maketext('The certificate’s signature is too weak to provide adequate security.');
}

sub _phrase_for_OCSP_REVOKED {
    my ($self) = @_;

    return locale()->maketext('[output,abbr,OCSP,Online Certificate Status Protocol] indicates that this website’s certificate is revoked.');
}

sub _phrase_for_INVALID_CERTIFICATE {
    my ( $self, $problem_path ) = @_;

    return locale()->maketext( 'The certificate file ([_1]) is corrupted.', $problem_path );
}

sub _phrase_for_MISSING_CERTIFICATE {
    my ( $self, $problem_path ) = @_;

    return locale()->maketext( 'The certificate does not exist at the expected filesystem path ([_1]).', $problem_path );
}

sub _phrase_for_EMPTY_CERTIFICATE {
    my ( $self, $problem_path ) = @_;

    return locale()->maketext( 'The certificate file ([_1]) is empty. This may indicate filesystem corruption.', $problem_path );
}

sub _phrase_for_OPENSSL_VERIFY {
    my ( $self, $problem_detail ) = @_;

    return locale()->maketext( 'The certificate chain failed [asis,OpenSSL]’s verification ([_1]).', $problem_detail );
}

1;
