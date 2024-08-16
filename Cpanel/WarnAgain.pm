package Cpanel::WarnAgain;

# cpanel - Cpanel/WarnAgain.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WarnAgain - Catch warnings without disturbing other code.

=head1 SYNOPSIS

    my @w1;
    $SIG{'__WARN__'} = sub { push @w1, @_ };

    my @w2;
    {
        my $catcher = Cpanel::WarnAgain->new_to_array( \@w2 );

        warn "Looks weird";
    }

    warn "not sure";

At the end of the above, C<@w1> will contain both warn messages, while C<@w2>
will only contain the first.

=head1 DESCRIPTION

This little module simplifies the task of catching C<$SIG{__WARN__}>
without disturbing any other code that may also expect to receive warnings.

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new_to_array( \@DESTINATION )

Creates an instance of I<CLASS> that, while it lives, pushes
each warning to @DESTINATION.

=cut

sub new_to_array ( $class, $destination ) {
    my $existing_handler = $SIG{'__WARN__'};

    my $cb = sub { push @$destination, @_ };

    $SIG{'__WARN__'} = sub {    ## no critic qw(Localized)
        $existing_handler->(@_) if $existing_handler;
        $cb->(@_);
    };

    return bless [ $existing_handler, $cb ], $class;
}

sub DESTROY ($self) {
    $SIG{'__WARN__'} = $self->[0];    ## no critic qw(Localized)

    return;
}

1;
