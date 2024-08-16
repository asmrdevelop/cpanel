package Cpanel::Transaction::File::BaseReader;

# cpanel - Cpanel/Transaction/File/BaseReader.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: If you need to edit the datastore, use the "Base" class.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Autodie   qw(open exists stat close);
use Cpanel::Exception ();

my $PACKAGE = __PACKAGE__;

sub new {
    my ( $class, %opts ) = @_;

    #Implementor error
    die "No file!" if !length $opts{'path'};

    my $path = $opts{'path'};

    my $self = bless {}, $class;

    my $data;

    #XXX: This should probably die() if the file doesn’t exist.
    if ( !Cpanel::Autodie::exists($path) ) {
        $data = \undef;
    }
    else {
        Cpanel::Autodie::open( my $read_fh, '<', $path );

        $self->{'_original_mtime'} = ( Cpanel::Autodie::stat($read_fh) )[9];
        local $self->{'_fh'} = $read_fh;

        $data = $self->_init_data_with_catch(%opts);

        Cpanel::Autodie::close( $read_fh, $path );
    }

    return bless { _data => $data, _did_init_data => 1 }, $class;
}

sub _init_data_with_catch {
    my ( $self, %opts ) = @_;

    my $data;
    local $@;

    # Eval used for tight read loops
    eval { $data = $self->_init_data(%opts); 1 } or do {
        die Cpanel::Exception->create(
            'The system failed to load and to parse the file “[_1]” because of an error: [_2]',
            [ $opts{'path'}, Cpanel::Exception::get_string($@) ]
        );
    };

    return $data;
}

sub _init_data {
    die "Do not instantiate $PACKAGE directly; use a subclass instead.";
}

sub _get_data {
    if ( !$_[0]->{'_did_init_data'} ) {
        $_[0]->{'_data'}          = $_[0]->_init_data_with_catch( %{ $_[0]->{'_opts'} } );
        $_[0]->{'_did_init_data'} = 1;
    }

    return $_[0]->{'_data'};
}

sub get_original_mtime {
    return $_[0]->{'_original_mtime'};
}

sub path_is_newer {

    #In case of time-warp, return 1.
    #
    return ( Cpanel::Autodie::stat( $_[0]->{'_path'} ) )[9] != $_[0]->{'_original_mtime'} ? 1 : 0;
}

sub get_fh {
    return $_[0]->{'_fh'};
}

sub get_mtime {
    return ( stat( $_[0]->{'_fh'} ) )[9];
}

no warnings 'once';
*get_data = \&_get_data;

1;
