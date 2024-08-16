
#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

package Whostmgr::Cpaddon::Conf;

use strict;
use warnings;
use Cpanel::cPAddons::Filter            ();
use Cpanel::FileUtils::Write            ();
use Cpanel::Config::Sources             ();
use Cpanel::HttpRequest                 ();
use Cpanel::Template                    ();
use Whostmgr::Cpaddon                   ();
use Whostmgr::Cpaddon::CacheFileManager ();
use Whostmgr::Cpaddon::Signatures       ();
use Cpanel::Imports;    # for locale() and logger()

use Cpanel::AdminBin::Serializer ();

################################################################################

my $CPANEL_ROOT = '/usr/local/cpanel';
my $ADDON_ROOT  = "$CPANEL_ROOT/cpaddons";

our $CONF_FILE          = "$ADDON_ROOT/cPAddonsConf.pm";
our $JSON_CONF_FILE     = "$ADDON_ROOT/cPAddonsConf.json";
our $CONF_TEMPLATE_FILE = "$CPANEL_ROOT/whostmgr/docroot/templates/cpaddons/cpaddons_conf.tmpl";

our ( $have_loaded, %Availab, %Current, %OwnVend );

################################################################################

=head1 NAME

Whostmgr::Cpaddon::Conf

=head1 DESCRIPTION

This module manages the generation of the generated cPAddonsConf.pm module under
/usr/local/cpanel/cpaddons. This module serves as a record of which addons are
installed or not installed, along with a handful of basic metadata attributes
about each addon.

=head1 FUNCTIONS

=head2 write_conf

=over

=item write_conf()

=item write_conf( config_definitions => ... )

=item write_conf( force => 1 )

=item write_conf( config_definitions => ..., force => 1 )

=item write_conf( force => 1, if_missing => 1 )

=back

Rebuilds the /usr/local/cpanel/cpaddons/cPAddonsConf.pm file.

=head3 Arguments

=over

=item * config_definitions - Hash ref - (Optional) If specified, allows you to choose
which addon information to write to the config file. Otherwise, the full set of addon
info will be gathered and written to the file.

=item * force - Boolean - (Optional) If true, force a reload from HTTP sources even if
caches haven't expired yet.

=item * if_missing - Boolean - (Optional) If true, only regenerate the conf if one or
both of the conf files is/are missing. This may be combined with C<force>, and the
C<if_missing> check will still be effective.

=back

=head3 Returns

True on success

=head3 Throws

An exception will be thrown if:

- The conf file can't be written

- The needed data can't be looked up in preparation for writing the conf file

=cut

sub write_conf {
    my %opts = @_;

    if ( $opts{'if_missing'} ) {
        return if -f $CONF_FILE && -f $JSON_CONF_FILE;
    }

    my $config_definitions = $opts{'config_definitions'};

    _load_once( force => $opts{'force'} );

    # Create definitions for all addons if none have been passed in
    if ( !$config_definitions ) {
        for my $amod ( sort keys %Availab ) {
            next if $amod =~ tr/'//;

            my $version = 0;
            my $VERSION = 0;
            my ( $is_rpm, $display_app_name, $desc, $is_deprecated ) = gather_addon_conf_info( $Availab{$amod}, $amod );

            if ( $Current{$amod}->{VERSION} && $Availab{$amod}->{version} !~ tr/'// ) {

                # Admin has checked this addon to allow cpanel users to install it
                $version = $Availab{$amod}->{version};    # Application Version, ex: 4.7.1
                $VERSION = $Availab{$amod}->{VERSION};    # Full packaged Version, ex: 4.7.1-1.0.0
            }

            $config_definitions->{$amod} = {
                version          => $version,
                VERSION          => $VERSION,
                is_rpm           => $is_rpm,
                display_app_name => $display_app_name,
                desc             => $desc,
                deprecated       => $is_deprecated,
            };

        }
    }

    my $template_data = {
        config_definitions => $config_definitions,
        ownvend            => \%OwnVend,
    };
    my ( $success, $output ) = Cpanel::Template::process_template(
        'whostmgr',
        {
            template_file => $CONF_TEMPLATE_FILE,
            data          => $template_data,
        }
    );
    if ( !$success ) {
        die locale()->maketext( 'The system could not process the template for “[_1]”: [_2]', $CONF_TEMPLATE_FILE, $output );
    }

    Cpanel::FileUtils::Write::overwrite( $CONF_FILE, $$output, 0644 );    # throws exception on failure
    Cpanel::FileUtils::Write::overwrite(
        $JSON_CONF_FILE,
        Cpanel::AdminBin::Serializer::Dump(
            {
                'inst' => $config_definitions,
                'vend' => \%OwnVend,
            }
        ),
        0644
    );                                                                    # throws exception on failure

    return 1;
}

=head3 gather_addon_conf_info(ADDON, NAMESPACE)

