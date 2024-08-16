package Cpanel::iContact::Provider::Posturl;

# cpanel - Cpanel/iContact/Provider/Posturl.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use parent 'Cpanel::iContact::Provider';

use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::Hostname   ();
use Cpanel::LoadModule ();
use Encode             ();

our $POSTURL_CLASS = 'Cpanel::Posturl';

###########################################################################
#
# Method:
#   send
#
# Description:
#   This implements sending a message to a url via HTTP POST.  For arguments to create
#   a Cpanel::iContact::Provider::Posturl object, see Cpanel::iContact::Provider.
#
# Exceptions:
#   This module throws on failure
#
# Returns: 1
#
sub send {
    my ($self) = @_;

    my $args_hr = $self->{'args'};
    my @errs;

    Cpanel::LoadModule::load_perl_module($POSTURL_CLASS);

    # Note Encode::decode_utf8 must operate on the copy
    # as it will break the input
    my $subject_copy = $args_hr->{'subject'};
    my $body_copy    = ${ $args_hr->{'text_body'} };
    my $subject      = Encode::decode_utf8( $subject_copy, Encode::FB_QUIET );
    my $body         = Encode::decode_utf8( $body_copy,    Encode::FB_QUIET );

    my $obj = $POSTURL_CLASS->new();
    foreach my $url ( @{ $args_hr->{'to'} } ) {
        try {
            my $response = $obj->post(
                $url,
                {
                    subject     => $subject,
                    body        => $body,
                    application => $args_hr->{'application'},
                    event_name  => $args_hr->{'event_name'},
                    hostname    => Cpanel::Hostname::gethostname(),

                }
            );

            if ( !$response->{success} ) {
                die Cpanel::Exception::create( 'ConnectionFailed', 'The system could not send data via [asis,HTTP POST] to the [asis,URL] “[_1]” due to an error: [_2]', [ $url, $response->{content} || $response->{reason} ] );
            }

        }
        catch {
            push @errs, $_;
        };
    }

    if (@errs) {
        die Cpanel::Exception::create( 'Collection', [ exceptions => \@errs ] );
    }

    return 1;
}

1;
