package Cpanel::cPAddons::Class;

# cpanel - Cpanel/cPAddons/Class.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::cPAddons::Globals::Static ();
use Cpanel::cPAddons::LegacyNaming    ();
use Cpanel::AdminBin::Serializer      ();
use Cpanel::LoadFile                  ();
use Cpanel::LoadModule                ();
use Cpanel::Features::Load            ();

use Cpanel::Locale::Lazy 'lh';

our $SINGLETON;

use constant _ENOENT => 2;

my $logger;
my %default_approved_vendors = (
    'cPanel' => {
        'weburl' => 'http://www.cpanel.net/cpaddons.pl',
        'securl' => 'http://www.cpanel.net/cpaddons.pl',    # ?id=$meta_info{security_id}
        'palmd5' => '382c1ad1d1e50bf1e77a3b17ff3d1e96',     # md5sum of cPAddonsMd5::$pal.pm
        'tarurl' => '',                                     # url to tar.gz that gets untarred into /usr/local/cpanel/cpaddons/$pal
        'secimg' => '../images',                            # url to directory with security_rank gifs, non https will cause browser warnings  in SSL cPanel...
    },
);

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {
        'approved_vendors'        => {%default_approved_vendors},
        'approved_addons'         => {},
        'deprecated_addons'       => {},
        'disabled_addons'         => {},
        'rpm_packaged_modules'    => [],
        'legacy_packaged_modules' => [],
    }, $class;

    # disabled addons are managed with feature lists
    my $featurelist = $OPTS{'featurelist'} || $Cpanel::CPDATA{'FEATURELIST'};    # PPI NO PARSE - passed in if needed

    my $feature_list_name =
      defined $featurelist && Cpanel::Features::Load::is_feature_list("$featurelist.cpaddons")
      ? $featurelist
      : 'default';

    foreach my $list ( $feature_list_name, 'disabled' ) {
        next if !-s Cpanel::Features::Load::featurelist_file("$list.cpaddons");
        my $features_ref = Cpanel::Features::Load::load_featurelist( "$list.cpaddons", '=' );
        foreach my $feature ( %{$features_ref} ) {
            $self->{'disabled_addons'}{$feature} = 1 if defined $features_ref->{$feature} && !$features_ref->{$feature};
        }
    }

    my $conf;

    my $serialized = Cpanel::LoadFile::load_if_exists("$Cpanel::cPAddons::Globals::Static::base/cPAddonsConf.json");

    if ( defined $serialized && Cpanel::AdminBin::Serializer::looks_like_serialized_data($serialized) ) {
        $conf = Cpanel::AdminBin::Serializer::Load($serialized);
    }
    elsif ( -e "$Cpanel::cPAddons::Globals::Static::base/cPAddonsConf.pm" ) {
        local @INC = ( $Cpanel::cPAddons::Globals::Static::base, @INC );
        eval 'use cPAddonsConf;';    ##no critic(ProhibitStringyEval)
        if ( !$@ ) {
            $conf = { 'vend' => \%cPAddonsConf::vend, 'inst' => \%cPAddonsConf::inst };
        }
    }

    if ($conf) {

        # Load the approved vendors
        my ( $vend, $inst ) = @{$conf}{ 'vend', 'inst' };

        @{ $self->{'approved_vendors'} }{ keys %$vend } = values %$vend;

        # Load the approved addons
        for my $addon ( keys %$inst ) {
            my $addon_data = {
                module => $addon,
                %{ $inst->{$addon} },
            };
            if ( $addon_data->{version} ) {
                $self->{'approved_addons'}{$addon} = 1;
            }
            if ( $addon_data->{deprecated} ) {
                $self->{'deprecated_addons'}{$addon} = 1;
            }
            if ( $addon_data->{is_rpm} ) {
                push @{ $self->{'rpm_packaged_modules'} }, $addon_data;
            }
            else {
                push @{ $self->{'legacy_packaged_modules'} }, $addon_data;
            }
        }
    }

    return $self;
}

sub get_disabled_addons {
    my ($self) = @_;
    return %{ $self->{'disabled_addons'} };
}

sub get_approved_vendors {
    my ($self) = @_;
    return %{ $self->{'approved_vendors'} };
}

sub get_approved_addons {
    my ($self) = @_;
    return { %{ $self->{'approved_addons'} } };
}

sub get_deprecated_addons {
    my ($self) = @_;
    return { %{ $self->{'deprecated_addons'} } };
}

sub get_rpm_packaged_modules {
    my ($self) = @_;
    return $self->{'rpm_packaged_modules'};
}

sub get_legacy_packaged_modules {
    my ($self) = @_;
    return $self->{'legacy_packaged_modules'};
}

sub list_available_modules {
    my ( $self, $include_every ) = @_;
    my %cpaddons;

    my $base_dir = $Cpanel::cPAddons::Globals::Static::base;
    foreach my $addon_type (qw(rpm_packaged_modules legacy_packaged_modules)) {
        my $addons = $self->{$addon_type} or next;

        foreach my $addon (@$addons) {
            my $package_name = $addon->{'module'};
            my ( $vendor, $category, $name ) = split( m{::}, $package_name );
            my $catgory_name = $category;

            # ensure that it’s installed
            my $path = "$base_dir/$vendor/$category/$name.pm";
            if ( !-e $path ) {
                warn "stat($path): $!" if $! != _ENOENT();
                next;
            }

            $catgory_name =~ tr/_/ /;
            my $display_name = $addon_type eq 'rpm_packaged_modules' ? $addon->{'display_app_name'} : Cpanel::cPAddons::LegacyNaming::get_app_name($package_name);
            if ( $include_every
                || !exists $self->{'disabled_addons'}{$package_name} ) {
                $cpaddons{$catgory_name}->{$package_name} = $display_name;
            }
        }
    }

    return \%cpaddons;
}

sub load_cpaddon_feature_descs {
    my ($self) = @_;
    my $addon_features = $self->list_available_modules(1);

    my @addon_feature_descriptions = ();
    for my $ky ( sort keys %{$addon_features} ) {
        next if ref $addon_features->{$ky} ne 'HASH';
        for my $ns ( sort keys %{ $addon_features->{$ky} } ) {
            my ( $vend, $cat, $name ) = split( m{::}, $ns, 3 );
            push @addon_feature_descriptions, [ $ns, ( $addon_features->{$ky}->{$ns} || $name ) . " ($vend)" ];
        }
    }

    return @addon_feature_descriptions;
}

sub load_cpaddon_feature_names {
    my ($self) = @_;
    my @feature_names = ();

    my $addon_features = $self->list_available_modules(1);

    for my $ky ( sort keys %{$addon_features} ) {
        next if ref $addon_features->{$ky} ne 'HASH';
        for ( sort keys %{ $addon_features->{$ky} } ) {
            push @feature_names, $_;
        }
    }

    return @feature_names;
}

my $notices;

sub _notices {
    return $notices if $notices;
    Cpanel::LoadModule::load_perl_module('Cpanel::cPAddons::Notices');
    return ( $notices ||= Cpanel::cPAddons::Notices::singleton() );
}

1;
