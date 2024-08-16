package Cpanel::Config::userdata::TwoFactorAuth::Secrets;

# cpanel - Cpanel/Config/userdata/TwoFactorAuth/Secrets.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base qw(Cpanel::Config::userdata::TwoFactorAuth::Base);

use Cpanel::Exception                              ();
use Cpanel::Security::Authn::TwoFactorAuth::Google ();

sub DATA_FILE {
    my $self = shift;
    return $self->base_dir() . '/tfa_userdata.json';
}

sub configure_tfa_for_user {
    my ( $self, $user_config_hr ) = @_;
    return if $self->{'_read_only'};

    if ( !$user_config_hr || 'HASH' ne ref $user_config_hr ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] containing details for two-factor authentication' );
    }
    my $username = delete $user_config_hr->{'username'} || die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['username'] );

    $user_config_hr = _sanitize_user_config($user_config_hr);

    my $userdata = $self->read_userdata();
    $userdata->{$username} = $user_config_hr;
    $self->{'_transaction_obj'}->set_data($userdata);

    return wantarray ? ( $username, $user_config_hr ) : 1;
}

sub remove_tfa_for_user {
    my ( $self, $username ) = @_;
    return if $self->{'_read_only'};

    my $userdata = $self->read_userdata();
    delete $userdata->{$username};

    $self->{'_transaction_obj'}->set_data($userdata);

    return 1;
}

sub _sanitize_user_config {
    my $user_config_hr = shift;

    my ( @err_collection, $sanitized_user_config );
    my %required_keys = map { $_ => 1 } (qw(secret));

    foreach my $required_key ( keys %required_keys ) {
        push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_key] ) if not exists $user_config_hr->{$required_key};
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;

    my $validation_tests = {
        'secret' => \&Cpanel::Security::Authn::TwoFactorAuth::Google::_validate_secret,
    };

    foreach my $key ( sort keys %{$user_config_hr} ) {
        if ( exists $validation_tests->{$key} && !$validation_tests->{$key}->( $user_config_hr->{$key} ) ) {
            push @err_collection, Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” specified is not valid: [_2]', [ $key, $user_config_hr->{$key} ] );
        }
        elsif ( exists $required_keys{$key} ) {
            $sanitized_user_config->{$key} = $user_config_hr->{$key};
        }
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;

    return $sanitized_user_config;
}

1;
