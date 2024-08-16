package Cpanel::WrapOutputFH;

# cpanel - Cpanel/WrapOutputFH.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
# NOTE: If you are using any perl beyond 5.6, consider using open()
# on a scalar reference instead of using this module.
#----------------------------------------------------------------------

sub TIEHANDLE {
    my ( $class, %opts ) = @_;
    my $self = bless {%opts}, $class;
    return $self;
}

sub WRITE {    ## no critic qw(RequireArgUnpacking)
    return $_[0]->{'output_obj'}->message( 'out', { 'msg' => [ $_[1] ] } );
}

sub PRINT {    ## no critic qw(RequireArgUnpacking)
    return $_[0]->{'output_obj'}->message( 'out', { 'msg' => [ @_[ 1 .. $#_ ] ] } );
}

sub PRINTF {    ## no critic qw(RequireArgUnpacking)
    return $_[0]->{'output_obj'}->message( 'out', { 'msg' => [ sprintf( $_[1], @_[ 2 .. $#_ ] ) ] } );
}

1;
