package Cpanel::Gzip::Config;

# cpanel - Cpanel/Gzip/Config.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadCpConf ();
use Cpanel::Binaries           ();

our $MAX_GZIP_HEADER_SIZE = 4096;

my @CONFIG_KEYS = qw(
  gzip_compression_level
  gzip_pigz_block_size
  gzip_pigz_processes
);

sub load {
    my $class      = shift;
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my %config;

    # Read in relevant variables into the object.
    @config{@CONFIG_KEYS} = @{$cpconf_ref}{@CONFIG_KEYS};

    # -x is checked by users of Cpanel::Gzip::Config
    my $program_path = Cpanel::Binaries::path('pigz');

    my $rsyncable = 1;

    $config{'bin'}       = $program_path;
    $config{'rsyncable'} = $rsyncable;

    return bless \%config, $class;
}

sub command {
    my ($self) = @_;

    my $program = $self->{'bin'};
    my @args;

    push @args, "-$self->{'gzip_compression_level'}";

    # We always use pigz with a default of 1 process because it does
    # buffering better than gzip and allows control of the blocksize
    push @args, '--processes', ( $self->{'gzip_pigz_processes'} || 1 );
    push @args, '--blocksize', $self->{'gzip_pigz_block_size'};
    push @args, '--rsyncable' if $self->{'rsyncable'};

    return ( $program, @args );
}

sub read_size {
    my ($self) = @_;

    return $self->{'gzip_pigz_block_size'} ? ( $self->{'gzip_pigz_block_size'} * 1024 + $MAX_GZIP_HEADER_SIZE ) : ( 1024**2 * 4 + $MAX_GZIP_HEADER_SIZE );
}

sub exec {
    my ( $self,    @user_args ) = @_;
    my ( $program, @gzip_args ) = $self->command;

    return exec( $program, @gzip_args, @user_args );
}

1;
