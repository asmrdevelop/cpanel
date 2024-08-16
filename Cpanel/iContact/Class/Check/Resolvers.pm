package Cpanel::iContact::Class::Check::Resolvers;

# cpanel - Cpanel/iContact/Class/Check/Resolvers.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Locale ();

use parent qw(
  Cpanel::iContact::Class
);

my $WHM_SETUP_RESOLVERS = 'scripts2/setupresolvconf';

my @args = qw(
  resolver_state
  overall_state
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        'whm_setup_resolvers_url' => $self->_whm_setup_resolvers_url(),

        #XXX: This boilerplate defeats the whole point of having a _template_args()
        #method that white-lists parameters that go into the template.
        #It was caught in review but left in out of a desire to avoid re-testing.
        #Please do NOT follow this pattern in the future unless there is a clear,
        #documented reason--or, maybe we should just throw all of the _opts into
        #the template and not worry about it? (Seriously.)
        map { $_ => $self->{'_opts'}{$_} } (@args),
    );

    return %template_args;
}

sub _whm_setup_resolvers_url {
    my ($self) = @_;
    return $self->assemble_whm_url($WHM_SETUP_RESOLVERS);

}

1;
