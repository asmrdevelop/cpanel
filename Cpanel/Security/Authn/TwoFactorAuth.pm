package Cpanel::Security::Authn::TwoFactorAuth;

# cpanel - Cpanel/Security/Authn/TwoFactorAuth.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Security::Authn::TwoFactorAuth::Google   ();
use Cpanel::Config::userdata::TwoFactorAuth::Secrets ();
use Cpanel::Config::userdata::TwoFactorAuth::Issuers ();
use Cpanel::Security::Authn::TwoFactorAuth::Enabled  ();

*is_enabled = \&Cpanel::Security::Authn::TwoFactorAuth::Enabled::is_enabled;

sub new {
    my ( $class, $args_hr ) = @_;
    die "Invalid arguments provided. Arguments must be specified as a HashRef.\n" if !( $args_hr && ref $args_hr eq 'HASH' );

    my $self = bless {}, $class;
    $self->_check_required_args_or_die($args_hr);
    $self->{'user'}           = $args_hr->{'user'};
    $self->{'token_verifier'} = undef;
    return $self;
}

sub user { return shift->{'user'}; }

sub token_verifier {
    my $self = shift;

    $self->{'token_verifier'} //= $self->_build_token_verifier();
    return $self->{'token_verifier'};
}

sub is_tfa_configured {
    my $self = shift;
    return 1 if $self->token_verifier();
    return;
}

sub verify_token {
    my ( $self, $token ) = @_;

    # If the user doesn't have TFA configured, then
    # then verification is not needed, so we'll just
    # pass all of those calls.
    return 1 if not $self->is_tfa_configured();

    return $self->token_verifier()->verify_token($token);
}

# Removes the 'secret', and the 'issuer' userdata.
sub remove_tfa_userdata {
    my $self            = shift;
    my $secret_userdata = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new();
    $secret_userdata->remove_tfa_for_user( $self->{'user'} );
    $secret_userdata->save_changes_to_disk();

    my $issuer_userdata = Cpanel::Config::userdata::TwoFactorAuth::Issuers->new();
    $issuer_userdata->set_issuer( $self->{'user'}, undef );
    $issuer_userdata->save_changes_to_disk();

    return 1;
}

sub _build_token_verifier {
    my $self            = shift;
    my $user_tfa_config = _load_user_tfa_config( $self->user() ) || {};
    if ( scalar keys %{$user_tfa_config} ) {
        return Cpanel::Security::Authn::TwoFactorAuth::Google->new($user_tfa_config);
    }

    return;
}

sub _load_user_tfa_config {
    my $user = shift;

    my $userdata = Cpanel::Config::userdata::TwoFactorAuth::Secrets->new( { 'read_only' => 1 } );
    if ( my $tfa_config = $userdata->read_userdata()->{$user} ) {
        return {
            %{$tfa_config},

            # We don't really use the 'issuer' setting here.
            # We create the 'token verifier' just to verify
            # the token, so setting the 'issuer' here to a
            # placeholder instead of the 'real' value, saves us
            # from having to look it up in the 'issuer userdata'.
            'issuer'       => 'n/a',
            'account_name' => $user,
        };
    }
    return;
}

sub _check_required_args_or_die {
    my ( $self, $args ) = @_;
    my @required_keys = qw(user);

    my @missing_or_invalid;
    foreach my $key (@required_keys) {
        my $validator = $self->can( '_validate_' . $key );

        # TODO: validate user specified and make sure its a real system user.
        if ( !exists $args->{$key} || ( ref $validator eq 'CODE' && !$validator->( $args->{$key} ) ) ) {
            push @missing_or_invalid, $key;
        }
    }

    die 'Missing or Invalid: [ ' . join( ',', @missing_or_invalid ) . ' ]' if @missing_or_invalid;
    return 1;
}

1;
