
# cpanel - Cpanel/ImagePrep/Check.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Check;

use parent 'Cpanel::ImagePrep::Task';

use cPstrict;

=head1 NAME

Cpanel::ImagePrep::Check

=head1 SYNOPSIS (subclass)

  use parent 'Cpanel::ImagePrep::Check';

  sub _check($self) {
      if (problem) {
          die ...........;
      }
      return;
  }

  sub _description($self) {
      ...
  }

=head1 METHODS

=head2 Main interface is similar to C<Cpanel::ImagePrep::Task>

See C<Cpanel::ImagePrep::Task> for the methods that are available.
Note: C<pre> and C<post> are unused for Check objects.

The rest below is specific to C<Cpanel::ImagePrep::Check>.

=head2 check()

Subclass must provide the _check() method as an implementation for check().

No changes should be made on disk. This is just a check to see whether the server
is in a state where it would make sense to proceed.

The implementation in the subclass must die on failure and return anything
(e.g., an empty list) on success. A C<Check> failure will result in the entire
operation being aborted and an early exit, as opposed to C<Task> failure, from
which the process will be allowed to continue.

=cut

sub check ($self) {
    return $self->_check;
}

sub _check ($self) {
    die 'must implement _check in subclass';
}

sub _pre ($self) {
    return $self->PRE_POST_NOT_APPLICABLE;
}

sub _post ($self) {
    return $self->PRE_POST_NOT_APPLICABLE;
}

sub _type ($self) {
    return 'non-repair only';
}

sub _deps ($self) {
    return;
}

1;
