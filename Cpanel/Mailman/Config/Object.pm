package Cpanel::Mailman::Config::Object;

# cpanel - Cpanel/Mailman/Config/Object.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::JSON ();
use JSON::XS     ();

sub new {
    my ( $class, $config_file ) = @_;

    my $self = Cpanel::JSON::LoadFile($config_file);

    bless $self, $class;

    # Workaround JSON::XS::Bool bug by forced deref
    foreach my $val ( values %{$self} ) {
        if ( JSON::XS::is_bool($val) ) {
            $val = $$val;
        }
    }

    return $self;
}

sub is_for_a_private_list {
    my ($self) = @_;

    return 0 if !$self->{'archive_private'};
    return 0 if $self->{'advertised'};

    my $subscribe_policy = $self->{'subscribe_policy'};
    return 0 if ( $subscribe_policy != 2 && $subscribe_policy != 3 );

    return 1;
}

1;
