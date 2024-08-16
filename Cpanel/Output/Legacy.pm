package Cpanel::Output::Legacy;

# cpanel - Cpanel/Output/Legacy.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Cpanel::Output';

###########################################################################
#
# Method:
#   message
#
# Description:
#   Sends a message to wherever the Cpanel::Output object is configured
#   to send them
#
# Parameters:
#   $message_type             - The type of message (Ex. out, warn, error)
#   $message_contents         - The contents of the message (Usually a hashref)
#   $source                   - The source of the message (usually the hostname of a server)
#
# Returns:
#   True or False depending on the systems ability to write the message.
#
#
sub message {
    my ( $self, $message_type, $msg_ref ) = @_;

    my $msg = ref $msg_ref ? ( $msg_ref->{'msg'} || $msg_ref->{'statusmsg'} ) : $msg_ref;
    if ( ref $msg ) { $msg = join( ' ', @{$msg} ) }
    $msg =~ s/\r?\n$//g;
    if ( $message_type eq 'modulestatus' ) {
        print { $self->{'filehandle'} } "[$message_type][$msg_ref->{'module'}]: " . $msg . "\n";
    }
    elsif ( $message_type eq 'control' ) {
        print { $self->{'filehandle'} } "[$message_type][$msg_ref->{'action'}]: " . $msg . "\n";
    }
    elsif ( $message_type eq 'out' ) {
        print { $self->{'filehandle'} } $msg . "\n";
    }
    else {
        print { $self->{'filehandle'} } "[$message_type]: " . $msg . "\n";
    }
    return print { $self->{'filehandle'} } "<br />";    #sigh!
}

1;
