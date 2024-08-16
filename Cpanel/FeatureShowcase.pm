package Cpanel::FeatureShowcase;

# cpanel - Cpanel/FeatureShowcase.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Use ConfigObj to showcase particular features/software and mark them via
#  an interface

our $VERSION = '1.0';

use strict;

our $SOURCE_API                 = "API";
our $SOURCE_GUI                 = "GUI";
our $SOURCE_CLI                 = "CLI";
our $SOURCE_CPANEL_MAINTENTANCE = 'cpanel_maintenance';

use Cpanel::Config::ConfigObj::Filter             ();
use Cpanel::Config::ConfigObj::Filter::FilterList ();
use Cpanel::FeatureShowcase::Display              ();
use Cpanel::Debug                                 ();
use Cpanel::Config::LoadConfig                    ();
use Cpanel::LoadModule                            ();

use parent qw(Cpanel::Config::ConfigObj);

############## FUNCTIONS ##############

*is_not_visible = \&Cpanel::FeatureShowcase::Display::is_not_visible;

sub showcased_feature_directory {
    return showcased_feature_base_directory() . '/features';
}

sub showcased_feature_base_directory {
    return '/var/cpanel/activate';
}

sub create_showcased_feature_directory {

    # Case 60174: discovered subtle race condition: if going through WHM gsw,
    #   an object of this class might be instantiated following actions which
    #   unlink activate/ but before recreating it...resulting is an fatal error
    #   during the redirect
    my $base_dir = Cpanel::FeatureShowcase::showcased_feature_base_directory();

    if ( !-d $base_dir ) {
        if ( !$INC{'Cpanel/SafeDir/MK.pm'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        }
        if ( !Cpanel::SafeDir::MK::safemkdir( $base_dir, 0700 ) ) {
            Cpanel::Debug::log_warn("Cannot create base directory for showcased features: $base_dir.");
            return;
        }
    }

    my $features_directory = Cpanel::FeatureShowcase::showcased_feature_directory();

    if ( -l $features_directory ) {
        Cpanel::Debug::log_warn("Unsafe operation. Features directory is symbolic link.");
        return;
    }

    if ( !-d $features_directory ) {
        if ( !$INC{'Cpanel/SafeDir/MK.pm'} ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        }
        if ( !Cpanel::SafeDir::MK::safemkdir( $features_directory, 0700 ) ) {
            Cpanel::Debug::log_warn("Cannot create directory for showcased features: $features_directory.");
            return;
        }
    }
    return $features_directory;
}

############## METHODS ##############
sub new {
    my ($class) = shift;
    my $self = $class->SUPER::new(@_);

    $self->create_showcased_feature_directory() || return;
    $self->refine_driver_list_to_showcased();

    return $self;
}

# filter all drivers down to just those that are a part of the showcase and
#  have a valid license (if applicable)
sub refine_driver_list_to_showcased {
    my ($self)     = @_;
    my $filterList = $self->_default_filter_list();
    my $refined    = $filterList->to_hash() || {};
    $self->_set_driver_objects($refined);
    return $refined;
}

sub _loadconfig_list_or_die {
    my (@args) = @_;

    my ( $vals_hr, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig(@args);
    die $err if !$vals_hr;

    return %$vals_hr;
}

# Determines when to display feature showcase page.
sub get_feature_showcase_names {
    my ($self)             = @_;
    my @features           = ();
    my $features_directory = Cpanel::FeatureShowcase::showcased_feature_directory();
    my $drivers            = $self->_get_drivers();
    foreach ( keys %{$drivers} ) {
        if ( -f $features_directory . "/$_" ) {
            my %config_values = _loadconfig_list_or_die( $features_directory . "/$_" );
            my $interface     = $config_values{'INTERFACE'};
            if ( $interface ne $SOURCE_GUI ) {
                push @features, $_;
            }
        }
        else {
            push @features, $_;
        }
    }

    return grep _is_precheck_passed( $self, $_ ), @features;
}

# get a list of feature (driver) names
# that have not been presented to
# users as a showcased feature
# TODO this should probably be a filter
sub get_new_feature_showcase_names {
    my ($self)             = @_;
    my @features           = ();
    my $features_directory = Cpanel::FeatureShowcase::showcased_feature_directory();

    my $drivers = $self->_get_drivers();
    foreach ( keys %{$drivers} ) {
        unless ( -e "$features_directory/$_" ) {
            push @features, $_;
        }
    }

    return grep _is_precheck_passed( $self, $_ ), @features;
}

sub _is_precheck_passed {
    my ( $self, $k ) = @_;
    my $driver = $self->get_driver($k);

    return ( !$driver->can('precheck') || $driver->precheck() );
}

# build the data structure used by the showcase features page
# to display showcased features
# TODO this should probably be a filter
sub get_new_feature_showcase {
    my ($self) = @_;

    my @features = $self->get_new_feature_showcase_names();
    my %feature_data;
    my %recommended_feature_data;
    my %spotlight_feature_data;

    foreach my $feature_name (@features) {
        my $driver = $self->get_driver($feature_name);
        if ($driver) {
            my $meta                 = $driver->meta();
            my $is_recommended       = $meta->is_recommended();
            my $is_spotlight_feature = $meta->is_spotlight_feature();
            my %feature_details;
            $feature_details{driver}            = $feature_name;
            $feature_details{blurb}             = $meta->abstract();
            $feature_details{blurb_html}        = _html( $meta->abstract() );
            $feature_details{helpurl}           = $meta->url();
            $feature_details{name}              = $meta->name();
            $feature_details{defaultvalue}      = $driver->check() // $driver->set_default();
            $feature_details{recommended}       = $is_recommended;
            $feature_details{spotlight_feature} = $is_spotlight_feature;
            $feature_details{forced}            = $meta->forced();
            $feature_details{readonly}          = $meta->readonly();

            if ($is_recommended) {
                $recommended_feature_data{$feature_name} = \%feature_details;
            }
            elsif ($is_spotlight_feature) {
                $spotlight_feature_data{$feature_name} = \%feature_details;
            }
            else {
                $feature_data{$feature_name} = \%feature_details;
            }
        }
    }
    return \%spotlight_feature_data, \%recommended_feature_data, \%feature_data;
}

# build the data structure used by the showcase features page
# to display features that are configured through CLI & Remote API
# TODO this should probably be a filter
sub get_modified_feature_showcase {
    my ($self) = @_;
    my %feature_data;

    my $features_directory = Cpanel::FeatureShowcase::showcased_feature_directory();
    my $drivers            = $self->_get_drivers();
    if ( -d $features_directory ) {
        opendir( my $dh, $features_directory ) || do {
            Cpanel::Debug::log_warn("Cannot open directory: $features_directory.");
            return;
        };
        my @files = readdir($dh);
        closedir($dh);

        # files should be name the same and the driver reference name (from meta->name('driver'))
        foreach my $file (@files) {
            next if $file !~ m/^[a-zA-Z0-9]/;
            if ( exists $drivers->{$file} ) {
                my %config_values = _loadconfig_list_or_die( $features_directory . "/$file" );
                my $interface     = $config_values{'INTERFACE'};
                if ( $interface ne $SOURCE_GUI ) {

                    my $driver = $self->get_driver($file);
                    my $meta   = $driver->meta();
                    my %feature_details;
                    $feature_details{driver}            = $file;
                    $feature_details{blurb}             = $meta->abstract();
                    $feature_details{blurb_html}        = _html( $meta->abstract() );
                    $feature_details{helpurl}           = $meta->url();
                    $feature_details{name}              = $meta->name();
                    $feature_details{defaultvalue}      = $driver->check() // $driver->set_default();
                    $feature_details{recommended}       = $meta->is_recommended();
                    $feature_details{spotlight_feature} = $meta->is_spotlight_feature();
                    $feature_details{forced}            = $meta->forced();
                    $feature_details{readonly}          = $meta->readonly();
                    $feature_data{$file}                = \%feature_details;
                }
            }
        }
    }
    return %feature_data;
}

# write extended state information to state file
# parameters:
# $feature: driver name
# $source (optional): GUI | CLI | API
# "GUI" is the default source
#
# NOTE: if previously set by a GUI source, the file will simply be touched and
#  the contents will not be modified.
sub write_feature_status_file {
    my $self    = shift;
    my $feature = shift;
    my $source  = shift || $SOURCE_GUI;

    # validate the $source passed in to make sure
    # it is allowed. Assume GUI if it isn't.

    if ( $source !~ /\A($SOURCE_API|$SOURCE_GUI|$SOURCE_CLI|$SOURCE_CPANEL_MAINTENTANCE)$/ ) {
        Cpanel::Debug::log_warn("Invalid source ($source) specified for \"$feature\" feature; assuming \"GUI\".");
        $source = $SOURCE_GUI;
    }

    my $features_directory = Cpanel::FeatureShowcase::showcased_feature_directory();

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::TouchFile');

    # If previous set by GUI, just touch the file
    if ( -e "$features_directory/$feature" ) {
        my %config_values = _loadconfig_list_or_die("$features_directory/$feature");
        my $interface     = ( $config_values{'INTERFACE'} ) ? $config_values{'INTERFACE'} : '';
        if ( $interface eq $SOURCE_GUI ) {
            Cpanel::FileUtils::TouchFile::touchfile("$features_directory/$feature");
            return 1;
        }
    }
    elsif ( !Cpanel::FileUtils::TouchFile::touchfile("$features_directory/$feature") ) {
        Cpanel::Debug::log_warn("Cannot create status file for \"$feature\" feature.");
    }

    # construct data hash for status file
    # and write it to touch file

    my $user = ( $ENV{'REMOTE_USER'} ) ? $ENV{'REMOTE_USER'} : ( getpwuid( int($<) ) )[0];
    my %conf;
    $conf{'INTERFACE'} = $source;
    $conf{'TIMESTAMP'} = time;
    $conf{'MODIFIED'}  = localtime;
    $conf{'USER'}      = $user;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::FlushConfig');
    return Cpanel::Config::FlushConfig::flushConfig( "$features_directory/$feature", \%conf );
}

# mark features (drivers) that have been advertised to user
# as viewed. accepts a list of feature names as
# a parameter. When a feature has been viewed and enabled/disabled
# a file with the feature name is created in the directory
# /var/cpanel/activate/features/
#
# NOTE: we're req'ing file modules to help conserve resources if this gets
#  frozen in a binary
sub mark_features_as_viewed {
    my ( $self, $source, @features_to_mark ) = @_;

    # check for existence of features directory
    # make sure it is not a symbolic link
    # and is actually a directory

    my $features_directory;
    if ( !( $features_directory = Cpanel::FeatureShowcase::create_showcased_feature_directory() ) ) {
        return;
    }

    # iterate through the list of features to be marked as viewed
    foreach my $feature (@features_to_mark) {
        $self->write_feature_status_file( $feature, $source );
    }
    return 1;
}

# $filters is an array with indices 0 being 'name' and 1 being an args hash DOESN'T WORK THAT WAY NOW
sub feature_info {
    my ( $self, $filters ) = @_;

    if ( ref $filters ne 'ARRAY' ) {
        $filters = [];
    }

    my $filterObj = $self->get_filterObj();

    # sanitize filters here?

    my $filterlist = Cpanel::Config::ConfigObj::Filter::FilterList->new($self);
    if ( @{$filters} ) {
        foreach my $filter ( @{$filters} ) {
            $filterObj->filter( $filter, undef, $filterlist );
        }
    }
    return $filterlist->to_array();
}

###### Filtering methods #######

sub get_filterObj {
    my ($self) = @_;
    if ( !$self->{'filterObj'} ) {
        $self->{'filterObj'} = Cpanel::Config::ConfigObj::Filter->new( _showcase_filters(), $self );
    }

    return $self->{'filterObj'};
}

sub _default_filter_list {
    my ($self)         = @_;
    my $filterObj      = $self->get_filterObj();
    my $custom_filters = _showcase_filters();
    my $filterlist     = Cpanel::Config::ConfigObj::Filter::FilterList->new($self);

    foreach my $filter ( ( 'expunge_invalid_licensed', 'is_showcased' ) ) {
        $filterObj->filter( $filter, undef, $filterlist );
    }

    return $filterlist;
}

sub _showcase_filters {
    return {
        'is_showcased'   => \&_filter_is_showcased,
        'is_recommended' => \&_filter_is_recommended,
    };
}

### custom filters for showcase ###

sub _filter_is_showcased {
    my ($listObj) = @_;
    my $data = $listObj->to_hash();
    foreach my $name ( keys %{$data} ) {
        my $metaObj = $data->{$name}->meta();
        unless ( $metaObj->can('showcase')
            && ref $metaObj->showcase eq 'HASH'
            && %{ $metaObj->showcase } ) {
            $listObj->remove($name);
        }
    }
    return 1;
}

sub _filter_is_recommended {
    my ($listObj) = @_;
    my $data = $listObj->to_hash();
    foreach my $name ( keys %{$data} ) {
        my $metaObj = $data->{$name}->meta();
        if ( !$metaObj->is_recommended() ) {
            $listObj->remove($name);
        }
    }
    return 1;
}

sub _html {
    my $text = shift;
    $text =~ s{\n}{<br />}g;

    my $token = $ENV{'cp_security_token'} ? $ENV{'cp_security_token'} : "";
    $text =~ s/\[% CP_SECURITY_TOKEN %\]/$token/g;

    return $text;
}

1;
