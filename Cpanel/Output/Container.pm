package Cpanel::Output::Container;

# cpanel - Cpanel/Output/Container.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Output::Container

=head1 DESCRIPTION

=head2 Avoid in New Code?

B<NOTE:> This class may be obsolete since L<Cpanel::Output> itself now
 implements C<create_indent_guard()>.

=head2 Legacy Description

This is a base class for modules that contain a L<Cpanel::Output> instance
but expose C<create_log_level_indent()> rather than separate controls to
increase/decrease the log indent level.

Subclasses of this class must store the Cpanel::Output object in the
C<_logger> internal property.

=cut

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->create_log_level_indent()

Increases the log level indent and returns an object that, when
C<DESTROY()>ed, will undo the indent.

(Void context is pointless for this function and thus prompts an exception.)

=cut

sub create_log_level_indent ($self) {
    return $self->{'_logger'}->create_indent_guard();
}

=head2 $obj = I<OBJ>->create_indent_guard()

An alias for C<create_log_level_indent()>. It’s here to match
L<Cpanel::Output>’s interface.

=cut

*create_indent_guard = *create_log_level_indent;

1;
