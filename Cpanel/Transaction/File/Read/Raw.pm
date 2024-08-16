package Cpanel::Transaction::File::Read::Raw;

# cpanel - Cpanel/Transaction/File/Read/Raw.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadFile::ReadFast ();

my $READ_SIZE = 262140;

sub length {
    my ($self) = @_;

    return length ${ $self->{'_data'} };
}

#NOTE: A substr() that die()s when given a final argument could be useful here.

sub _init_data {
    my ($self) = @_;

    my $buffer = '';

    Cpanel::LoadFile::ReadFast::read_all_fast( $self->{'_fh'}, $buffer );

    return \$buffer;
}

1;
