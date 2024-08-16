package Cpanel::Output::Formatted;

# cpanel - Cpanel/Output/Formatted.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Output';

use Cpanel::Output::Terminal ();
use Cpanel::ScalarUtil       ();
use Cpanel::StringFunc::Fmt  ();

use constant {
    _prepend_message => q{},

    # This is useful when you want the timestamp to be the leftmost
    # thing on the line (e.g., AutoSSL logs).
    INDENT_AFTER_PREPEND => 0,
};

sub _init {
    my ($self) = @_;

    return $self->reset();
}

sub reset {
    my ($self) = @_;

    $self->{'_indent_level'}             = 0;
    $self->{'_last_message_had_newline'} = 1;    # Assume we start on a fresh line

    return 1;
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
#   $partial_message          - The message is part of a message (usually means more is coming and not to terminate with a new line)
#
# NOTE: $message_contents can be like:
#   'my message'
#   [ 'my message' ]
#   { msg => 'my message' }
#   { msg => [ 'my message' ] }
#
# Returns:
#   True or False depending on the systems ability to write the message.
#
sub message {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $message_type, $msg_contents, $source, $partial_message, $prepend_message ) = @_;

    #XXX Misleading name, since $message_as_text can also be
    #an arrayref or a blessed/overloaded object.
    my $message_as_text = ( 'HASH' eq ref $msg_contents ) ? $msg_contents->{'msg'} : $msg_contents;

    #In case of stringify-overloaded objects (e.g., Cpanel::Exception)
    if ( ref($message_as_text) && Cpanel::ScalarUtil::blessed($message_as_text) ) {
        $message_as_text .= q<>;
    }

    if ( $message_type eq 'failed' || $message_type eq 'fail' || $message_type eq 'error' ) {
        $self->_safe_render_message( $message_as_text, Cpanel::Output::Terminal::COLOR_ERROR(), $partial_message, $prepend_message );
    }
    elsif ( $message_type eq 'warn' ) {
        $self->_safe_render_message( $message_as_text, Cpanel::Output::Terminal::COLOR_WARN(), $partial_message, $prepend_message );
    }
    elsif ( $message_type eq 'success' ) {
        $self->_safe_render_message( $message_as_text, Cpanel::Output::Terminal::COLOR_SUCCESS(), $partial_message, $prepend_message );
    }
    elsif ( $message_type eq 'header' ) {
        $self->_safe_render_message( $message_as_text, 'bold', $partial_message, $prepend_message );
    }
    elsif ( grep { $message_type eq $_ } qw{out debug} ) {
        if ( $source && $source->{'host'} ) {
            $self->_safe_render_message( $message_as_text, 'bold black on_white', $partial_message, $prepend_message );

        }
        else {
            $self->_safe_render_message( $message_as_text, $Cpanel::Output::SOURCE_NONE, $partial_message, $prepend_message );
        }
    }
    else {
        if ( ref $msg_contents ) {
            print { $self->{'filehandle'} } "UNHANDLED TYPE: [$message_type]: " . join( ', ', map { "$_ => $msg_contents->{$_}" } keys %{$msg_contents} ) . "\n";
        }
        else {
            print { $self->{'filehandle'} } "UNHANDLED TYPE: [$message_type]: $message_as_text\n";
        }
    }

    return;
}

###########################################################################
#
# Method:
#   format_message
#
# Description:
#   Applies color formatting appropriate for the output destination
#
# Parameters:
#   $color               - The color to decorate the message with
#   $message             - The contents of the message
#
# Returns:
#   True or False depending on the systems ability to write the message.
#
sub format_message {

    #my ( $self, $color, $message ) = @_;
    return $_[0]->_format_text( $_[1] || '', $_[2] );
}

sub _safe_render_message {
    my ( $self, $msg, $color, $partial_message, $prepend_message ) = @_;

    $msg = join( "\n", @{$msg} ) if ref $msg;

    # If the message is empty, we just want to output a new line
    $msg = q<> if !defined $msg;

    my $last_line_ends_with_new_line = ( length $msg && substr( $msg, -1, 1 ) eq "\n" ) ? 1 : 0;
    my @lines                        = split( /\n/, $msg );

    # Make sure we can output a blank line
    @lines = ('') if !@lines;

    my $last_line_to_add_new_line = -1;
    if ( scalar @lines == 1 ) {
        if ( !$partial_message || $last_line_ends_with_new_line ) {
            $last_line_ends_with_new_line = 1;
            $last_line_to_add_new_line    = 1;
        }
    }
    else {
        $last_line_to_add_new_line    = $#lines - ( $partial_message ? 1 : 0 );
        $last_line_ends_with_new_line = $#lines == $last_line_to_add_new_line ? 1 : 0;
    }

    my $output;

    foreach my $count ( 0 .. $#lines ) {
        $output = $self->{'_last_message_had_newline'} ? $self->_indent() : '';

        # Prepend if we need to - this is done for things like timestamps
        my $prepend = $prepend_message ? $self->_prepend_message() : q{};

        if ( $self->INDENT_AFTER_PREPEND() ) {
            substr( $output, 0, 0, $prepend );
        }
        else {
            $output .= $prepend;
        }

        $output .=                                             #
                                                               # Format the actual message with color. Passing in a newline will cause background colors to bleed to the next line.
          $self->format_message( $color, $lines[$count] ) .    #

          # Add a newline if we need to. This needs to be done AFTER coloring otherwise the
          # background color will bleed to the new line
          ( $count <= $last_line_to_add_new_line ? $self->_new_line() : q{} );    #

        if ( $self->{'_parent'} ) {
            my $pid = $self->{'_parent'}{'pid'};
            my ( $queue, $child_number, $item_name, $item ) = @{ $self->{'_parent'}{'contents'} }{ 'queue', 'child_number', 'item_name', 'item' };

            my $pid_info       = ( $self->{'fmt_cache_pid'}{$pid}                                  //= Cpanel::StringFunc::Fmt::fixed_length( $pid,                   6, $Cpanel::StringFunc::Fmt::ALIGN_RIGHT ) );
            my $job_info       = ( $self->{'fmt_cache_queue_child_number'}{"$queue:$child_number"} //= Cpanel::StringFunc::Fmt::fixed_length( "$queue:$child_number", 10 ) );
            my $item_info      = ( $self->{'fmt_cache_item_name'}{$item_name}                      //= Cpanel::StringFunc::Fmt::fixed_length( $item_name,             1 ) );
            my $item_formatted = ( $self->{'fmt_cache_item'}{$item}                                //= Cpanel::StringFunc::Fmt::fixed_length( $item,                  16 ) );
            substr(
                $output, 0, 0,
                $self->format_message( 'base1', "[" . $pid_info . "]" . "[" . $job_info . "]" . "[" . $item_info . ':' . $item_formatted . "]" . ": " )
            );
        }

        print { $self->{'filehandle'} } $output;
    }

    $self->{'_last_message_had_newline'} = $last_line_ends_with_new_line;

    return;
}

1;

__END__
