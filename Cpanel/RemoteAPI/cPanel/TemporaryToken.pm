package Cpanel::RemoteAPI::cPanel::TemporaryToken;

# cpanel - Cpanel/RemoteAPI/cPanel/TemporaryToken.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::cPanel::TemporaryToken

=head1 SYNOPSIS

    my $token_obj = Cpanel::RemoteAPI::cPanel::TemporaryToken->new(
        api => $api_obj,            # Cpanel::RemoteAPI::cPanel
        prefix => 'myapp',
        validity_length => 3600,    # one hour
    );

    my $token = $token_obj->get();

    # This will delete/revoke the token; if a failure happens a
    # warning is shown.
    undef $token_obj;

=head1 DESCRIPTION

This object encapsulates logic for creating and deleting a temporary API
token on a remote cPanel & WHM server.

=head1 TOKEN NAME

The name of the token is intentionally withheld from this module’s interface
because there I<should> be no need for it. Please do not add methods to
disclose it unless a particular need arises.

=cut

#----------------------------------------------------------------------

use Cpanel::Time::ISO ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class. %OPTS are:

=over

=item * C<api> - A L<Cpanel::RemoteAPI::cPanel> instance.

=item * C<prefix> - A short prefix to add to the token name. This is
here so that, if something goes awry, the prefix gives some indication
of what created the token.

=item * C<validity_length> - A length of time, in seconds, over which
the token is to be valid.

=back

=cut

sub new ( $class, %opts ) {
    my @missing = grep { !$opts{$_} } qw( api validity_length prefix );
    die "Need: @missing" if @missing;

    my $api = $opts{'api'};

    return bless {
        _pid          => $$,
        _api          => $api,
        _validity_len => $opts{'validity_length'},
        _prefix       => $opts{'prefix'},
    }, $class;
}

=head2 $token = I<OBJ>->get()

Returns the API token.

=cut

sub get ($self) {
    return $self->{'_token'} ||= do {
        $self->{'_name'} = _create_api_token_name( $self->{'_prefix'} );

        my $expires_at = time() + $self->{'_validity_len'};

        my $result = $self->{'_api'}->request_uapi(
            Tokens => 'create_full_access',
            {
                name       => $self->{'_name'},
                expires_at => $expires_at,
            },
        );

        if ( !$result->status() ) {
            my $username = $self->{'_api'}->get_username();
            my $hostname = $self->{'_api'}->get_hostname();
            die "“$username” failed to create a temporary API token “$self->{'_name'}” on “$hostname”: " . $result->errors_as_string();
        }

        $result->data()->{'token'};
    };
}

sub DESTROY ($self) {
    my $destroyed;

    if ( $$ == $self->{'_pid'} && $self->{'_token'} ) {

        # This can die(), but Perl will just convert that to a warning.
        my $result = $self->{'_api'}->request_uapi(
            Tokens => 'revoke',
            {
                name => $self->{'_name'},
            },
        );

        if ( $result->status() ) {
            delete $self->{'_token'};

            $destroyed = 1;
        }
        else {
            my $username = $self->{'_api'}->get_username();
            my $hostname = $self->{'_api'}->get_hostname();

            warn "“$username” failed to delete temporary API token “$self->{'_name'}” on “$hostname” because of an error: " . $result->errors_as_string();
        }
    }

    return $destroyed || 0;
}

sub _create_api_token_name ($prefix) {
    my $isotime    = Cpanel::Time::ISO::unix2iso();
    my $random_hex = sprintf '%x', substr( rand, 2 );
    return ( "${prefix}_${isotime}_$random_hex" =~ tr<:><_>r );
}

1;
