package Cpanel::iContact::Class::Mail::SpammersDetected;

# cpanel - Cpanel/iContact/Class/Mail/SpammersDetected.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw( spammers action );

my @optional_args = qw( origin );

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args )
    );
}

1;

__END__

=pod

=head1 NAME

Cpanel::iContact::Class::Mail::SpammersDetected

=head1 DESCRIPTION

iContact class that handles messages sent when potential spam is detected via C<scripts/eximstats_spam_check>.

=head1 METHODS

This class implements methods required by the parent class.

=cut
