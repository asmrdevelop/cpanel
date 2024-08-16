package Cpanel::Server::WebCalls;

# cpanel - Cpanel/Server/WebCalls.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebCalls

=head1 SYNOPSIS

    my $ran = Cpanel::Server::WebCalls::handle('ggiugyxxjwnkmqtwysgmvrurplmafxpj');

    if ($ran) { .. }

=head1 DESCRIPTION

This module implements cpsrvd’s handler for C<cpanelwebcall> requests.

=cut

#----------------------------------------------------------------------

use Cpanel::WebCalls::Datastore::Read  ();
use Cpanel::WebCalls::Datastore::Write ();    # PPI USE OK -- preload for performance

use Cpanel::Exception           ();
use Cpanel::WebCalls::Constants ();           # PPI NO PARSE - mis-parse
use Cpanel::WebCalls::ID        ();
use Cpanel::Try                 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $id = extract_id_from_request( $URL_AFTER_INITIAL )

This function extracts the webcall id from a request. It is expected
that the leading C</cpanelwebcall/> will be removed.

The return value is a string representing the web call id.

=cut

sub extract_id_from_request ($request) {

    my $slash_at = index( $request, '/' );
    my $id;

    if ( $slash_at == -1 ) {
        $id = $request;
    }
    else {
        $id = substr( $request, 0, $slash_at );
    }

    return $id;
}

=head2 $ran_yn = handle( $URL_AFTER_INITIAL )

This function processes the webcalls request. It is expected that the
leading C</cpanelwebcall/> will be removed.

The return value is a boolean that indicates whether the webcall ran.

This throws L<Cpanel::Exception::cpsrvd> exceptions to indicate failure
of the request, e.g., C<NotFound> if there’s no such webcall, etc.

=cut

sub handle ($request) {

    my $id = extract_id_from_request($request);
    substr( $request, 0, length $id ) = q<>;

    Cpanel::WebCalls::ID::is_valid($id) or do {
        die _http_invalid_params_err("Invalid webcall ID: $id");
    };

    my @args;

    if ( length $request ) {

        # We can only have gotten here if the first character in $request
        # is a slash, so we don’t need to validate that.

        # Reject "$id/":
        if ( 1 == length $request ) {
            die _http_invalid_params_err('Argument(s) must follow slash.');
        }

        substr $request, 0, 1, q<>;

        @args = split m</>, $request, -1;
    }

    local ( $@, $! );

    my $entry_obj = Cpanel::WebCalls::Datastore::Read->read_if_exists($id);

    if ( !$entry_obj ) {
        die Cpanel::Exception::create('cpsrvd::NotFound');
    }

    my $ran;

    if ( my $needs_wait = _rate_limit_wait($entry_obj) ) {
        die Cpanel::Exception::create(
            'cpsrvd::TooManyRequests',
            [ retry_after => $needs_wait ],
        );
    }

    require Cpanel::WebCalls::Run;

    Cpanel::Try::try(
        sub {
            local $SIG{'__DIE__'};
            $ran = Cpanel::WebCalls::Run::validate_and_run( $id, $entry_obj, @args );
        },

        'Cpanel::Exception::InvalidParameter' => sub ($err) {
            die _http_invalid_params_err( $err->to_string_no_id() );
        },
    );

    return $ran;
}

sub _http_invalid_params_err ($why) {
    return Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $why );
}

sub _rate_limit_wait ($entry_obj) {
    require Cpanel::RateLimit;

    return Cpanel::RateLimit::get_wait(
        'Cpanel::WebCalls::Constants',
        [ $entry_obj->last_run_times() ],
    );
}

1;
