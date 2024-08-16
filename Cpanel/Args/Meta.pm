package Cpanel::Args::Meta;

# cpanel - Cpanel/Args/Meta.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

my $PACKAGE = __PACKAGE__;

sub new {
    my ( $class, $args_hr ) = @_;

    my $self = { map { ( "_$_" => $args_hr->{$_} ) } keys %$args_hr };
    bless $self, $class;

    my @missing_parameters = grep { !defined $args_hr->{$_} } ( $self->_required_args() );
    if (@missing_parameters) {
        die Cpanel::Exception::create( 'MissingParameter', 'You are missing the following [numerate,_1,parameter,parameters]: [join, ,_2]', [ scalar @missing_parameters, \@missing_parameters ] );
    }

    return $self;
}

sub _required_args {
    die "Do not instantiate base class $PACKAGE directly.";
}

1;
