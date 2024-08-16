package Cpanel::NAT::Object;

# cpanel - Cpanel/NAT/Object.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug            ();
use Cpanel::Validate::IP::v4 ();

our $NAT_FILE = '/var/cpanel/cpnat';

sub new {
    my ( $class, $file ) = @_;

    my $self = {
        'cpnat_file'    => $file || $NAT_FILE,
        'cpnat_data'    => {},
        'file_read'     => 0,
        'only_local_ip' => [],
        'dups'          => {},
    };

    bless $self, $class;
    $self->load_file();

    return $self;
}

sub load_file {
    my ($self) = @_;

    $self->{'file_read'}  = 0;
    $self->{'cpnat_data'} = {};

    if ( !-e $self->{'cpnat_file'} || !-r _ || -z _ ) {
        return;
    }

    my $nat_data;
    {
        local $/;
        open my $fh, '<', $self->{'cpnat_file'} or die "Failed to open “$self->{'cpnat_file'}”: $!";

        $nat_data = <$fh>;
        close $fh;
    }

    $self->{'nat_data'}   = $nat_data;
    $self->{'cpnat_data'} = $self->_parse_nat_file($nat_data);
    $self->{'file_read'}  = 1;
    return 1 if %{ $self->{'cpnat_data'} };

    return;
}

sub enabled {
    my ($self) = @_;
    return $self->{'file_read'} ? 1 : 0;
}

sub ordered_list {
    my ($self) = @_;
    return ( $self->{'cpnat_ordered'} ||= $self->_create_ordered_list( $self->{'nat_data'} ) );
}

# $_[0] = $self
# $_[1] = $local_ip
sub get_public_ip {
    return $_[1] if !$_[1] || !$_[0]->{'file_read'} || !$_[0]->{'cpnat_data'}->{ $_[1] };
    return $_[0]->_get_public_ip( $_[1] );
}

sub get_all_public_ips {
    my ($self) = @_;
    return [ sort values %{ $self->{cpnat_data} } ];
}

sub get_public_ip_raw {
    my ( $self, $local_ip ) = @_;

    return 'FILE NOT READ'    if !$self->{'file_read'};
    return 'INVALID LOCAL IP' if !$self->{'cpnat_data'}->{$local_ip} && !$self->_find_ip($local_ip) && !exists $self->{'dups'}->{$local_ip};

    return $self->_get_public_ip($local_ip) || $self->{'dups'}->{$local_ip} || '';
}

sub _find_ip {
    my ( $self, $ip ) = @_;

    my $found = grep { $_ eq $ip } @{ $self->{'only_local_ip'} };
    return $ip if $found;
    return;
}

sub _get_public_ip {
    my ( $self, $local_ip ) = @_;
    my $public_ip = $self->{'cpnat_data'}->{$local_ip};
    return $public_ip;
}

sub get_local_ip {
    my ( $self, $public_ip ) = @_;

    return $public_ip unless $public_ip;
    return $public_ip if !$self->{'file_read'};

    $self->{'_public_to_local'} ||= { reverse %{ $self->{'cpnat_data'} } };

    return $self->{'_public_to_local'}{$public_ip} || $public_ip;
}

sub _parse_nat_file {
    my ( $self, $nat_data ) = @_;

    return if !$nat_data;

    my $cpnat_hash    = {};
    my @file          = split /\n/, $nat_data;
    my $only_local_ip = $self->{'only_local_ip'};
    foreach my $line (@file) {
        my ( $local, $public ) = split /\s+/, $line;
        if ( !$public ) {
            push @$only_local_ip, $local;
            next;
        }
        if (   !Cpanel::Validate::IP::v4::is_valid_ipv4($local)
            && !Cpanel::Validate::IP::v4::is_valid_ipv4($public) ) {

            Cpanel::Debug::log_warn( 'Invalid line in cpnat file: ' . $line );
            next;
        }
        if ( !grep { $public && $public eq $_ } values %{$cpnat_hash} ) {
            $cpnat_hash->{$local} = $public;
        }
        else {
            $self->{'dups'}->{$local} = $public;
        }
    }

    return $cpnat_hash;
}

sub _create_ordered_list {
    my ( $self, $nat_data ) = @_;

    return if !$nat_data;

    my $cpnat_array = [];
    my $group_hash  = {};
    my $order       = [];
    my @file        = split /\n/, $nat_data;
    foreach my $line (@file) {
        my ( $local, $public ) = split /\s+/, $line;
        my $key = $public || $local;

        $public ||= '';

        push @$order,                  $key if !$group_hash->{$key};
        push @{ $group_hash->{$key} }, [ $local, $public ];
    }

    foreach my $key (@$order) {
        if ( scalar @{ $group_hash->{$key} } == 1 ) {
            push @$cpnat_array, pop @{ $group_hash->{$key} };
        }
        else {
            push @$cpnat_array, $group_hash->{$key};
        }
    }

    return $cpnat_array;
}

1;
