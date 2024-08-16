package Cpanel::StringFunc::LineIterator;

# cpanel - Cpanel/StringFunc/LineIterator.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#The general pattern for this module is:
#
#   my $iterator;
#   $iterator = Cpanel::StringFunc::LineIterator->new(
#       $string_literal,    #i.e., not a reference
#       sub {   #The line is $_
#           $iterator ||= shift;    #isa C::SF::LI::InProgress
#           $iterator->replace_with( tr<a-z><A-Z>r );
#       },
#   );
#
#The above example will capitalize an ASCII buffer, line-by-line.
#It's not a very practical application of this module since it's so much
#more easily accomplished directly, but it illustrates basic usage.
#
#A few points of interest:
#   - The string is modified directly.
#
#   - In the closure, $iterator isa Cpanel::StringFunc::LineIterator::InProgress.
#       What new() actually returns is the same object, re-blessed as
#       Cpanel::StringFunc::LineIterator. This is done so that methods that
#       pertain only while editing the buffer are exposed only at that time.
#
#   - Assign new()'s return to $iterator in case the buffer is empty, in which
#       case the closure never runs.
#
#   - Alter the string with replace_with(). Changing $_ will have no effect.
#
#   - Performance should be reasonably good, but it's definitely less than
#       just iterating through directly. What this module offers is an
#       interface that is arguably cleaner and more readable.
#
#   - Any subclass must define its own ::InProgress class as a subclass
#       of Cpanel::StringFunc::LineIterator::InProgress.
#
#----------------------------------------------------------------------
#TODO: Unify this logic with that in Cpanel::FileUtils::Read::LineIterator.
#----------------------------------------------------------------------

use strict;

#NOTE: After this object is created, pos($$buffer_sr's) will correspond with
#the end of the string.
sub new {    ##no critic qw(RequireArgUnpacking)
             # $_[0]: class
             # $_[1]: buffer
             # $_[2]: todo
    my $class = $_[0];

    my $self = bless {
        _todo_cr               => $_[2],
        _buffer_sr             => \$_[1],
        _first_modified_offset => length $_[1],
      },
      "${class}::InProgress";

    return $self->_run();
}

sub has_changed {
    my ($self) = @_;

    return $self->{'_has_changed'} ? 1 : 0;
}

#i.e., was the stop() method called
sub stopped {
    my ($self) = @_;

    return $self->{'_stopped'} ? 1 : 0;
}

sub get_first_modified_offset {
    my ($self) = @_;

    return $self->{'_has_changed'} ? $self->{'_first_modified_offset'} : undef;
}

#----------------------------------------------------------------------

package Cpanel::StringFunc::LineIterator::InProgress;

use strict;
use parent 'Cpanel::StringFunc::LineIterator';
use Try::Tiny;

sub _run {
    my ($self) = @_;

    my $todo_cr         = $self->{'_todo_cr'};
    my $iteration_index = 0;

    $self->{'_iteration_index_sr'} = \$iteration_index;

    my $buffer_sr = $self->{'_buffer_sr'};
    pos($$buffer_sr) = 0;

    try {
        my $line;
        $self->{'_line_sr'} = \$line;
        while ( $$buffer_sr =~ m<([^\n]*\n|[^\n]+\z)>g ) {

            # We need to make a copy, otherwise if someone modifies $_ in
            # $todo_cr, it will modify ${$self->{_line_sr}} and break things.
            my $cur_line = $line = $1;
            for ($cur_line) {
                $todo_cr->($self);
                $iteration_index++;
            }
        }
    }
    catch {
        die $_ if !UNIVERSAL::isa( $_, __PACKAGE__ . '::_STOP' );
        $self->{'_stopped'} = 1;
    };

    my $done_class = __PACKAGE__;
    $done_class = substr( $done_class, 0, -12 ) if substr( $done_class, -12 ) eq '::InProgress';

    return bless $self, $done_class;
}

###########################################################################
#
# Method:
#   prepend
#
# Description:
#   prepend text to a line
#
# Parameters:
#   The text to append
#
# Returns:
#   none
#
sub prepend {    ##no critic qw(RequireArgUnpacking)
                 # $_[0]: self
                 # $_[1]: new_value
    my $self = $_[0];

    return $self->replace_with( $_[1] . ${ $self->{'_line_sr'} } );
}

###########################################################################
#
# Method:
#   append
#
# Description:
#   append text to a line
#
# Parameters:
#   The text to append
#
# Returns:
#   none
#
sub append {    ##no critic qw(RequireArgUnpacking)
                # $_[0]: self
                # $_[1]: new_value
    my $self = $_[0];

    return $self->replace_with( ${ $self->{'_line_sr'} } . $_[1] );
}

#Replaces the current chunk (i.e., line) with a new value in the buffer.
sub replace_with {    ##no critic qw(RequireArgUnpacking)
                      # $_[0]: self
                      # $_[1]: new_value
    my $self = $_[0];

    my $old_length = length ${ $self->{'_line_sr'} };
    my $new_length = length $_[1];

    my $start_pos_of_change = pos( ${ $self->{'_buffer_sr'} } ) - $old_length;

    substr(
        ${ $self->{'_buffer_sr'} },
        $start_pos_of_change,
        $old_length,
        $_[1],
    );

    if ( $start_pos_of_change < $self->{'_first_modified_offset'} ) {
        $self->{'_first_modified_offset'} = $start_pos_of_change;
    }

    pos( ${ $self->{'_buffer_sr'} } ) = $start_pos_of_change + $new_length;

    $self->{'_has_changed'} = 1;

    # Update the line so we can call this multiple times
    # We need to copy new_value=$_[1] so any changes to
    # it do not creep into $self->{'_line_sr'}
    ${ $self->{'_line_sr'} } = $_[1];

    return;
}

sub get_iteration_index {
    my ($self) = @_;

    return ${ $self->{'_iteration_index_sr'} };
}

#NOTE: Not "get_bytes_read()" because we don't actually track that,
#and it's probably less relevant.
sub get_buffer_position {
    my ($self) = @_;

    return pos ${ $self->{'_buffer_sr'} };
}

# The die is trapped in _run which causes it to exit the loop there
sub stop {
    my ($self) = @_;

    die Cpanel::StringFunc::LineIterator::InProgress::_STOP->new();
}

#----------------------------------------------------------------------

package Cpanel::StringFunc::LineIterator::InProgress::_STOP;

sub new {
    my ($class) = @_;

    my $scalar;
    my $self = \$scalar;
    return bless $self, $class;
}

1;
