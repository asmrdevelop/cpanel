package Whostmgr::Addons::Pkgr::Cache;

# cpanel - Whostmgr/Addons/Pkgr/Cache.pm           Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Addons::Pkgr::Cache

=head1 SYNOPSIS

    my @pkgs = Whostmgr::Addons::Pkgr::Cache->load()

=head1 DESCRIPTION

This is a cache for most of the package-assembly logic for
L<Whostmgr::Addons::Pkgr>. The cache expires after one day.

This method subclasses L<Cpanel::CacheFile>.

=head1 TODO

It would be ideal for the data-fetching logic to be in its own
module.

=head1 METHODS

=head2 @pkgs = I<CLASS>->load( BASEURL, ATTR1, ATTR2, … )

=cut

use parent qw( Cpanel::CacheFile );

use Try::Tiny;

use Cpanel::Autodie       ();
use Cpanel::ConfigFiles   ();
use Cpanel::Context       ();
use Cpanel::DataURI       ();
use Cpanel::Plugins::Repo ();
use Cpanel::Version::Full ();
use Cpanel::OS            ();

use Whostmgr::Addons::Legacy ();

our $_PATH_BASE = '/var/cpanel/caches/manage_plugins';

use constant _TTL => 86400;    #1 day

use constant ATTRIBUTE_ORDER => (
    'id',
    'label',
    'description',
    'version',
    'url',
);

#This hash doubles as the “whitelist” of plugins that this version
#of cPanel & WHM will recognize. It was considered to fetch the logo
#from the repo itself, abusing the “Provides” tag as a way to store a
#data URI, but we still need to whitelist these, so we might as well
#just store the logos in the product.
my %known_plugins = (
    'cpanel-dovecot-solr' => { logo_path => 'img-sys/solr.svg' },
    'cpanel-munin'        => { logo_path => 'img-sys/munin_cropped.svg' },
    'cpanel-clamav'       => { logo_path => 'img-sys/clamav_black_r.svg' },
);

use constant LOGO_MIME_TYPE => 'image/svg+xml';

sub load {
    my ( $class, @args ) = @_;

    Cpanel::Context::must_be_list();
    return @{ $class->SUPER::load(@args) };
}

sub _PATH {
    return "$_PATH_BASE." . Cpanel::Version::Full::getversion();
}

sub _LOAD_FRESH {
    my ($class) = @_;
    my @modules;

    for my $mod_ar ( _modules( \%known_plugins ) ) {
        my %addon;
        @addon{ ATTRIBUTE_ORDER() } = @$mod_ar;
        $addon{'pkg'} = $addon{'id'};
        push @modules, \%addon;
    }

    for my $mod_ar ( _legacy_modules() ) {
        my %addon;
        @addon{ ATTRIBUTE_ORDER() } = @$mod_ar;
        $addon{'pkg'}               = Whostmgr::Addons::Legacy::get_plugin_rpm_name( $addon{'id'} );
        $addon{'version'}           = Whostmgr::Addons::Legacy::get_plugin_rpm_version( $addon{'pkg'} );
        push @modules, \%addon;
    }

    for my $mod (@modules) {

        #Set minimum memory specifications for any module that has one, in bytes.
        #If there are no min-specs for a module, nothing needs to be added.
        if ( $mod->{'id'} eq 'cpanel-clamav' ) {
            $mod->{'minimum_ram'} = 3 * 1024 * 1024 * 1024;
        }
        elsif ( $mod->{'id'} eq 'cpanel-z-push' ) {
            $mod->{'minimum_ram'}  = 7 * 1024 * 1024 * 1024;
            $mod->{'minimum_cpus'} = 4;
        }

        #Set up a logo to display in the URI
        my $logo_data_uri;

        my $plugin_info = $known_plugins{ $mod->{'id'} } or next;
        if ( my $logo_path = $plugin_info->{'logo_path'} ) {
            Cpanel::Autodie::open( my $rfh, '<', "$Cpanel::ConfigFiles::CPANEL_ROOT/$logo_path" );

            $logo_data_uri = Cpanel::DataURI::create_from_fh(
                LOGO_MIME_TYPE(),
                $rfh,
            );
        }
        $mod->{'logo'}         = $logo_data_uri;
        $mod->{'installed_by'} = $plugin_info->{installed_by} || '';
        $mod->{'description'} .= "\n" . $plugin_info->{description_detail} if $plugin_info->{description_detail};
    }

    return \@modules;
}

#----------------------------------------------------------------------

#The command below is the source of the information on the legacy modules:
#> curl http://httpupdate.cpanel.net/cpanelsync/adons/modules/nthemes.rc
#spamdconf|cPanel, L.L.C.|free|0|spamd startup configuration editor|0.55
#clamavconnector|cPanel, L.L.C.|free|0|Virus Protection for Email and Filemanager Uploads|0.97.8-3.6
#cronconfig|cPanel, L.L.C.|free|0|Allows user to edit cPanel cron settings/program run times|0.4.4
#munin|cPanel, L.L.C.|free|0|Munin Server Monitor|1.4.7-2.8

use constant _legacy_modules => (
    [
        'cpanel-clamav',
        'ClamAV for cPanel',
        'Virus Protection for Email and Filemanager Uploads',
    ],
    [
        'cpanel-munin',
        'Munin for cPanel',
        'Munin Server Monitor',
    ],
);

sub _modules {
    my ($whitelist) = @_;
    my @pkgs;

    # get_config() returns the list of mirrors in random order.
    # It’s possible that any given returned mirror could be down.
    # To make the most of the mirror list, we should keep retrying until we
    # get a mirror that actually works, up to the number of mirrors
    my $repo_config;
    my @baseurls;
    my $mirrorurl = "";
    try {
        $repo_config = Cpanel::Plugins::Repo::get_config();
        $mirrorurl   = $repo_config->{'mirrorurl'} if exists $repo_config->{'mirrorurl'};
        @baseurls    = $repo_config->{'baseurls'}->@*;
    }
    catch {

        # re-throw only if the problem is not with the mirror or the network:
        my $ex = $_;

        require Scalar::Util;

        if ( !Scalar::Util::blessed($ex) ) {
            if ( !grep { $ex->isa("Cpanel::Exception::HTTP::$_") } qw(Network Server) ) {
                die $ex;
            }
        }
    };

    return [] if !@baseurls;

    my $ok;
    my $errors;
    require Cpanel::RepoQuery;

    foreach my $baseurl (@baseurls) {
        try {
            @pkgs = Cpanel::RepoQuery::get_all_packages_from_repo( $baseurl, $mirrorurl );
            $ok   = 1;
        }
        catch {
            local $@ = $_;
            my $error_msg = "Unable to download packages from $baseurl";
            $errors .= $error_msg . "\n";
            require Cpanel::Logger;
            Cpanel::Logger->new()->warn( $error_msg . ":\n" . $@ );
        };

        last if $ok;
    }

    warn $errors unless $ok;
    @pkgs = map {
        [
            $_->{'name'},
            $_->{ Cpanel::OS::package_descriptions()->{'short'} },
            $_->{ Cpanel::OS::package_descriptions()->{'long'} },
            $_->{'version'} . ( exists( $_->{'release'} ) ? '-' . $_->{'release'} : '' ),
            $_->{'url'},
        ]
    } grep { $_->{'name'} && $whitelist->{ $_->{'name'} } } @pkgs;

    return @pkgs;
}

1;
