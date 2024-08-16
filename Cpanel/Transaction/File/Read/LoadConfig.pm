package Cpanel::Transaction::File::Read::LoadConfig;

# cpanel - Cpanel/Transaction/File/Read/LoadConfig.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use Cpanel::HiRes              ();

my $DEFAULT_DELIMITER = ':';

sub _init_data {
    my ( $self, %opts ) = @_;

    $self->{'_delimiter'} = $opts{'delimiter'} || $DEFAULT_DELIMITER;

    my $fh = $self->{'_fh'};
    my ( $homedir, $cache_dir ) = Cpanel::Config::LoadConfig::get_homedir_and_cache_dir();
    my $cache_file = Cpanel::Config::LoadConfig::get_cache_file(
        %opts,
        'file'      => $opts{'path'},
        'cache_dir' => $cache_dir,
        'delimiter' => $opts{'_delimiter'},
    );

    my ( $cache_valid, $ref ) = Cpanel::Config::LoadConfig::load_from_cache_if_valid(
        %opts,
        'file'          => $opts{'path'},
        'cache_file'    => $cache_file,
        'filesys_mtime' => ( Cpanel::HiRes::stat($fh) )[9],
    );

    return $ref if $cache_valid;

    #NOTE: This would ideally throw errors when it fails to read.
    return Cpanel::Config::LoadConfig::parse_from_filehandle(
        $self->{'_fh'},
        delimiter => $self->{'_delimiter'},
        %opts
    );
}

#This checks has_entry() first so we can accommodate undef more easily.
sub get_entry {
    my $data = $_[0]->get_data();
    return ( ref $data ne 'HASH' || !exists $data->{ $_[1] } ) ? undef : $data->{ $_[1] };
}

sub has_entry {
    my ( $self, $key ) = @_;

    my $data = $self->get_data();

    if ( $data && ( ref $data eq 'HASH' ) ) {
        return exists $data->{$key} ? 1 : 0;
    }

    return undef;
}

1;
