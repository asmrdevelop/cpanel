package Cpanel::StringFunc::LineIterator::Indent;

# cpanel - Cpanel/StringFunc/LineIterator/Indent.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $NUMBER_OF_SPACES_FOR_TAB = 4;

use base 'Cpanel::StringFunc::LineIterator';

#----------------------------------------------------------------------

package Cpanel::StringFunc::LineIterator::Indent::InProgress;

use base 'Cpanel::StringFunc::LineIterator::InProgress';
use Cpanel::Exception ();

###########################################################################
#
# Method:
#   prepend_decreased_indent_level
#
# Description:
#   prepend text to a line at
#   one decreased level of indentation
#
# Example:
#    If the line is "    cat" and we prepend "bob\n"
#    the line will be "bob\n    cat"
#
# Parameters:
#   The text to prepend
#
# Returns:
#   none
#
sub prepend_decreased_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_decrease_indent_level_from_current_line( \$new_value );
    return $self->prepend($new_value);
}

###########################################################################
#
# Method:
#   prepend_increased_indent_level
#
# Description:
#   prepend text to a line at
#   one increased level of indentation; i.e., if the line is indented
#   N levels, the line will become:
#       ( ' ' x ($TAB_LEVEL * (N+1)) . $new_value . $current_line
#
# Examples:
#    If the line is "    cat" (i.e., ' ' x 4 . 'cat') and we prepend "bob\n"
#    the line will be "        bob\n    cat"
#
#    If the line is "        foo" (8 spaces) and we prepend "bar"
#    the line will be "            bar        foo" (12 spaces, then 8)
#
# Parameters:
#   The text to prepend
#
# Returns:
#   none
#
sub prepend_increased_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_increase_indent_level_from_current_line( \$new_value );
    return $self->prepend($new_value);
}

###########################################################################
#
# Method:
#   prepend_same_indent_level
#
# Description:
#   prepend text to a line and maintain
#   the current indent level of the line
#
# Example:
#    If the line is "    cat" and we prepend "bob\n"
#    the line will be "    bob\n    cat"
#
# Parameters:
#   The text to prepend
#
# Returns:
#   none
#
sub prepend_same_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_sync_indent_level_to_current_line( \$new_value );
    return $self->prepend($new_value);
}

###########################################################################
#
# Method:
#   append_decreased_indent_level
#
# Description:
#   append text to a line at
#   one decreased level of indentation
#
# Example:
#    If the line is "    bob" and we append "cat\n"
#    the line will be "    bob\ncat\n"
#
# Parameters:
#   The text to append
#
# Returns:
#   none
#
sub append_decreased_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_decrease_indent_level_from_current_line( \$new_value );
    return $self->append($new_value);
}

###########################################################################
#
# Method:
#   append_increased_indent_level
#
# Description:
#   append text to a line at
#   one increased level of indentation
#
# Example:
#    If the line is "    bob" and we append "cat\n"
#    the line will be "    bob\n        cat\n"
#
# Parameters:
#   The text to append
#
# Returns:
#   none
#
sub append_increased_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_increase_indent_level_from_current_line( \$new_value );
    return $self->append($new_value);
}

###########################################################################
#
# Method:
#   append_same_indent_level
#
# Description:
#   append text to a line at
#   the current indent level of the line
#
# Example:
#    If the line is "    bob" and we append "cat\n"
#    the line will be "    bob\n    cat\n"
#
# Parameters:
#   The text to append
#
# Returns:
#   none
#
sub append_same_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_sync_indent_level_to_current_line( \$new_value );
    return $self->append($new_value);
}

###########################################################################
#
# Method:
#   replace_with_same_indent_level
#
# Description:
#   replace text to a line at
#   the current indent level of the line
#
# Example:
#    If the line is "    cat" and we replace with "dog\n"
#    the line will be "    dog\n"
#
# Parameters:
#   The text to replace the current line with
#
# Returns:
#   none
#
sub replace_with_same_indent_level {
    my ( $self, $new_value ) = @_;
    $self->_sync_indent_level_to_current_line( \$new_value );
    return $self->replace_with($new_value);
}

###########################################################################
#
# Method:
#   length_of_whitespace_at_beginning_of_line
#
# Description:
#   Returns the number of spaces before the
#   text begins on a line
#
# Example:
#    If the line is "    cat", the length_of_whitespace_at_beginning_of_line
#    will be 4
#
# Parameters:
#   none
#
# Returns:
#   The number of spaces before the text begins.
#
sub length_of_whitespace_at_beginning_of_line {
    my ($self) = @_;

    return $self->_scalar_ref_length_of_whitespace_at_beginning_of_line( $self->{'_line_sr'} );
}

sub _scalar_ref_length_of_whitespace_at_beginning_of_line {
    my ( $self, $sr ) = @_;

    if ( !$sr || ref $sr ne 'SCALAR' ) {
        die Cpanel::Exception->create_raw('“_scalar_ref_length_of_whitespace_at_beginning_of_line” requires a scalar reference as a parameter.');
    }
    return ( $$sr =~ m{^([ \t]+)} ) ? length($1) : 0;
}

sub _sync_indent_level_to_current_line {
    my $self         = shift;
    my $new_value_sr = shift;
    my $additional   = shift || 0;

    my $indent_text = ( ' ' x $self->length_of_whitespace_at_beginning_of_line() ) || '';
    if ( $additional > 0 ) {
        $indent_text .= ' ' x $additional;
    }
    elsif ( $additional < 0 ) {
        my $remove_chars = abs($additional);
        $indent_text =~ s/[ ]{$remove_chars}//;
    }
    my $new_value_end_with_newline = ${$new_value_sr} =~ m{\n$} ? 1 : 0;

    my @data = split( m{\n}, ${$new_value_sr} );
    foreach (@data) {
        substr( $_, 0, $self->_scalar_ref_length_of_whitespace_at_beginning_of_line( \$_ ), $indent_text );
    }

    $$new_value_sr = join( "\n", @data );
    $$new_value_sr .= "\n" if $new_value_end_with_newline;

    return;
}

sub _increase_indent_level_from_current_line {
    my ( $self, $new_value_sr ) = @_;

    return $self->_sync_indent_level_to_current_line( $new_value_sr, $NUMBER_OF_SPACES_FOR_TAB );
}

sub _decrease_indent_level_from_current_line {
    my ( $self, $new_value_sr ) = @_;

    return $self->_sync_indent_level_to_current_line( $new_value_sr, -1 * $NUMBER_OF_SPACES_FOR_TAB );
}

#----------------------------------------------------------------------
1;
