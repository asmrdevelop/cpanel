package Cpanel::RemoteAPI::Base;

# cpanel - Cpanel/RemoteAPI/Base.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::Base

=head1 DESCRIPTION

This is a base class for classes that implement remote API access.

=cut

#----------------------------------------------------------------------

use Cpanel::Set ();

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->new_from_password( $HOSTNAME, $USERNAME, $PASSWORD, %EXTRA_OPTS )

Instantiates an API session object to authenticate via username and
password.

=cut

sub new_from_password ( $class, $hostname, $username, $password, %opts ) {
    $class->_validate_opts( \%opts );

    my %api_args = (
        host => $hostname,
        user => $username,
        pass => $password,
        %opts,
    );

    return bless { _api_args => \%api_args }, $class;
}

=head2 I<CLASS>->new_from_token( $HOSTNAME, $USERNAME, $TOKEN, %EXTRA_OPTS )

Like C<new_from_password()> but accepts an API token rather than
a password.

=cut

sub new_from_token ( $class, $hostname, $username, $token, %opts ) {
    $class->_validate_opts( \%opts );

    my %api_args = (
        host       => $hostname,
        user       => $username,
        accesshash => $token,
        %opts,
    );

    return bless { _api_args => \%api_args }, $class;
}

#----------------------------------------------------------------------

=head1 INSTANCE METHODS

=head2 $obj = I<OBJ>->disable_tls_verify()

Disables TLS verification to allow commands to run against a remote
hostname whose TLS is not correctly configured.

This method must be called prior to the first API request.

Returns the object.

=cut

sub disable_tls_verify ($self) {

    $self->{'_api_args'}{'ssl_verify_mode'} //= 1;

    die 'Already connected to remote!' if $self->_already_connected() && $self->{'_api_args'}{'ssl_verify_mode'};

    $self->{'_api_args'}{'ssl_verify_mode'} = 0;

    return $self;
}

=head2 $hostname = I<OBJ>->get_hostname()

Retrieves I<OBJ>’s internally-stored hostname.

=cut

sub get_hostname ($self) {
    return $self->{'_api_args'}{'host'};
}

=head2 $username = I<OBJ>->get_username()

Retrieves I<OBJ>’s internally-stored username.

=cut

sub get_username ($self) {
    return $self->{'_api_args'}{'user'};
}

#----------------------------------------------------------------------

sub _validate_opts ( $class, $opts_hr ) {

    if (%$opts_hr) {
        my @allowed = $class->_NEW_OPTS();

        my @bad = Cpanel::Set::difference(
            [ keys %$opts_hr ],
            \@allowed,
        );

        if (@bad) {
            die "$class: Unknown: @bad";
        }
    }

    return;
}

sub _expand_array_args ( $, $data_hr ) {

    if ( grep { ref } values %$data_hr ) {
        local ( $@, $! );
        require Cpanel::APICommon::Args;

        $data_hr = Cpanel::APICommon::Args::expand_array_refs($data_hr);
    }

    return $data_hr;
}

sub _NEW_OPTS ($) { return }

1;
