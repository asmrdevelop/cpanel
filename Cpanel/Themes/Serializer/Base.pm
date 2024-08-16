package Cpanel::Themes::Serializer::Base;

# cpanel - Cpanel/Themes/Serializer/Base.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Branding::Lite::Config ();

use Cpanel::Debug ();

=head1 SYNOPSIS

This object's responsibility is to represent a theme as it exists on disk and act as as interface for a theme

=head1 METHODS

=over

=item new( %OPTS )

Arguments (named)

    docroot     - The document root of the theme
    user        - a cPanel user (if omitted, integrated applications will be missing)

    OR

    spec_files  - An array of files to load with the specifications for the theme objects (in DynamicUI these are the dynamicui.conf files)
    config      - A file or hashref containing the theme's config hash

Returns back a Cpanel::Theme::Serializer::$type Object

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $docroot = $OPTS{'docroot'};
    my $user    = $OPTS{'user'};
    my $config  = $OPTS{'config'};
    my $sources;

    if ( defined $config && !ref $config && -e $config ) {

        # if $config is not a reference and exists on the file system
        $config = Cpanel::Branding::Lite::Config::load_theme_config_from_file($config);
    }
    elsif ( !defined $config && -e "${docroot}/config.json" ) {

        # if config isn't specified and one exists for the theme, load it.
        $config = Cpanel::Branding::Lite::Config::load_theme_config_from_file("${docroot}/config.json");
    }

    if ( exists $OPTS{'sources'} ) {
        $sources = $OPTS{'sources'};
        $sources = [$sources] unless ref $sources eq 'ARRAY';    # ensure it's in an array ref;
    }
    else {
        $sources = 0;                                            # special condition, means attempt to load after blessing
    }
    my $self = bless {
        'docroot' => $docroot,
        'config'  => $config,
        'sources' => $sources,
        'user'    => $user,
    }, $class;

    # if the spec_file is specified, enforce an array
    if ( !$sources ) {

        # If it is not specified, we'll try to determine what the correct listing is
        $self->{'sources'} = [ $self->get_sources() ];
    }

    # If we explictly pass in an empty sources
    # list we do not want to generate a warning.
    #
    # We should only warn when the system failed to load
    # them when we expected them
    if ( !exists $OPTS{'sources'} && scalar @{ $self->{'sources'} } == 0 ) {
        Cpanel::Debug::log_warn('No sources could be detected');
    }

    return $self;
}

# get an array ref of Cpanel::Themes::Assets::Links objects containing each link in a theme
sub links {
    my ($self) = @_;

    if ( !exists $self->{'links'} || ref $self->{'links'} ne 'ARRAY' ) {
        $self->build_data_tables;
    }

    return $self->{'links'};
}

# get an array ref of Cpanel::Themes::Assets::Group objects containing each link in a theme
sub groups {
    my ($self) = @_;

    if ( !exists $self->{'groups'} || ref $self->{'groups'} ne 'ARRAY' ) {
        $self->build_data_tables;
    }

    return $self->{'groups'};
}

# get an array ref of defined account enhancements
sub account_enhancements {
    my ($self) = @_;

    if ( !exists $self->{'account_enhancements'} || ref $self->{'account_enhancements'} ne 'ARRAY' ) {
        $self->build_data_tables;
    }

    return $self->{'account_enhancements'};
}

# Iterate through all the sources entries
# load the data from them
# merge into single array
# return reference to array
sub load {
    my ($self) = @_;

    my @full_listing;

    #NB: Depending on the subclass, $source here might be either
    #a reference or a scalar. It shouldn’t matter, though, since
    #_read() is in the subclass and can/will work with whatever
    #get_sources() returned earlier.
    #
    foreach my $source ( @{ $self->{'sources'} } ) {
        my $entries_from_source = $self->_read($source);
        push @full_listing, @{$entries_from_source};
    }

    return \@full_listing;
}

# Return the config for the theme in question ( can be null )
sub config {
    my ($self) = @_;
    return $self->{'config'};
}

=back

=cut

1;
