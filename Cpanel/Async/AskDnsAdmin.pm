package Cpanel::Async::AskDnsAdmin;

# cpanel - Cpanel/Async/AskDnsAdmin.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::AskDnsAdmin - asynchronous dnsadmin queries

=head1 SYNOPSIS

    my $dnsadmin = Cpanel::Async::AskDnsAdmin->new();

    $dnsadmin->ask('GETZONES', zone => 'texas.com')->then(
        sub ($payload) {
        },
    );

=head1 DESCRIPTION

This module implements client logic for dnsadmin via non-blocking I/O.
It’s a complement to the blocking I/O in L<Cpanel::DnsUtils::AskDnsAdmin>.

=cut

# One-liner:
# perl -Mstrict -w -MData::Dumper -MCpanel::PromiseUtils -MCpanel::Async::AskDnsAdmin -e'my $dnsadmin = Cpanel::Async::AskDnsAdmin->new(); my $p = $dnsadmin->ask("GETZONES", zone => "texas.com"); print Dumper( Cpanel::PromiseUtils::wait_anyevent($p)->get() )'

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use AnyEvent    ();
use Promise::XS ();

use Net::Curl::Easy ();

use Net::Curl::Promiser::AnyEvent ();

use Cpanel::Async::Throttler               ();
use Cpanel::DnsUtils::AskDnsAdmin::Backend ();
use Cpanel::Exception                      ();
use Cpanel::LoadModule                     ();
use Cpanel::NetCurlEasy                    ();
use Cpanel::Promise::Interruptible         ();

# overridden in tests
our $_SOCKET_PATH = Cpanel::DnsUtils::AskDnsAdmin::Backend::SOCKET_PATH;

use constant _POOL_SIZE => 10;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {
        _throttler   => Cpanel::Async::Throttler->new(_POOL_SIZE),
        _dnsadminapp => Cpanel::DnsUtils::AskDnsAdmin::Backend::get_dnsadminapp_path(),
    }, $class;
}

=head2 promise($answer) = I<OBJ>->ask( $QUESTION, %OPTS )

Sends a “normal” (remote-and-local) query to dnsadmin.

$QUESTION is the name (e.g., C<SYNCZONES>) of the query to send to dnsadmin.
A corresponding C<Cpanel::DnsAdmin::Query::*> module B<MUST> exist for
$QUESTION, or an exception is thrown.

%OPTS are sent to dnsadmin. Depending on the $QUESTION being sent, this
might typically contain C<zone>, C<zonedata>, C<dnsuniqid>, and/or
perhaps others.

The returned promise resolves to whatever the $QUESTION’s corresponding
C<Cpanel::DnsAdmin::Query::*> module’s C<parse_response()> method returns.

That promise may be C<interrupt()>ed (cf. L<Cpanel::Promise::Interruptible>)
to cancel the in-progress query.

=cut

sub ask ( $self, $question, %opts ) {
    return $self->_ask( [], $question, \%opts );
}

=head2 promise($answer) = I<OBJ>->ask_local_only( $QUESTION, %OPTS )

Like C<ask()> but sends a local-only query.

=cut

sub ask_local_only ( $self, $question, %opts ) {
    return $self->_ask( [Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_LOCAL_ONLY], $question, \%opts );
}

=head2 promise($answer) = I<OBJ>->ask_remote_only( $QUESTION, %OPTS )

Like C<ask()> but sends a remote-only query.

=cut

sub ask_remote_only ( $self, $question, %opts ) {
    return $self->_ask( [Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_REMOTE_ONLY], $question, \%opts );
}

=head2 promise($answer) = I<OBJ>->ask_correlative( $QUESTION, %OPTS )

Like C<ask()> but sends a correlative query.

=cut

sub ask_correlative ( $self, $question, %opts ) {
    if ( !$opts{'dnsuniqid'} ) {
        die 'Correlative queries require “dnsuniqid”.';
    }

    return $self->_ask( [Cpanel::DnsUtils::AskDnsAdmin::Backend::ARG_CORRELATIVE], $question, \%opts );
}

#----------------------------------------------------------------------

sub _get_restarter () {
    require Cpanel::Async::AskDnsAdmin::Restarter;
    return Cpanel::Async::AskDnsAdmin::Restarter->new($_SOCKET_PATH);
}

