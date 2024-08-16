package Cpanel::DB::Map::Convert;

# cpanel - Cpanel/DB/Map/Convert.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie     ();
use Cpanel::ConfigFiles ();
use Cpanel::DB::Map     ();

sub old_dbmap_exists {
    my ($cpuser) = @_;

    return -e _yaml_dbmap_path($cpuser) ? 1 : 0;
}

sub _yaml_dbmap_path {
    my ($cpuser) = @_;

    require Cpanel::Validate::FilesystemNodeName;
    Cpanel::Validate::FilesystemNodeName::validate_or_die($cpuser);

    my $dir = $Cpanel::ConfigFiles::DATABASES_INFO_DIR;

    return "$dir/$cpuser.yaml";
}

#This accepts just the name of the cpuser that owns the DB map.
#
#If no old map data is found, this returns undef.
#
#If we found old map data, then this returns the data payload,
#updated for the current DB Map schema.
#
sub read_old_dbmap {
    my ($cpuser) = @_;

    my $yaml_file = _yaml_dbmap_path($cpuser);

    return undef if !-f $yaml_file;

    require Cpanel::CachedDataStore;
    my $data = Cpanel::CachedDataStore::load_ref($yaml_file);
    return if !$data;

    _update_data_from_cacheddatastore($data);

    return $data;
}

sub _update_data_from_cacheddatastore {
    my ($data) = @_;

    $data->{'version'} = $Cpanel::DB::Map::DATASTORE_SCHEMA_VERSION;

    return;
}

sub remove_old_dbmap {
    my ($cpuser) = @_;

    my $dir = $Cpanel::ConfigFiles::DATABASES_INFO_DIR;

    Cpanel::Autodie::unlink_if_exists()
      for (
        "$dir/$cpuser.yaml",
        "$dir/$cpuser.cache",
      );

    return 1;
}

1;
