package Cpanel::Transaction::File::Read::JSON;

# cpanel - Cpanel/Transaction/File/Read/JSON.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadFile::ReadFast ();
use Cpanel::JSON               ();

my $READ_SIZE = 262140;

sub _init_data {
    my ( $self, %opts ) = @_;

    return \undef if -z $self->{'_fh'};

    my $func = \&Cpanel::JSON::Load;
    my $txt  = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $self->{'_fh'}, $txt );

    my $load = $func->($txt);

    return ref($load) ? $load : \$load;
}

1;
