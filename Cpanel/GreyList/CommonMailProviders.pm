package Cpanel::GreyList::CommonMailProviders;

# cpanel - Cpanel/GreyList/CommonMailProviders.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Try::Tiny;

use Cpanel::JSON            ();
use Cpanel::Exception       ();
use Cpanel::HttpRequest     ();
use Cpanel::Config::Sources ();

=head1 NAME

Cpanel::GreyList::CommonMailProviders - helper methods to manage 'common_mail_providers' data for cPGreylist.

=head1 SYNOPSIS

use Cpanel::GreyList::CommonMailProviders ();

=head1 Methods

=over 8

=item B<fetch_latest_data>

Returns the latest 'common mail provider' data retrieved from a cPanel mirror.

Doesn't take any arguments. Returns a hashref.

=cut

sub fetch_latest_data {

    my $httpClient = Cpanel::HttpRequest->new(
        'hideOutput' => 1,
        'logger'     => DummyLogger->new(),    # Cpanel::Logger prints stuff out to screen.
                                               # This DummyLogger object will allow us to suppress such duplicate messages,
                                               # without breaking functionality.
    );
    my $CPSRC = Cpanel::Config::Sources::loadcpsources();

    my $json_data;
    try {
        my $response = $httpClient->request(
            'host'     => $CPSRC->{'HTTPUPDATE'},
            'url'      => '/common_mail_providers/common_mail_provider_ips.json',
            'protocol' => 0,
            'signed'   => 1,
        );
        $json_data = Cpanel::JSON::Load($response);
    }
    catch {
        die Cpanel::Exception->create( 'Failed to download the latest common mail provider [asis,IP] address data: [_1]', [ Cpanel::Exception::get_string($_) ] );
    };

    return $json_data;
}

=back

=cut

package DummyLogger;

sub new {
    my $class = shift;
    my $self  = bless {}, $class;
    return $self;
}

sub info { return; }

1;
