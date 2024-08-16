package Cpanel::Transaction::File::Storable;

# cpanel - Cpanel/Transaction/File/Storable.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Cpanel::Transaction::File::Base';

use Cpanel::Exception    ();
use Cpanel::SafeStorable ();

sub _init_data {
    my ($self) = @_;

    return \undef if -z $self->{'_fh'};

    return Cpanel::SafeStorable::fd_retrieve( $self->{'_fh'} );
}

sub save_or_die {
    my ($self) = @_;

    return $self->_save_or_die(
        write_cr => \&_writer,
    );
}

sub _writer {
    my ($self) = @_;

    my $ok = Cpanel::SafeStorable::nstore_fd( $self->{'_data'}, $self->{'_fh'} );
    if ( !defined $ok ) {
        die Cpanel::Exception->create( "The system failed to save a [asis,Storable] file because of an error: [_1]", [$!] );
    }

    return $ok;
}

1;