sub _ask_path ( $self, $question, $args_ar, $opts_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    require Cpanel::Async::AskDnsAdmin::Exec;

    return Cpanel::Async::AskDnsAdmin::Exec::ask(
        $self->{'_dnsadminapp'},
        $question,
        $args_ar,
        $opts_hr,
    );
}

sub _ask ( $self, $args_ar, $question, $opts_hr ) {    ## no critic qw(ManyArgs) - mis-parse

    if ( $self->{'_dnsadminapp'} ) {
        return $self->_ask_path( $question, $args_ar, $opts_hr );
    }

    my $query_class = Cpanel::LoadModule::load_perl_module("Cpanel::DnsAdmin::Query::$question");

    my $promiser = $self->{'_promiser'} ||= Net::Curl::Promiser::AnyEvent->new();

    my $url = Cpanel::DnsUtils::AskDnsAdmin::Backend::get_url_path_and_query( $question, @$args_ar );
    substr( $url, 0, 0, 'http://localhost' );

    my $easy = $self->_get_curl_easy($url);

    Cpanel::NetCurlEasy::set_form_post( $easy, $opts_hr );

    my $restarter;

    my $throttler = $self->{'_throttler'};

    my ( $interrupted, $added_to_promiser );

    # This deferred is here to provide a means for cancellation requests
    # to remove the request from the throttler if the request is already
    # given to libcurl. Without this, cancellation would “leak” the
    # request in the throttler.
    #
    my $throttler_d = Promise::XS::deferred();

    my $enqueued_deferred;

    my $p = $self->{'_throttler'}->add(
        sub {
            my $throttled_task = __SUB__;

            return if $interrupted;
            $added_to_promiser = 1;

            my $curl_promise = $promiser->add_handle($easy)->then(
                sub ($easy) {
                    my $code = $easy->getinfo(Net::Curl::Easy::CURLINFO_RESPONSE_CODE);

                    if ( $code - ( $code % 100 ) != 200 ) {
                        die "dnsadmin “$question” request failed: $easy->{'head'}$easy->{'body'}";
                    }

                    return $query_class->parse_response( $easy->{'body'} );
                },
                sub ($err) {
                    if ( eval { $err->isa('Net::Curl::Easy::Code') } ) {
                        my $code  = 0 + $err;
                        my $str   = q<> . $err;
                        my $cperr = Cpanel::Exception->create_raw("Curl error ($code): $str");

                        if ( $code == Net::Curl::Easy::CURLE_COULDNT_CONNECT ) {
                            warn "Failed to connect to dnsadmin; will enqueue a restart and retry …\n";

                            $restarter ||= _get_restarter();

                            my $socket_p = $restarter->on_connect_failure($cperr);

                            return $socket_p->then(
                                sub ($socket) {
                                    warn "dnsadmin is back up; retrying request …\n";
                                    Cpanel::NetCurlEasy::set_socket_if_supported( $easy, $socket );
                                    $throttler->add($throttled_task);
                                },
                            );
                        }

                        $err = $cperr;
                    }

                    local $@ = $err;
                    die;
                },
            );

            if ($enqueued_deferred) {

                # We get here if we retried. In this case we don’t
                # care about $throttler_d because a previous time
                # through this logic already took care of that.
                # So we just return the curl promise:

                return $curl_promise;
            }
            else {

                # The normal/default workflow:

                $enqueued_deferred = 1;

                $curl_promise->then(
                    sub { $throttler_d->resolve(@_) },
                    sub { $throttler_d->reject(@_) },
                );

                return $throttler_d->promise();
            }
        }
    );

    return Cpanel::Promise::Interruptible->new(
        $p,
        sub {
            $interrupted = 1;

            if ($added_to_promiser) {
                $promiser->cancel_handle($easy);

                # Make the throttler move past this request:
                $throttler_d->resolve();
            }
        },
    );
}

sub _get_curl_easy ( $self, $url ) {
    my $curl_easy = Cpanel::NetCurlEasy::create_simple($url);

    Cpanel::NetCurlEasy::set_request_headers(
        $curl_easy,

        # This disables libcurl’s “Expect: 100-continue” header, which
        # as of this writing causes dnsadmin to time out because it
        # naïvely awaits the payload rather than sending the expected
        # “100 Continue” response.
        Expect => undef,

        map { @$_ } Cpanel::DnsUtils::AskDnsAdmin::Backend::get_headers(),
    );

    Cpanel::NetCurlEasy::set_unix_socket_path( $curl_easy, $_SOCKET_PATH );

    return $curl_easy;
}

1;
