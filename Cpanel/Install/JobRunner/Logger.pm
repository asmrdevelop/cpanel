package Cpanel::Install::JobRunner::Logger;

# cpanel - Cpanel/Install/JobRunner/Logger.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Install::JobRunner::Logger

=head1 DESCRIPTION

Logger for L<Cpanel::Install::JobRunner> that abstracts over the
specific logger implementation.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Output::Container::MethodProvider );

use Cpanel::Output::Formatted::Terminal ();

#----------------------------------------------------------------------

=head1 METHODS

This module subclasses L<Cpanel::Output::Container::MethodProvider>;
see that module for this class’s inherited methods.

=head2 I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    my %data = (
        _logger => Cpanel::Output::Formatted::Terminal->new(),
    );

    return bless \%data, $class;
}

1;
