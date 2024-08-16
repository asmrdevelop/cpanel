package Cpanel::Component::Cache;

# cpanel - Cpanel/Component/Cache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Debug           ();
use Cpanel::CachedDataStore ();
use Cpanel::SafeDir::MK     ();    #okay: only depends on Cpanel::Logger

our $VERSION = 1.0;                #might consider altering versioning() if this changes <shrug/>

my $cached_info;

=encoding utf-8

=head1 NAME

C<Cpanel::Component::Cache>

=head1 DESCRIPTION

Cache file manager for various C<Cpanel::Component> datasets.

The module implements some similar method as C<Cpanel::Component> so you can retrieve the same data from the cache
without going thru the more expensive C<Cpanel::Component> object.

=over

=item get_component_value

=item has_registered_components

=item has_component

=back

=head1 SYNOPSIS

    use Cpanel::Component::Cache ();
    my $info = Cpanel::Component::Cache::fetch();

    # add a new component to the cache.
    $info->{ 'new_component' } = {};

    Cpanel::Component::Cache::save($info);

=head1 FUNCTIONS

=head2 versioning()

The current version of the cache.

=cut

sub versioning {
    return 'v1';
}

=head2 cache_dir()

The path to the cache directory. This is mainly provided for testing

=cut

sub cache_dir {
    return '/var/cpanel/caches';
}

=head2 cache_deps()

The list of files that if they are changed the cache should be flushed.

=cut

sub cache_deps {
    return (
        '/var/cpanel/plugins/config.json',
    );
}

=head2 cachefile()

Load the selected cache file.  This is mainly provided for testing.

=head3 RETURNS

string - the path to the specific cache file.

=cut

sub cache_file {
    my $versioning = versioning();
    my $dir        = cache_dir();

    return "$dir/license_component.info.$versioning";
}

=head2 expired

Check to see if the cache should be expired. If so, remove the cache.

=head3 RETURNS

1 when the cache was expired, 0 otherwise.

=cut

sub expired {
    my $cache_path = cache_file();
    my $cache_ts   = _mtime($cache_path);
    foreach my $dep_path ( cache_deps() ) {
        my $dep_ts = _mtime($dep_path);
        if ( $dep_ts > $cache_ts ) {
            $cached_info = undef;
            unlink($cache_path);
            return 1;
        }
    }
    return 0;
}

=head2 fetch()

Retreive the data stored in the cache file by type.

=head3 RETURNS

hashref - the data stored in the cache file. The structure varies depending on the C<$TYPE> of file requested. If the requested
cache file is not present on disk, this returns an empty HASHREF.

=cut

sub fetch {
    my $cache_path = cache_file();

    if ( !$cached_info ) {
        $cached_info = _load($cache_path);
    }
    return $cached_info || {};
}

=head2 save($DATA)

Update the cache with new data.

=cut

sub save {
    my ($data) = @_;
    return if ref $data ne 'HASH';
    my $dir = cache_dir();

    # must be root
    return if $> != 0;

    if (   !( Cpanel::SafeDir::MK::safemkdir( $dir, 0711 ) )
        || !( chown 0, 0, $dir ) ) {
        Cpanel::Debug::log_warn("Could not create or assert directory '$dir' for writing.");
        return;
    }

    $cached_info = $data;
    return Cpanel::CachedDataStore::savedatastore(
        cache_file(),
        {
            'data' => $data,
        }
    );
}

=head2 has_registered_components()

Check if there are registered components in the cache.

=head3 RETURNS

1 when there are components, 0 otherwise.

=cut

sub has_registered_components {
    my $cache = Cpanel::Component::Cache::fetch();
    return ( keys %{ $cache->{'components'} } ) ? 1 : 0;
}

=head2 has_component(@COMPONENTS)

Check if the requested components are in the cache file.

=head3 ARGUMENTS

A list of component names to check.

=head3 RETURNS

1 when all the listed components are present, 0 otherwise.

=cut

sub has_component {
    my @components = @_;
    my $cache      = Cpanel::Component::Cache::fetch();
    foreach my $component (@components) {
        return 0 unless exists $cache->{'components'}->{$component};
    }
    return 1;
}

=head2 get_component_value($COMPONENT)

Retrieve data stored for the requested component

=head3 ARGUMENTS

The component to retrieve from the cache.

=head3 RETURNS

The value stored in the component cache for the passed component name if any.

=cut

sub get_component_value {
    my ($component) = @_;
    my $cache = fetch();
    my $value;
    if ( exists $cache->{'components'}->{$component} ) {
        $value = $cache->{'components'}->{$component};
    }
    return $value;
}

=head1 PRIVATE FUNCTIONS

=head2 _reset_vars()

For testing only.

=cut

sub _reset_vars {
    ($cached_info) = (undef);
    return;
}

=head2 _load($PATH)

Load the cache data from disk.

=head3 ARGUMENTS

=over

=item $PATH - string

Path to the cache file.

=back

=cut

sub _load ($path) {
    my $stored = Cpanel::CachedDataStore::loaddatastore($path);
    return $stored->{'data'} || { 'components' => {} };
}

=head2 _mtime($PATH)

Gets the mtime for a given path if it exists.

=head3 ARGUMENTS

=over

=item $PATH - string

Path to the file.

=back

=head3 RETURNS

0 if nothing exists at the path, otherwise returns the mtime for the file.

=cut

sub _mtime ($path) {
    return ( stat(_) )[9] if -e $path;
    return 0;
}

1;
