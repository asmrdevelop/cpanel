package Cpanel::Security::Authn::TwoFactorAuth::Base;

# cpanel - Cpanel/Security/Authn/TwoFactorAuth/Base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Try::Tiny;

use Cpanel::Exception    ();
use Cpanel::Encoder::URI ();

sub new {
    my ( $class, $args_hr ) = @_;
    die "Invalid arguments provided. Arguments must be specified as a HashRef.\n" if !( $args_hr && ref $args_hr eq 'HASH' );

    my $self = bless {}, $class;
    $self->_check_required_args_or_die($args_hr);
    $self->{'issuer'}       = $args_hr->{'issuer'};
    $self->{'secret'}       = $args_hr->{'secret'};
    $self->{'account_name'} = $args_hr->{'account_name'};
    return $self;
}

sub secret       { return shift->{'secret'}; }
sub issuer       { return shift->{'issuer'}; }
sub account_name { return shift->{'account_name'}; }

sub otpauth_str {
    my $self = shift;
    return 'otpauth://totp/' . Cpanel::Encoder::URI::uri_encode_str( $self->issuer() ) . ':' . Cpanel::Encoder::URI::uri_encode_str( $self->account_name() ) . '?secret=' . $self->secret() . '&issuer=' . Cpanel::Encoder::URI::uri_encode_str( $self->issuer() );
}

sub verify_token {
    my ( $self, $token ) = @_;
    $token //= '';

    # The token is valid if it is generated within:
    #  - the 'current' time slice (time)
    #  - the 'next' time slice (time + 30)
    #  - or the 'previous' time slice (time - 30)
    #
    # Any time skew worse than this will require
    # the sysadmins to sync the system clock.
    #
    # The license system currently allows for "a minute or two" of skew,
    # so we are accomadating such a skew, by accepting tokens generated within a 90 second window.
    return 1 if ( $self->generate_code() eq $token ) || ( $self->generate_code( time + 30 ) eq $token ) || ( $self->generate_code( time - 30 ) eq $token );
    return;
}

sub _check_required_args_or_die {
    my ( $self, $args ) = @_;
    my @required_keys = qw(issuer account_name secret);

    my @missing_or_invalid;
    foreach my $key (@required_keys) {
        my $validator = $self->can( '_validate_' . $key );
        if ( !exists $args->{$key} || ( ref $validator eq 'CODE' && !$validator->( $args->{$key} ) ) ) {
            push @missing_or_invalid, $key;
        }
    }

    die Cpanel::Exception->create( 'Missing or Invalid: [list_and_quoted,_1]', [ \@missing_or_invalid ] ) if @missing_or_invalid;
    return 1;
}

1;
