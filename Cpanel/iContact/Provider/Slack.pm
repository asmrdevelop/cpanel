package Cpanel::iContact::Provider::Slack;

# cpanel - Cpanel/iContact/Provider/Slack.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::iContact::Provider';

use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Encode             ();

our $SLACK_CLASS = 'Slack::WebHook';

=encoding utf-8

=head1 NAME

Cpanel::iContact::Provider::Slack - iContact wrapper for Slack::WebHook

=head1 SYNOPSIS

    use Cpanel::iContact::Provider::Slack;
    my $slack = Cpanel::iContact::Provider::Slack->new( url => $url);
    $slack->send( $hash_ref );

See Cpanel::iContact::Provider for more information

=head1 DESCRIPTION

A class for sending iContact notifications via Slack

=head2 send

Sends a message to one of more Slack WebHooks

=head3 INPUT

See Cpanel::iContact for information about arguments

=head3 OUTPUT

Throws Cpanel::Exception::Collection on failure. Returns 1 otherwise

=cut

sub send {
    my ($self) = @_;

    my $args_hr = $self->{'args'};
    my @errs;

    Cpanel::LoadModule::load_perl_module($SLACK_CLASS);

    # Note Encode::decode_utf8 must operate on the copy
    # as it will break the input
    my $subject_copy = $args_hr->{'subject'};
    my $body_copy    = ${ $args_hr->{'text_body'} };
    my $subject      = Encode::decode_utf8( $subject_copy, Encode::FB_QUIET );
    my $body         = Encode::decode_utf8( $body_copy,    Encode::FB_QUIET );

    foreach my $url ( @{ $args_hr->{'to'} } ) {
        my $obj = $SLACK_CLASS->new( url => $url );
        try {
            my $response = $obj->post_info(
                title => $subject,
                body  => $body,
            );

            if ( !$response->{success} ) {
                die Cpanel::Exception::create( 'ConnectionFailed', 'The system could not send data to the Slack WebHook due to an error: [_2]', [ $url, $response->{content} || $response->{reason} ] );
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
