
# cpanel - Cpanel/RPM/Versions/File/YAML.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::RPM::Versions::File::YAML;

use strict;
use warnings;

use YAML::Syck ();

BEGIN {
    $YAML::Syck::LoadBlessed = 0;
    $YAML::Syck::SortKeys    = 1;
}

sub supported_file_format {
    my ($self) = @_;

    my $supported_file_format = 2;
    return $supported_file_format;
}

sub new {
    my ( $class, $args ) = @_;

    my $self = $class->init($args);

    bless $self, $class;

    $self->_loadfile();

    return $self;
}

sub init {
    my ( $class, $args ) = @_;

    my $self = {
        yaml_file => $args->{'file'},
    };

    return $self;
}

sub _loadfile {

    # This will need to be made more efficient later
    my ($self) = @_;

    my $file = $self->yaml_file();

    if ( !-e $file || -z _ ) {
        $self->{'data'} = {};
        return 0;
    }

    eval { $self->{'data'} = YAML::Syck::LoadFile($file) };

    if ($@) {
        die "Unable to load $file: $@";
    }

    if ( !exists $self->{'data'}->{'file_format'}{'version'} || $self->{'data'}->{'file_format'}{'version'} != $self->supported_file_format() ) {
        die( 'Incorrect file format version in ' . $file );
    }

    return scalar keys %{ $self->{'data'} };
}

sub yaml_file {
    my ($self) = @_;
    return $self->{'yaml_file'};
}

sub fetch {
    my ( $self, $args ) = @_;

    return if ( !keys %{ $self->{'data'} } );

    my $section = $args->{'section'};
    my $key     = $args->{'key'};

    if ($key) {
        return $self->{'data'}->{$section}->{$key};
    }
    else {
        return $self->{'data'}->{$section} || {};
    }
}

sub set {
    my ( $self, $args ) = @_;
    my $section = $args->{'section'};
    my $key     = $args->{'key'};
    my $value   = $args->{'value'};

    if ( ref $key eq 'ARRAY' ) {
        $self->{'data'}->{$section} = {} if ( ref $self->{'data'}->{$section} ne 'HASH' );
        _build_hash( $key, $self->{'data'}->{$section}, $value );

        return $self->{'data'}->{$section};
    }

    return $self->{'data'}->{$section}->{$key} = $value;
}

sub delete {
    my ( $self, $args ) = @_;

    return if ( !keys %{ $self->{'data'} } );

    my $section = $args->{'section'};
    my $key     = $args->{'key'};

    if ( ref $key eq 'ARRAY' ) {
        _delete_hash( $key, $self->{'data'}->{$section} );
        return;
    }

    return delete $self->{'data'}->{$section}->{$key};
}

sub visit_section {
    my ( $self, $section, $coderef ) = @_;
    foreach my $key ( keys %{ $self->{'data'}->{$section} } ) {
        $coderef->( $key, $self->{'data'}->{$section}->{$key} );
    }
}

sub visit_all {
    my ( $self, $coderef ) = @_;
    foreach my $section ( keys %{ $self->{'data'} } ) {
        foreach my $key ( keys %{ $self->{'data'}->{$section} } ) {
            $coderef->( $section, $key, $self->{'data'}->{$section}->{$key} );
        }
    }
}

sub save {
    my ($self) = @_;

    if ( !%{ $self->{'data'} } ) {
        return;
    }

    if ( !exists $self->{'data'}{'file_format'} ) {
        $self->{'data'}{'file_format'}{'version'} = $self->supported_file_format();
    }

    return YAML::Syck::DumpFile( $self->yaml_file(), $self->{'data'} );
}

sub _build_hash {
    my ( $keys, $hash_accumulator, $value ) = @_;
    while (@$keys) {
        my $key = shift @$keys;

        if ( ref $hash_accumulator->{$key} ne 'HASH' ) {
            $hash_accumulator->{$key} = @$keys ? {} : $value;
        }
        $hash_accumulator = $hash_accumulator->{$key};
    }

    return;
}

sub _delete_hash {
    my ( $keys, $hash_accumulator ) = @_;
    while (@$keys) {
        my $key = shift @$keys;

        if ( !@$keys ) {
            if ( ref $hash_accumulator eq 'HASH' ) {
                delete $hash_accumulator->{$key};
                return;
            }
        }
        $hash_accumulator = $hash_accumulator->{$key};
    }

    return;
}

1;
