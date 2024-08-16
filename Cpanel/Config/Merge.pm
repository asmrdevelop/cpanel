package Cpanel::Config::Merge;

# cpanel - Cpanel/Config/Merge.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig   ();
use Cpanel::Config::FlushConfig  ();
use Cpanel::Crypt::GPG::Settings ();
use Cpanel::Update::Logger       ();

=head1 NAME

Cpanel::Config::Merge - merge two config files

=head1 USAGE


    Cpanel::Config::Merge::files(
           defaults_file => '/ulc/etc/cpanel.config',  # source
           config_file => '/var/cpanel/cpanel.config', # destination (overwrite)
           # logger => Cpanel::Logger->new # optional
    );


=head1 DESCRIPTION

Merge two cPanel config files using default values from 'default_file'
and storing the result to the file 'config_file'

=head1 METHODS

=over 4

=item B<files>

This is done one time during install to assure cpanel.config is fully populated. It will merge in customer
provided values if present.

=cut

sub files {
    my (%opts) = @_;

    my $config_defaults_file = $opts{defaults_file} or die q[Missing required 'defaults_file' argument];    # a.k.a. source
    my $config_file          = $opts{config_file}   or die q[Missing required 'config_file' argument];      # a.k.a. destination
    my $logger               = $opts{logger} // Cpanel::Update::Logger->new;

    my $cpanel_config = {};                                                                                 # hash used to load config in memory

    # Load defaults from etc/cpanel.config
    Cpanel::Config::LoadConfig::loadConfig( $config_defaults_file, $cpanel_config );

    # Set default signature_validation setting to match current update mirror
    $cpanel_config->{'signature_validation'} = Cpanel::Crypt::GPG::Settings::validation_setting_for_configured_mirror();

    # Load user provided config defaults, which are already moved into place.
    if ( -e $config_file ) {
        $logger->info("Merging custom cpanel.config entries provided by installer with cPanel defaults.");
        Cpanel::Config::LoadConfig::loadConfig( $config_file, $cpanel_config );
    }
    else {
        $logger->info("Installing default cpanel.config, located in etc/cpanel.config");
    }

    # Save the merged defaults.
    Cpanel::Config::FlushConfig::flushConfig( $config_file, $cpanel_config, '=', undef, { 'sort' => 1 } );

    return 1;
}

=back

=cut

1;