Get the information for legacy addons and RPM-based addons that is
needed for writing the cPAddonsConf.pm list.

=head3 Arguments

=over

=item * ADDON - Hash ref - Containing the record for the addon from cPAddonsAvailable.pm

=item * NAMESPACE - String - The addon namespace. See Cpanel::cPAddons::Module for examples of this.

=back

=head3 Returns

Returns a list:

[0] - Boolean - True if the addon is RPM-provided. False otherwise.

[1] - String - The "display app name", which may have been adjusted for human presentation.

[2] - String - The description for the addon.

=cut

sub gather_addon_conf_info {
    my ( $addon, $namespace ) = @_;

    my $is_rpm           = $addon->{package}{is_rpm} ? 1 : 0;
    my $display_app_name = $addon->{application}{name};
    my $desc             = $addon->{application}{summary} || '';
    my $is_deprecated    = Cpanel::cPAddons::Filter::is_deprecated($namespace);

    if ( !$display_app_name ) {
        my ( $vendor, undef, $name ) = split /\:\:/, $namespace;
        $display_app_name //= $name;
    }

    if ( !$desc ) {
        $desc = _get_legacy_description($namespace);
    }

    return ( $is_rpm, $display_app_name, $desc, $is_deprecated );
}

# Addons packaged in the legacy format place their description text in the MD5
# module. This method allows us to retrieve it so that we can create a normalized
# structure in the cPAddonsConf.pm list.
sub _get_legacy_description {
    no strict 'refs';

    my $namespace = shift;
    my ($vendor)  = split /\:\:/, $namespace;

    if ( !$INC{"cPAddonsMD5/${vendor}.pm"} ) {
        eval "use cPAddonsMD5::${vendor};";    ##no critic(ProhibitStringyEval)
        return '' if $@;
    }

    # We have the vendor MD5 module loaded, so we can get the desc
    return ${"cPAddonsMD5\:\:${vendor}\:\:cpaddons"}{$namespace}{desc} || '';
}

=head3 load()

Load the cPAddons conf files.

=head3 Arguments

Named parameters:

=over

=item * force - Boolean - (Optional) If specified and true, force a full reload
(including HTTP retrievals) even if the caches have not expired yet.

=back

=head3 Returns

This function returns a list containing three hash refs:

[0] - Hash ref - "Availab"

[1] - Hash ref - "Current"

[2] - Hash ref - "OwnVend"

=head3 Throws

If the necessary data can't be loaded, this function throws an exception.

Note: In some cases, there may be network operations to download new lists,
which could lead to intermittent failures depending on the quality of network
connectivity.

=head3 In-memory cache

This function populates an in-memory cache of %Availab, %Current, and %OwnVend.
The cache is not used as a source for future load() calls; only other functions
in Whostmgr::Cpaddon::Conf take advantage of this cache.

=cut

sub load {
    my %opts = @_;

    eval 'use cPAddonsConf;';    ##no critic(ProhibitStringyEval)
    if ($@) {                    # If the conf file hasn't been built yet, start with nothing
        %cPAddonsConf::vend = ();
        %cPAddonsConf::inst = ();
    }

    mkdir $ADDON_ROOT                     if !-d $ADDON_ROOT;
    mkdir "$ADDON_ROOT/cPAddonsAvailable" if !-d "$ADDON_ROOT/cPAddonsAvailable";

    # Current contains the cPAddons installed to the local repository/database
    %OwnVend = %cPAddonsConf::vend;
    %Current = %cPAddonsConf::inst;

    my $listage        = 14400;                             # 4 hours in seconds
    my $security_token = $ENV{'cp_security_token'} || '';

    # Check the legacy cache
    if ( ( ( ( stat "$ADDON_ROOT/cPAddonsAvailable.pm" )[9] || 0 ) + $listage ) < time() || $opts{'force'} ) {
        _refresh_legacy_cache();
    }

    # Load the module containing the cpanel provided addons
    eval qq{require '$ADDON_ROOT/cPAddonsAvailable.pm';};    ##no critic(ProhibitStringyEval)

    if ( my $exception = $@ ) {
        die locale()->maketext( 'The system failed to retrieve the list of available [asis,cPAddons]: [_1]', $exception );
    }

    {
        # Load the cpanel addons into the available list
        no warnings 'once';
        %Availab = ( %Availab, %cPAddonsAvailable::list );
    }

    # Load the addons available from each vendor
    for my $vnd ( sort keys %OwnVend ) {
        next if !$vnd;

        eval "use cPAddonsAvailable\:\:$vnd;";    ##no critic(ProhibitStringyEval)
        if ( my $exception = $@ ) {
            logger()->warn("Vendor List for “$vnd” failed to be included: $exception");    # we can move on from this
        }
        else {
            # TODO: This loading of addon info from cPAddonsAvailable is sometimes redundant if the
            # _refresh_legacy_cache() call above is made because it also gets loaded there.
            no strict 'refs';
            for my $addon ( sort keys %{"cPAddonsAvailable\:\:$vnd\:\:list"} ) {
                next if $addon !~ m/^\Q$vnd\E\:\:/;
                $Availab{$addon} = ${"cPAddonsAvailable\:\:$vnd\:\:list"}{$addon};
            }
        }
    }

    my $installed_rpms = Whostmgr::Cpaddon::get_installed_addons();
    @Current{ keys %$installed_rpms } = values %$installed_rpms;

    # Check the rpm addon cache
    my $available_rpms;
    eval { $available_rpms = Whostmgr::Cpaddon::CacheFileManager->load(); };

    my $needs_new_data = 0;
    if ( my $exception = $@ ) {

        # Check if the cache has expired
        die if $exception && !UNIVERSAL::isa( $exception, 'Cpanel::CacheFile::NEED_FRESH' );

        # It has expired, so request new data
        $needs_new_data = 1;
    }

    if ( $needs_new_data || $opts{'force'} ) {

        # Reload the cpaddons distributed via rpm
        $available_rpms = Whostmgr::Cpaddon::get_available_addons();

        # TODO: Add third-party vendor rpm based addon here
        # to the $available_rpm collection. https://webpros.atlassian.net/browse/LC-6270

        # Update the cache
        die if !eval { Whostmgr::Cpaddon::CacheFileManager->save($available_rpms); };
    }

    # Add the rpm based addons to the list of available addons
    @Availab{ keys %$available_rpms } = values %$available_rpms;

    return \%Availab, \%Current, \%OwnVend;
}

