package Cpanel::Transaction::File::LoadConfig;

# cpanel - Cpanel/Transaction/File/LoadConfig.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# XXX: JSON is a preferred format to LoadConfig.
#   - Please do not create any new LoadConfig datastores.
#   - Consider migrating an old datastore to JSON rather than creating
#     a new call into this module.
#
# NOTE: Use this class for read/write operations ONLY.
# If you only need to read, then use LoadConfigReader.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(
  Cpanel::Transaction::File::Read::LoadConfig
  Cpanel::Transaction::File::Base
);

use Cpanel::Config::FlushConfig ();
use Cpanel::Config::LoadConfig  ();
use Cpanel::Autodie             ();

my $PACKAGE = __PACKAGE__;

sub set_data {
    my ( $self, $data ) = @_;
    my $old_data = $self->_get_data();
    %$old_data = %$data;
    return 1;
}

sub remove_entry {
    my ( $self, $key ) = @_;
    return delete $self->_get_data()->{$key};
}

sub set_entry {
    my ( $self, $key, $value ) = @_;

    die "LoadConfig values must be scalar!" if ref $value;

    return $self->_get_data()->{$key} = $value;
}

sub rename_entry {
    my ( $self, $key, $new_key ) = @_;
    return $self->set_entry( $new_key, $self->remove_entry($key) );
}

#opts are:
#   do_sort - Sort the file by key.
#   header - A header to write out at the beginning of the file.
#       NOTE: Be sure that the header is comment-escaped so the
#       parser will ignore it!
sub save_or_die {
    my ( $self, %opts ) = @_;

    my $data_ref = $self->get_data();    # read the data before we swap the fh

    return $self->_save_or_die(
        %opts,
        write_cr => sub {
            my ($self) = @_;

            my $fh = $self->{'_fh'};
            my ( $homedir, $cache_dir ) = Cpanel::Config::LoadConfig::get_homedir_and_cache_dir();
            my $cache_file = Cpanel::Config::LoadConfig::get_cache_file(
                'file'      => $self->{'_path'},
                'cache_dir' => $cache_dir,
                'delimiter' => $self->{'_delimiter'},
            );

            my $ret = Cpanel::Autodie::print(
                $fh,
                ${
                    Cpanel::Config::FlushConfig::serialize(
                        $data_ref,
                        delimiter          => $self->{'_delimiter'},
                        do_sort            => $opts{'do_sort'},
                        header             => $opts{'header'},
                        allow_array_values => $opts{'allow_array_values'},
                    )
                },
            );

            if ($cache_file) {

                # Write cache after writing the file in case
                # writing the file fails
                Cpanel::Config::LoadConfig::write_cache(
                    'cache_dir'  => $cache_dir,
                    'cache_file' => $cache_file,
                    'homedir'    => $homedir,
                    'is_root'    => $> == 0 ? 1 : 0,
                    'data'       => $self->get_data(),
                );
            }

            return $ret;
        },
    );
}

1;
