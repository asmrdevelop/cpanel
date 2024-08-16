package Cpanel::Pushbullet;

# cpanel - Cpanel/Pushbullet.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Access interface to the Pushbullet API.
#
# NOTE: We do not use WWW::PushBullet because that module:
#
#   - print()s errors rather than die()ing
#   - is not very informative about failures
#   - uses LWP
#   - misspells the very technology with which it interfaces! :-(
#
# These are not bugs per se, but design aspects that make that module
# less than ideal for our use.
#----------------------------------------------------------------------

use strict;

use Cpanel::HTTP::Tiny::FastSSLVerify ();
use Try::Tiny;

use Cpanel::Exception ();
use Cpanel::JSON      ();

our $_URL_APIV2 = 'https://api.pushbullet.com/v2';

#for testing
our $_verify_SSL = 1;

#opts:
#
#   - access_token  (string, required)
#
sub new {
    my ( $class, %opts ) = @_;

    die 'Need “access_token”!' if !length $opts{'access_token'};

    my $self = {
        _token => $opts{'access_token'},
        _http  => Cpanel::HTTP::Tiny::FastSSLVerify->new(
            verify_SSL => $_verify_SSL,
        ),
    };

    return bless $self, $class;
}

#----------------------------------------------------------------------
#This implements part of the interaction described at:
#   https://docs.pushbullet.com/#pushes
#
#opts:
#
#   - body  (string, required)
#
#   - title (string, required)
#
#NOTE: The exceptions that this throws contain quite a lot of metadata.
#
sub push_note {
    my ( $self, %opts ) = @_;

    for my $attr (qw( title body )) {
        die "Need “$attr”!" if !length $opts{$attr};
    }

    my $resp = $self->{'_http'}->post(
        "$_URL_APIV2/pushes",
        {
            headers => {
                'Content-Type'  => 'application/json',
                'Authorization' => "Bearer $self->{'_token'}",
            },
            content => Cpanel::JSON::Dump(
                {
                    type  => 'note',
                    title => $opts{'title'},
                    body  => $opts{'body'},
                }
            ),
        },
    );

    my $content = $resp->{'content'};

    my ( $resp_parsed, $err_details );
    try {
        $resp_parsed = Cpanel::JSON::Load($content);
        $err_details = $resp_parsed->{'error'};
    }
    catch {
        if ( $resp->{'success'} ) {
            warn "JSON parse of payload ($content) failed: $_";
        }
    };

    if ( !$resp->{'success'} ) {

        my $err;

        my $basic_err_str = "$resp->{'status'} - $resp->{'reason'}";

        my %err_attrs = (
            http_status => $resp->{'status'},
            http_reason => $resp->{'reason'},
        );

        if ($err_details) {
            %err_attrs = ( %err_attrs, %$err_details );

            $err = Cpanel::Exception->create( 'The system failed to send a note via [asis,Pushbullet] because of an error of type “[_1]”: [_2] ([_3])', [ @{$err_details}{qw( type message )}, $basic_err_str ], \%err_attrs );
        }
        elsif ($content) {
            $err = Cpanel::Exception->create( 'The system failed to send a note via [asis,Pushbullet] because of an error: [_1]. The payload ([_2]) was also invalid.', [ $basic_err_str, $content ], \%err_attrs );
        }
        else {
            $err = Cpanel::Exception->create( 'The system failed to send a note via [asis,Pushbullet] because of an error: [_1].', [$basic_err_str], \%err_attrs );
        }

        die $err;
    }

    return $resp_parsed;
}

1;
