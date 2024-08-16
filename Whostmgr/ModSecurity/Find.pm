
# cpanel - Whostmgr/ModSecurity/Find.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Find;

use strict;
use File::Find ();    # ok for 5.6.2 / compiling

use Whostmgr::ModSecurity            ();
use Whostmgr::ModSecurity::Configure ();

my @fixed_configs = qw(
  modsec2.user.conf
);

=head1 NAME

Whostmgr::ModSecurity::Find

=head1 SUBROUTINES

=head2 find()

Locates configuration files eligible for management.

  Arguments:
    - None

  Returns:
  An array ref of hash refs, where each hash ref corresponds to a single config
  file and contains the following key/value pairs:
    - 'config': The relative path of the config file.
    - 'active': Boolean value indicating whether the config file is active. This is
             determined by whether the file's include is in place.

  Example:
  [
    { config => 'modsec2.user.conf',                          active => 1 },
    { config => 'modsec_vendor_configs/foo/bar/example.conf', active => 1 }
  ]

=cut

sub find {
    my $config_prefix = Whostmgr::ModSecurity::config_prefix();
    my $active_cache  = [];

    my @configs = map { { config => $_, active => Whostmgr::ModSecurity::Configure::is_config_active( $_, $active_cache ) } } grep { -f $config_prefix . '/' . $_ } @fixed_configs;

    my $search_dir = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir();
    push @configs, @{ find_vendor_configs($search_dir) };

    return \@configs;
}

sub find_vendor_configs {
    my $search_dir = shift || die;
    return [] if !-d $search_dir;
    my $active_cache = [];

    my $config_prefix = Whostmgr::ModSecurity::config_prefix();

    my @additional_configs;
    File::Find::find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $file = $File::Find::name;
                if ( -f $file && $file =~ m{\A\Q$config_prefix\E/(.+\.conf)\z} ) {    # Using /o on this regexp is fine in practice, but it breaks the unit tests because in the tests there can actually end up being more than one config prefix per process.
                    my $config = $1;
                    push @additional_configs,
                      {
                        config    => $config,
                        active    => Whostmgr::ModSecurity::Configure::is_config_active( $config, $active_cache ),
                        vendor_id => Whostmgr::ModSecurity::extract_vendor_id_from_config_name($config),
                      };
                }
            }
        },
        $search_dir
    );
    return \@additional_configs;
}

1;
