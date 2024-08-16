package Cpanel::Init;

# cpanel - Cpanel/Init.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::FileUtils::Copy ();
use Cpanel::Init::Factory   ();

around 'new' => sub {
    my $orig = shift;
    my ( $class, @args ) = @_;
    my $self = $class->$orig(@args);

    # Install the user modifiable file if not present.
    if ( !-e '/var/cpanel/cpservices.yaml' ) {
        Cpanel::FileUtils::Copy::safecopy( '/usr/local/cpanel/etc/init/scripts/cpservices.yaml', '/var/cpanel/cpservices.yaml' );
    }

    return $self->factory();
};

sub factory ($self) {
    return Cpanel::Init::Factory->new( { 'name_space' => 'Cpanel::Init' } )->factory;
}

1;
