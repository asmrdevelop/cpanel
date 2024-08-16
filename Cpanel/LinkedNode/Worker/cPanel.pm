package Cpanel::LinkedNode::Worker::cPanel;

# cpanel - Cpanel/LinkedNode/Worker/cPanel.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::cPanel

=head1 SYNOPSIS

    # The same pattern goes for call_api2().
    my $result = Cpanel::LinkedNode::Worker::cPanel::call_uapi( %opts );

=head1 DESCRIPTION

This module contains logic to call cPanel APIs on a remote cPanel
& WHM server.

Note that, unlike L<Cpanel::LinkedNode::Worker::User>, this module
does I<not> require any particular global state. This module is
equally usable from a privileged or an unprivileged process.

=cut

#----------------------------------------------------------------------

use Cpanel::App                ();
use Cpanel::APICommon::Persona ();    # PPI NO PARSE - constants
use Cpanel::LinkedNode::User   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $result = call_uapi( %OPTS )

Calls UAPI on a remote server and returns the result as a
L<Cpanel::Result> instance.

This function expects to be called from cPanel. If called from any other
context an exception is thrown. This sanity-check assertion prevents
inadvertent misuse. See below for an equivalent function that works from
any context.

This object’s metadata is given a C<proxied_from> array that
indicates to the caller where the response came from.
C<proxied_from> is an array because the remote host might itself
proxy the API request to a different server. C<proxied_from>
is sorted in ascending chronological order, e.g., the most
recent server’s hostname will be last.

The given %OPTS are:

=over

=item * C<worker_alias> - The alias of the server to call

=item * C<username> - The username to give to the server

=item * C<token> - The API token to submit with the API call

=item * C<module> - The API function’s module name

=item * C<function> - The function name

=item * C<arguments> - Optional, a hashref of arguments to the function

=back

NOTE: This accepts C<worker_alias> rather than a hostname because it
needs to look up the worker node’s configuration.

=cut

sub call_uapi (@opts_kv) {
    _die_if_not_cpanel();

    return call_uapi_from_anywhere(@opts_kv);
}

#----------------------------------------------------------------------

=head2 $result = call_uapi_from_anywhere( %OPTS )

Like C<call_uapi()> but may be called from any context. Please ensure that
your application truly needs this before using it; actual use cases should
be rare.

=cut

sub call_uapi_from_anywhere (%opts) {
    return _call_api(
        \%opts,
        \&_send_uapi_request,
        \&_handle_uapi_failure,
    );
}

sub _send_uapi_request {
    my ( $obj, $hostname, $module, $fn, $args_hr ) = @_;

    $args_hr ||= {};
    local $args_hr->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    my $result = $obj->request_uapi(
        $module,
        $fn,
        $args_hr,
    );

    $result->metadata(
        'proxied_from',
        [
            @{ $result->metadata('proxied_from') // [] },
            $hostname,
        ],
    );

    return $result;
}

sub _handle_uapi_failure {
    my $err = shift;

    local ( $@, $! );
    require Cpanel::Result;

    my $result = Cpanel::Result->new();
    $result->raw_error($err);
    $result->status(0);

    return $result;
}

#----------------------------------------------------------------------

=head2 $result_hr = call_api2( %OPTS )

Like C<call_uapi()> but for API2 and returns an unblessed hash reference
rather than an object.

That hash reference is the contents of the raw API2 response’s
C<cpanelresult>, augmented with a root-level C<proxied_from> array reference
that contains the same information that C<call_uapi()> adds to its
response’s metadata.

=cut

sub call_api2 {
    my (%opts) = @_;

    _die_if_not_cpanel();

    return _call_api(
        \%opts,
        \&_send_api2_request,
        \&_handle_api2_failure,
    );
}

sub _send_api2_request {
    my ( $obj, $hostname, $module, $fn, $args_hr ) = @_;

    $args_hr ||= {};
    local $args_hr->{'api2_persona'} = Cpanel::APICommon::Persona::PARENT;

    my $result = $obj->request_api2(
        $module,
        $fn,
        $args_hr,
    );

    push @{ $result->{'proxied_from'} }, $hostname;

    return $result;
}

sub _handle_api2_failure {
    my ($err) = @_;

    return {
        data => {
            result => 0,
            reason => $err,
        },

        error => $err,

        event => {
            result => 0,
            reason => $err,
        },
    };
}

sub _call_api {
    my ( $opts_hr, $todo_cr, $onerror_cr ) = @_;

    my ( $worker_alias, $username, $token, $module, $fn, $args_hr ) = @{$opts_hr}{qw( worker_alias  username  token  module  function  arguments )};

    my $linked_node_conf = Cpanel::LinkedNode::User::get_node_configuration($worker_alias);

    local ( $@, $! );

    my $hostname = $linked_node_conf->hostname();

    my $result = eval {
        require Cpanel::RemoteAPI::cPanel;
        my $obj = Cpanel::RemoteAPI::cPanel->new_from_token( $hostname, $username, $token );

        $obj->disable_tls_verify() if $linked_node_conf->allow_bad_tls();

        return $todo_cr->( $obj, $hostname, $module, $fn, $args_hr );
    };

    return $result || $onerror_cr->("Failed to send API request to “$hostname” as “$username”: $@");
}

sub _die_if_not_cpanel() {

    # Ordinarily we don’t make remote API calls from Webmail
    # because a webmail session should only exist on the Mail worker.
    # The following is a sanity check to ensure that.
    die 'Only cPanel calls worker nodes!' if !Cpanel::App::is_cpanel();

    return;
}

1;
