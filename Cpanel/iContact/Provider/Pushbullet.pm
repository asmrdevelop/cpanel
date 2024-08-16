package Cpanel::iContact::Provider::Pushbullet;

# cpanel - Cpanel/iContact/Provider/Pushbullet.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use parent 'Cpanel::iContact::Provider';

use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

our $PUSHBULLET_CLASS = 'Cpanel::Pushbullet';

###########################################################################
#
# Method:
#   send
#
# Description:
#   This implements sending Pushbullet messages.  For arguments to create
#   a Cpanel::iContact::Provider::Pushbullet object, see Cpanel::iContact::Provider.
#
# Exceptions:
#   This module throws on failure
#
# Returns: 1
#
sub send {
    my ($self) = @_;

    my $args_hr = $self->{'args'};
    Cpanel::LoadModule::load_perl_module($PUSHBULLET_CLASS);

    my @errs;

    foreach my $apikey ( @{ $args_hr->{'to'} } ) {
        my $pb = $PUSHBULLET_CLASS->new( access_token => $apikey );

        try {
            $pb->push_note(
                title => $args_hr->{'subject'},
                body  => ${ $args_hr->{'text_body'} },
            );
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
