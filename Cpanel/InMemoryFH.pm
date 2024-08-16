package Cpanel::InMemoryFH;

# cpanel - Cpanel/InMemoryFH.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
# NOTE: If you are using any perl beyond 5.6, consider using open()
# on a scalar reference instead of using this module.
#----------------------------------------------------------------------

sub TIEHANDLE {
    my $class = shift;
    my $self  = bless {};
    $self->{'data'} = '';
    return $self;
}

sub WRITE {
    $_[0]->{'data'} .= $_[1];
    return length $_[1];
}

sub PRINT {
    $_[0]->{'data'} .= join( '', @_[ 1 .. $#_ ] );
    return 1;
}

sub PRINTF {
    $_[0]->{'data'} .= sprintf( $_[1], @_[ 2 .. $#_ ] );
    return 1;
}

sub READ {
    my $self   = shift;
    my $bufref = \$_[0];
    $$bufref = $self->{'data'};
    return length $self->{'data'};
}

sub READLINE {
    my $self = shift;

    my $endpoint;

    if ( length $/ ) {
        my $rs_index = index $self->{'data'}, $/;
        if ( $rs_index > -1 ) {
            $endpoint = length($/) + $rs_index;
        }
    }

    if ( !defined $endpoint ) {
        $endpoint = length $self->{'data'};
    }

    return substr( $self->{'data'}, 0, $endpoint, q{} );
}

sub EOF { return 1 }

sub SEEK {
    return length( $_[0]->{'data'} );
}

*TELL = *SEEK;

1;
