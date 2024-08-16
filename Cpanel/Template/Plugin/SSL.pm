package Cpanel::Template::Plugin::SSL;

# cpanel - Cpanel/Template/Plugin/SSL.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::SSL - Template Toolkit Plugin for SSL

=head1 SYNOPSIS

    USE SSL;
    SSL.function();

=head1 DESCRIPTION

Template Toolkit Plugin for SSL related functions

=cut

use cPstrict;

use parent 'Template::Plugin';

use Cpanel::SSL::Utils  ();
use Cpanel::GlobalCache ();
use Cpanel::WebVhosts   ();

my $cached_installable_ssl_names;

sub DEFAULT_KEY_SIZE {
    eval 'require Cpanel::RSA' if !$INC{'Cpanel/RSA.pm'};
    return $Cpanel::RSA::DEFAULT_KEY_SIZE;
}

#See Cpanel::SSL::Utils for this function's interface.
sub validate_certificate_for_domain {
    my ( $plugin, $cert, $domain ) = @_;

    return [ Cpanel::SSL::Utils::validate_certificate_for_domain( $cert, $domain ) ];
}

sub validate_domains_lists_have_match {
    shift;    # $plugin
    goto \&Cpanel::SSL::Utils::validate_domains_lists_have_match;
}

#Pass in an array of domains to see if any of them corresponds with one of the
#names that can be used for an ssl install for $Cpanel::user
#Returns an arrayref of either:
#   [ 0, $error ], or
#   [ 1, $does_it_match_boolean ]
#NOTE: If no SSL is installable, we always return true.
sub match_domains_array_against_ssl_install {
    my ( $plugin, $domains_ar ) = @_;

    die 'Must be called from a UAPI-aware context!' if !$INC{'Cpanel/API.pm'};

    if ( !$cached_installable_ssl_names ) {
        $cached_installable_ssl_names = [ map { $_->{'domain'} } Cpanel::WebVhosts::list_ssl_capable_domains($Cpanel::user) ];
    }

    return [ 1, 1 ] if !@$cached_installable_ssl_names;

    my $match = Cpanel::SSL::Utils::validate_domains_lists_have_match( $domains_ar, $cached_installable_ssl_names );

    return [ 1, $match ];
}

#for testing
sub _reset_cached_installed_ssl_names {
    $cached_installable_ssl_names = undef;
    return;
}

=head2 autossl_supports_wildcard

Get whether the current autossl provider supports wildcard

=over 2

=item Output

=over 3

=item C<SCALAR>

    returns boolean value for whether or not this is supported.

=back

=back

=cut

sub autossl_supports_wildcard {
    my ($plugin) = @_;
    my $provider = $plugin->get_autossl_provider();
    if ($provider) {
        require Cpanel::SSL::Auto::Loader;
        my $perl_ns = Cpanel::SSL::Auto::Loader::get_and_load($provider);
        return $perl_ns->SUPPORTS_WILDCARD();
    }
    return;
}

=head2 autossl_override_enabled

Thin wrapper for Cpanel::SSL::Auto::Config metadata for clobber_externally_signed

=over 2

=item Output

=over 3

=item C<SCALAR>

    returns boolean value for whether or not this is enabled.

=back

=back

=cut

sub autossl_override_enabled {
    return Cpanel::GlobalCache::data( 'cpanel', 'autossl_clobber_externally_signed' );
}

=head2 get_autossl_provider

Thin wrapper for Cpanel::SSL::Auto::Config method for clobbering external certs

=over 2

=item Output

=over 3

=item C<SCALAR>

    returns string name of current Cpanel AutoSSL provider, or undef

=back

=back

=cut

sub get_autossl_provider {
    return Cpanel::GlobalCache::data( 'cpanel', 'autossl_current_provider_name' );
}

#----------------------------------------------------------------------

=head2 key_types_and_labels()

Returns an array reference of hash references, each of which
has a C<type> and a C<label>.

Example:

    [
        { type => 'rsa-2048', label => 'RSA, 2048-bit' },
        # ..
    ]

=cut

sub key_types_and_labels {
    my @opts_labels = _opts_labels();

    my @grouped;

    while ( my ( $type, $label ) = splice( @opts_labels, 0, 2 ) ) {
        push @grouped, { type => $type, label => $label };
    }

    return \@grouped;
}

=head2 default_key_type()

Returns the current user’s preferred SSL key type, as given by
L<Cpanel::SSL::DefaultKey::User>.

=cut

sub default_key_type {
    require Cpanel::SSL::DefaultKey::User;
    return Cpanel::SSL::DefaultKey::User::get( $ENV{'TEAM_USER'} ? $ENV{'TEAM_OWNER'} : $ENV{'REMOTE_USER'} );
}

=head2 translate_key_parts_to_label()

Returns SSL key type label based on the algorithm type:

Examples:

=over

=item * RSA, 2,048-bit

    SSL.translate_key_parts_to_label({ key_algorithm => 'rsaEncryption', modulus_length => '2048' })

=item * ECDSA, P-256 (prime256v1)

    SSL.translate_key_parts_to_label({ key_algorithm => 'id-ecPublicKey', ecdsa_curve_name => 'prime256v1' })

=back

=cut

sub translate_key_parts_to_label {
    my ( $self, $key_hash ) = @_;

    require Cpanel::SSL::KeyTypeLabel;
    require Cpanel::Crypt::Algorithm;
    return Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $key_hash,
        rsa => sub {
            my $key_hash = shift;
            return Cpanel::SSL::KeyTypeLabel::to_label( "RSA-" . $key_hash->{modulus_length} );
        },
        ecdsa => sub {
            my $key_hash = shift;
            return Cpanel::SSL::KeyTypeLabel::to_label( "ECDSA-" . $key_hash->{ecdsa_curve_name} );
        },
    );
}

=head2 key_type_descriptions()

Returns the key type descriptions, as given by
L<Cpanel::SSL::DefaultKey::Constants>.

=cut

sub key_type_descriptions {
    require Cpanel::SSL::DefaultKey::Constants;
    return Cpanel::SSL::DefaultKey::Constants::KEY_DESCRIPTIONS();
}

=head2 key_type_system()

Returns the key type setting that indicates for a user to use
the system’s own default key type.

=cut

sub key_type_system {
    require Cpanel::SSL::DefaultKey::Constants;
    return Cpanel::SSL::DefaultKey::Constants::USER_SYSTEM();
}

=head2 $txt = get_key_type_label($KEYTYPE)

Returns the text that should be used for $KEYTYPE in the UI.

=cut

sub get_key_type_label ( $, $keytype ) {
    my %type_label = _opts_labels();

    return $type_label{$keytype} || die "No label for type $keytype";
}

sub _opts_labels () {
    require Cpanel::SSL::DefaultKey::Constants;
    return Cpanel::SSL::DefaultKey::Constants::OPTIONS_AND_LABELS();
}

1;