sub _refresh_legacy_cache {

    my $basesyncdir = '/cpanelsync/cpaddons';    # no trailing slash

    # The cpanel list of addons for
    #   Production: http://httpupdate.cpanel.net/cpanelsync/cpaddons/cPAddonsAvailable.pm
    #   Testing:    http://httpupdate.cpanel.net/cpanelsync/cpaddons_test/cPAddonsAvailable.pm
    # The cache files are stored in:
    #   /usr/local/cpanel/cpaddons/cPAddonsAvailable.pm - for cpanel
    #   /usr/local/cpanel/cpaddons/cPAddonsAvailable/<vendor>.pm - for vendors

    # The testing list is available if the touchfile
    # /var/cpanel/use_cpaddons_test_branch exists
    $basesyncdir .= '_test' if -e '/var/cpanel/use_cpaddons_test_branch';

    my %CPSRC = Cpanel::Config::Sources::loadcpsources();
    eval {
        Cpanel::HttpRequest->new( 'hideOutput' => 1 )->request(
            'host'     => $CPSRC{'HTTPUPDATE'},
            'url'      => $basesyncdir . '/cPAddonsAvailable.pm',
            'destfile' => "$ADDON_ROOT/cPAddonsAvailable.pm",
            Whostmgr::Cpaddon::Signatures::httprequest_sig_flags('cPanel'),
        );
    };
    if ( my $exception = $@ ) {
        logger()->warn("Warning: Failed to download cPAddonsAvailable.pm from cPanel: $exception");
    }

    # Also load any list of available addons provided by third-party vendors
    for my $vnd ( sort keys %OwnVend ) {
        next if !$vnd;
        next if ref $OwnVend{$vnd} ne 'HASH';
        next if !keys %{ $OwnVend{$vnd} };

        # Download the vendor available downloads
        eval {
            Cpanel::HttpRequest->new( hideOutput => 1 )->request(
                host     => $OwnVend{$vnd}->{'cphost'},
                url      => "$OwnVend{$vnd}->{'cphuri'}/cPAddonsAvailable/$vnd.pm",
                destfile => "$ADDON_ROOT/cPAddonsAvailable/$vnd.pm",
                Whostmgr::Cpaddon::Signatures::httprequest_sig_flags($vnd)
            );
        };
        my $exception = $@;

        if ( !$exception ) {

            # Load the third-party addons into the available list.
            eval "use cPAddonsAvailable\:\:$vnd;";    ##no critic(ProhibitStringyEval)
            $exception = $@;
        }

        if ($exception) {
            unlink "$ADDON_ROOT/cPAddonsAvailable/$vnd.pm";
            die "Warning: Vendor List failed to be included. Please contact $vnd for support.\n$@";
        }

        else {
            no strict 'refs';
            for ( sort keys %{"cPAddonsAvailable\:\:$vnd\:\:list"} ) {
                next if $_ !~ m/^\Q$vnd\E\:\:/;
                $Availab{$_} = ${"cPAddonsAvailable\:\:$vnd\:\:list"}{$_};
            }
        }
    }
    return;
}

sub _load_once {
    my %load_opts = @_;
    if ( !$have_loaded ) {
        load(%load_opts);
        $have_loaded = 1;
    }
    return;
}

1;
