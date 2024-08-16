package Cpanel::RemoteAPI::cPanel;

# cpanel - Cpanel/RemoteAPI/cPanel.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::RemoteAPI );

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::cPanel

=head1 SYNOPSIS

    my $obj = Cpanel::RemoteAPI::cPanel->new_from_password(
        'host.name',
        'bob',
        'p4$$w0rd',
    );

    my $uapi = $obj->request_uapi('Email', 'verify_password', \%params);

    my $api2 = $obj->request_api2('Email', 'listautoresponders', \%params);

=head1 DESCRIPTION

This class subclasses L<Cpanel::RemoteAPI> for access to a remote
cPanel service.

B<IMPORTANT:> This is B<NOT> what you use to execute a cPanel API call
from within a WHM session. Use L<Cpanel::RemoteAPI::WHM> for that.

=head1 METHODS

=head2 $result = I<OBJ>->request_uapi( $MODULENAME, $FUNCNAME, \%PARAMS )

Calls a UAPI function and returns a L<Cpanel::Result> instance.

%PARAMS is filtered through C<Cpanel::APICommon::args::expand_array_args()>,
so you can submit an array reference as a value, and it’ll expand to
values that L<Cpanel::Args> can reassemble. (The passed-in
hash reference is not modified.)

Owing to implementation details, exceptions are thrown only for certain
(poorly-defined) failures

Note that failures from the API are B<NOT> reported via exception;
you have to inspect the returned object.

=cut

sub request_uapi {
    my ( $self, $module, $func, $data_hr ) = @_;

    $data_hr = $self->_expand_array_args($data_hr);

    local ( $@, $! );
    require Cpanel::RemoteAPI::Backend::cPanel;

    return Cpanel::RemoteAPI::Backend::cPanel::request_uapi(
        $self->_publicapi_obj(),
        sub { },
        'cpanel',
        "/execute/$module/$func",
        'POST',
        $data_hr,
    );
}

#----------------------------------------------------------------------

=head2 $result_hr = I<OBJ>->request_api2( $MODULENAME, $FUNCNAME, \%PARAMS )

Like C<request_uapi()> but for API2, and it returns a hash reference
rather than an object. The hash reference contains C<data> and C<event>;
it B<MAY> also contain C<preevent>, and C<postevent>. See API2’s
documentation for information about what those mean.

=cut

sub request_api2 {
    my ( $self, $module, $func, $data_hr ) = @_;

    $data_hr = $self->_expand_array_args($data_hr);

    my $return = $self->_publicapi_obj()->cpanel_api2_request(
        'cpanel',
        {
            module => $module,
            func   => $func,
        },
        $data_hr,
    );

    $return = $return->{'cpanelresult'} or die 'missing “cpanelresult”!';

    delete @{$return}{ 'apiversion', 'module', 'func' };

    return $return;
}

#----------------------------------------------------------------------

=head2 $version = I<OBJ>->get_cpanel_version_or_die()

Returns the remote major cPanel version (e.g., 94).

Throws an error if anything prevents that from happening.
Caches the response.

=cut

sub get_cpanel_version_or_die ($self) {

    # This logic is here--rather than in a separate module that calls
    # this one--because it’s frequently needed in API client applications,
    # and putting it in a central location allows caching.

    return $self->{'_cp_version'} ||= do {
        my $resp = $self->request_uapi(
            'StatsBar', 'get_stats',
            { display => 'cpanelversion' },
        );

        if ( !$resp->status() ) {
            my $hostname = $self->get_hostname();

            die "Failed to determine $hostname’s cPanel & WHM version: " . $resp->errors_as_string();
        }

        my $version_str = $resp->data()->[0]{'value'};

        $version_str =~ m<([0-9]+)> or do {
            my $hostname = $self->get_hostname();

            die "$hostname’s cPanel & WHM version string ($version_str) is invalid!";
        };

        $1;
    };
}

1;
