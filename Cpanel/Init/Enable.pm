package Cpanel::Init::Enable;

# cpanel - Cpanel/Init/Enable.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::Init::Factory;

sub factory ($self) {
    return Cpanel::Init::Factory->new( { 'name_space' => 'Cpanel::Init::Enable' } )->factory;
}

1;

__END__

=head1 NAME

Cpanel::Init::Enable - [Master sysV initscript control]

=head1 SYNOPSIS

    use Cpanel::Init::Enable;

    my $enabler = Cpanel::Init::Enable->new->factory();

    $enabler->collect_enable('service');
    $enabler->enable();

    $enabler->collect_disable('service');
    $enabler->disable();

=head1 DESCRIPTION

    Cpanel::Init::Enable builds a new enabler object. Enabler objects enabler or disable system
    V initscripts on the cPanel supported operating systems.

=head1 INTERFACE

=head2 Methods

=over 4

=item new

Argument list: none

This method instantiates the new object.

=item factory

This method returns an enabler subclass that is specific to the operating system.

=back
