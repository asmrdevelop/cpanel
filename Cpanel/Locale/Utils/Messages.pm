package Cpanel::Locale::Utils::Messages;

# cpanel - Cpanel/Locale/Utils/Messages.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub _localize_messages {
    my ( $locale, $messages_ref ) = @_;
    my @messages;

    foreach my $msg ( @{$messages_ref} ) {
        if ( exists $msg->{'maketext'} ) {    ## no extract maketext
            push @messages, $locale->makevar( @{ $msg->{'maketext'} } );    ## no extract maketext
        }
        elsif ( exists $msg->{'raw'} ) {
            push @messages, $msg->{'raw'};
        }

    }
    return \@messages;
}

1;
