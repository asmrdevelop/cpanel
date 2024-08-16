package Cpanel::Output::Restore;

# cpanel - Cpanel/Output/Restore.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
use base 'Cpanel::Output::Formatted';

use Cpanel::Output::Terminal ();
use Cpanel::Locale           ();
use Cpanel::Time::Local      ();

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

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
sub message {
    my ( $self, $message_type, $msg_contents, $source ) = @_;

    my $action = $msg_contents->{'action'};
    if ( $message_type eq 'control' ) {
        if ( $action =~ m{^start_module} ) {
            $self->{'_indent_level'} = 0;
            $self->_safe_render_message( $msg_contents->{'msg'}, 'bold blue' );
            $self->{'_indent_level'}++;
        }
        elsif ( $action =~ m{^end_module} ) {
            $self->{'_indent_level'} = 1;
            $self->_safe_render_message( $msg_contents->{'msg'}, 'green' );
        }
        elsif ( $action =~ m{^start_} ) {
            $self->{'_indent_level'}++;
            $self->_safe_render_message( $msg_contents->{'msg'}, 'bold' );
        }
        elsif ( $action =~ m{^end_} ) {
            $self->{'_indent_level'}-- if $self->{'_indent_level'} >= 2;
        }
        elsif ( $action =~ m{^percentage} ) {
            local $self->{'_indent_level'} = 0;
            $self->_safe_render_message( [ $msg_contents->{'time'} ? _locale()->maketext( "Progress: [numf,_1]% ([_2])", $msg_contents->{'percentage'}, Cpanel::Time::Local::localtime2timestamp( $msg_contents->{'time'} ) ) : _locale()->maketext( "Progress: [numf,_1]%", $msg_contents->{'percentage'} ) ], 'bold black on_blue' );
        }
        else {
            print { $self->{'filehandle'} } "UNHANDLED ACTION: [$action]: " . join( ', ', map { "$_ => $msg_contents->{$_}" } keys %{$msg_contents} ) . "\n";
        }
    }
    elsif ( $msg_contents->{'module'} ) {
        if ( $msg_contents->{'status'} ) {
            $self->_safe_render_message( $msg_contents->{'statusmsg'}, Cpanel::Output::Terminal::COLOR_SUCCESS() );
        }
        else {
            $self->_safe_render_message( $msg_contents->{'statusmsg'}, Cpanel::Output::Terminal::COLOR_ERROR() );
        }
    }
    elsif ( $message_type eq 'start' ) {
        $self->_safe_render_message( $msg_contents->{'msg'}, '' );
    }
    else {
        $self->SUPER::message( $message_type, $msg_contents, $source );
    }
    return;
}

1;

__END__
