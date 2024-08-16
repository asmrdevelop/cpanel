package Cpanel::cPStore::Utils;

# cpanel - Cpanel/cPStore/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Sources ();
use Cpanel::JSON            ();
use Cpanel::HTTP::Client    ();

my %CHARS_TO_UNESCAPE_FROM_CPSTORE;
my $unescape_pattern;

BEGIN {
    no warnings qw(qw);

    #These are the specific characters that the cP Store escapes in all strings.
    %CHARS_TO_UNESCAPE_FROM_CPSTORE = qw(
      &#39;   '
      &lt;    <
      &gt;    >
      &amp;   &
      &quot;  "
    );

    $unescape_pattern = join '|', keys %CHARS_TO_UNESCAPE_FROM_CPSTORE;
}

# TODO: LC-4933: Make this use Whostmgr::TicketSupport::Server::account_hostname().
# Coordinate with intdev on this change, since they may be relying on the way it works now.

sub validate_authn {
    my ( $endpoint, $send_hr ) = @_;

    my $req = Cpanel::HTTP::Client->new(
        default_headers => {
            'Content-Type' => 'application/vnd.cpanel.tickets-v2+json',
        },
    );

    $req->die_on_http_error();

    my $resp = $req->post(
        Cpanel::Config::Sources::get_source('TICKETS_SERVER_URL') . '/oauth2/auth/' . $endpoint,
        {
            content => Cpanel::JSON::Dump($send_hr),
        },
    );

    #NOTE: We don’t validate the Content-Type here; should we?

    return unpack_api_response_content( $resp->content() )->{'data'};
}

#NOTE: This works in-place; it doesn’t return anything.
#
#This is basically HTML decoding, but only for a subset of HTML entities.
#The difference is significant: on the off-chance that that API were to send
#something like “&eacute;” we need to ensure that we don’t errantly
#“over-decode” that to “é”.
sub recursive_cpstore_text_decode {    ##no critic qw(RequireArgUnpacking)
    my ( $thing_r, $isa ) = ( \$_[0], $_[1] );

    if ( defined wantarray ) {
        die "This function returns nothing; it operates in-place.";
    }

    $isa ||= ref $$thing_r;

    if ($isa) {
        if ( 'HASH' eq $isa ) {
            _handle_dollar_underscore() for values %$$thing_r;
        }
        elsif ( 'ARRAY' eq $isa ) {
            _handle_dollar_underscore() for @$$thing_r;
        }
        else {
            die "Unrecognized reference: $$thing_r;";
        }
    }
    else {
        _handle_dollar_underscore() for $$thing_r;
    }

    return;
}

sub unpack_api_response_content {
    my ($resp_content) = @_;

    my $content = Cpanel::JSON::Load($resp_content);

    #As a preventive against stored XSS attacks, the cP Store and login APIs
    #HTML-escape all strings, recursively. So, we have to
    #HTML-decode, recursively. This ordinarily should not make a difference,
    #but it’s in here as a preventive to be sure it never bites us.
    recursive_cpstore_text_decode($content);

    return $content;
}

sub _handle_dollar_underscore {
    my $isa = ref;
    if ($isa) {
        recursive_cpstore_text_decode( $_, $isa );
    }
    elsif ( $_ && -1 != index( $_, '&' ) ) {
        s<($unescape_pattern)><$CHARS_TO_UNESCAPE_FROM_CPSTORE{$1}>g;
    }

    return;
}

1;
