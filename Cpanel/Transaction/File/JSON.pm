package Cpanel::Transaction::File::JSON;

# cpanel - Cpanel/Transaction/File/JSON.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: Use this class for read/write operations ONLY.
#If you only need to read, then use JSONReader.
#----------------------------------------------------------------------

use strict;
use warnings;

use base qw(
  Cpanel::Transaction::File::Read::JSON
  Cpanel::Transaction::File::Base
);

use Try::Tiny;

use Cpanel::Autodie ();
use Cpanel::JSON    ();

sub save_or_die {
    my ( $self, @key_values ) = @_;

    return $self->_save_or_die(
        @key_values,
        write_cr => \&_writer,
    );
}

#NOTE: For now there is no save_canonical_and_close_or_die() method.
#Hopefully there will be very few needs for this “canonical” save,
#as it makes the JSON serialization slower.
#
sub save_canonical_or_die {
    my ($self) = @_;

    return $self->_save_or_die(
        write_cr => \&_writer_canonical,
    );
}

sub save_pretty_canonical_or_die {
    my ($self) = @_;

    return $self->_save_or_die(
        write_cr => \&_writer_pretty_canonical,
    );
}

sub _writer_pretty_canonical {
    my ($self) = @_;

    return Cpanel::Autodie::print(
        $self->{'_fh'},
        Cpanel::JSON::pretty_canonical_dump(
            ( 'SCALAR' eq ref $self->{'_data'} )
            ? ${ $self->{'_data'} }
            : $self->{'_data'}
        ),
    );
}

sub _writer_canonical {
    my ($self) = @_;

    return Cpanel::Autodie::print(
        $self->{'_fh'},
        Cpanel::JSON::canonical_dump(
            ( 'SCALAR' eq ref $self->{'_data'} )
            ? ${ $self->{'_data'} }
            : $self->{'_data'}
        ),
    );
}

sub _writer {
    my ($self) = @_;

    return Cpanel::Autodie::print(
        $self->{'_fh'},
        Cpanel::JSON::Dump(
            ( 'SCALAR' eq ref $self->{'_data'} )
            ? ${ $self->{'_data'} }
            : $self->{'_data'}
        ),
    );
}

1;
