package Cpanel::Themes::Serializer::JSON;

# cpanel - Cpanel/Themes/Serializer/JSON.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#  This file shows the format used by the cPanel Plugin files in the cPanel interface.
#
#

use strict;

use Cpanel::JSON                  ();
use Cpanel::Themes::Assets::Link  ();
use Cpanel::Themes::Assets::Group ();

use parent 'Cpanel::Themes::Serializer::Base';

sub _read {
    my ( $self, $path ) = @_;
    my $data = Cpanel::JSON::LoadFile($path);
    $data = [$data] if ref $data eq 'HASH';
    return $data;
}

sub build_data_tables {
    my ($self) = @_;

    my $raw_data = $self->load();
    my ( %links, %groups, @account_enhancements, @extras );

    foreach my $entry ( @{$raw_data} ) {
        $self->_pre_process_entry($entry);

        if ( $entry->{'type'} && $entry->{'type'} eq 'link' ) {
            $links{ $entry->{'id'} } = Cpanel::Themes::Assets::Link->new( %{$entry} );
        }
        elsif ( $entry->{'type'} && $entry->{'type'} eq 'group' ) {
            $groups{ $entry->{'id'} } = Cpanel::Themes::Assets::Group->new( %{$entry} );
        }
        elsif ( $entry->{'type'} && $entry->{'type'} eq 'account_enhancement' ) {
            push( @account_enhancements, $entry );
        }
        else {
            push @extras, $entry;
        }
    }

    $self->{'links'}                = [ values %links ];
    $self->{'groups'}               = [ values %groups ];
    $self->{'account_enhancements'} = \@account_enhancements;
    $self->{'extras'}               = \@extras;

    return 1;
}

# perform any necessary transformations on the entry object to make it suitable for
# usage
sub _pre_process_entry {
    my ( $self, $entry ) = @_;

    if ( exists $entry->{'icon'} ) {
        $entry->{'icon'} = $self->{'docroot'} . '/' . $entry->{'icon'};
    }

    return;
}

sub get_sources {
    my ($self) = @_;

    my @files;

    my $docroot = $self->{'docroot'};
    push @files, $docroot . '/install.json' if -e $docroot . '/install.json';
    push @files, $docroot . '/sitemap.json' if -e $docroot . '/sitemap.json';

    return @files;
}

sub get_items {
    my ($self) = @_;

    my $items = [];
    _process_items( $self->{'extras'}, $items );

    return $items;
}

sub _process_items {
    my ( $data_ref, $items ) = @_;

    if ( ref $data_ref eq 'ARRAY' ) {
        foreach my $i ( @{$data_ref} ) {
            if ( ref $i eq 'HASH' ) {
                _process_items( $i, $items );
            }
            elsif ( ref $i eq 'ARRAY' ) {
                _process_items( $i, $items );
            }
            else {
                push @{$items}, $i;
            }
        }
    }
    elsif ( ref $data_ref eq 'HASH' ) {
        push @{$items}, $data_ref;
        foreach my $k ( keys %{$data_ref} ) {
            if ( ref $data_ref->{$k} eq 'ARRAY' ) {
                _process_items( $data_ref->{$k}, $items );
            }
        }
    }
    else {
        push @{$items}, $data_ref;
    }

    return;
}

1;
