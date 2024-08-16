
# cpanel - Whostmgr/ModSecurity/Vendor.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Vendor;

=pod

Class for reading and vendor metadata (name, description, etc.),
and making Apache-related changes for that vendor (e.g., enabling
its rule set)

=cut

use strict;
use warnings;

use Carp                                 ();
use Cpanel::CachedDataStore              ();
use Cpanel::Exception                    ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();
use Cpanel::Locale 'lh';
use Whostmgr::ModSecurity                   ();
use Whostmgr::ModSecurity::Find             ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Whostmgr::ModSecurity::TransactionLog   ();
use Whostmgr::ModSecurity::Vendor           ();

use File::Path ();

#
# Constructor for loading an existing vendor from YAML
#

sub load {
    my ( $package, %args ) = @_;

    my $yaml_file = delete( $args{meta_yaml_file} ) || _vendor_meta_yaml( $args{vendor_id} );

    if ( !-f $yaml_file ) {
        die Cpanel::Exception::create( 'ModSecurity::NoSuchVendor', [ vendor_id => $args{vendor_id} ] );
    }

    my ( $vendor_metadata, $loaded_attributes );
    eval {
        $vendor_metadata   = Cpanel::CachedDataStore::load_ref($yaml_file);
        $loaded_attributes = $vendor_metadata->{attributes};
    };
    my $exception = $@;
    if ($exception) {
        die lh()->maketext( q{The downloaded file was not a valid vendor metadata [asis,YAML] file: [_1]}, $exception ) . "\n";
    }

    my $self = $package->new( %args, %$loaded_attributes );

    # Pick out just the one we care about for our version of ModSecurity. If ModSecurity is not installed
    # or our version is not supported by the vendor, then these 3 attributes will be omitted.
    my $modsecurity_version = Whostmgr::ModSecurity::version();
    if ( $modsecurity_version && ref $vendor_metadata->{$modsecurity_version} ) {
        $self->{archive_url}  = $vendor_metadata->{$modsecurity_version}{url};
        $self->{distribution} = $vendor_metadata->{$modsecurity_version}{distribution};
        $self->{dist_md5}     = $vendor_metadata->{$modsecurity_version}{MD5};
        $self->{dist_sha512}  = $vendor_metadata->{$modsecurity_version}{SHA512};
    }

    $self->{supported_versions} = [ grep { /^\d/ } sort keys %$vendor_metadata ];

    # If this wasn't already specified as an argument, fill it in based on the YAML file from which we loaded
    $self->{meta_yaml_file} ||= $yaml_file;

    # Set the location of the cache file that gets created after installing a vendor
    $self->{meta_vendor_cache_file} = _vendor_meta_cache( $args{vendor_id} );

    # Optional: For interactive callers
    $self->{progress_bar} = $args{progress_bar};

    $self->init_dynamic();

    return $self;
}

#
# Constructor for creating a vendor object based on the specified attributes
#

sub new {
    my ( $package, %args ) = @_;
    my $self = {};
    bless $self, $package;

    my $vendor_id = delete $args{vendor_id};
    if ( !defined($vendor_id) ) {
        Carp::croak( lh()->maketext('You must specify a [asis,vendor_id].') );
    }

    for my $attr_name ( _attributes_in() ) {
        my $value = delete $args{$attr_name};
        $self->{$attr_name} = $value;
    }

    # Fill in vendor_id based on known id requested for load
    $self->{vendor_id} = $vendor_id;
    $self->{installed} = 0;            # if it turns out this vendor has a real installed_from entry, installed will be set to 1

    return $self;
}

sub init_dynamic {
    my ($self) = @_;
    if ( $self->{installed_from} ) {
        $self->{installed} = 1;
    }
    else {
        $self->_init_installed_from();
    }
    $self->{enabled} = Whostmgr::ModSecurity::ModsecCpanelConf->new->is_vendor_enabled( $self->vendor_id ) ? 1 : 0;
    $self->{path}    = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir() . '/' . $self->vendor_id;
    return;
}

#
# Instance methods
#

# export using accessor methods since not all attributes are stored in the object
sub export {
    my ($self) = @_;
    return { map { defined( $self->$_() ) ? ( $_ => $self->$_() ) : () } _attributes_out() };
}

sub export_fresh {
    my ($self) = @_;
    $self->init_dynamic();
    return $self->export;
}

sub enable {
    my ($self) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->enable_vendor( $self->vendor_id );
}

sub disable {
    my ($self) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->disable_vendor( $self->vendor_id );
}

sub enable_updates {
    my ($self) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->enable_vendor_updates( $self->vendor_id );
}

sub disable_updates {
    my ($self) = @_;
    return Whostmgr::ModSecurity::ModsecCpanelConf->new->disable_vendor_updates( $self->vendor_id );
}

sub enable_configs {
    my ($self) = @_;
    my $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    my ( $ok, $outcomes ) = $self->_adjust(
        condition => sub { !shift->{'active'} },
        operation => sub { $mcc->include( shift->{'config'} ) }
    );
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    return ( $ok, $outcomes );
}

sub disable_configs {
    my ($self) = @_;
    my $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    my ( $ok, $outcomes ) = $self->_adjust(
        condition => sub { shift->{'active'} },
        operation => sub { $mcc->uninclude( shift->{'config'} ) }
    );
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    return ( $ok, $outcomes );
}

# For each config belonging to this vendor, if condition(config), then operation(config).
sub _adjust {
    my ( $self,      %args )      = @_;
    my ( $condition, $operation ) = @args{qw(condition operation)};

    my $configs = $self->configs;
    my @outcomes;
    my $all_ok = 1;

    if ( $self->{progress_bar} ) {
        $self->{progress_bar}->init( pos => 0, max => scalar(@$configs) );
    }

    for my $c (@$configs) {
        my $failed;
        if ( $condition->($c) ) {
            eval { $operation->($c) };
            if ($@) {
                push @outcomes, { config => $c->{config}, ok => 0, exception => _exception_string($@) };
                $failed = 1;
                $all_ok = 0;
            }
        }
        push @outcomes, { config => $c->{config}, ok => 1 } unless $failed;

        if ( $self->{progress_bar} ) {
            $self->{progress_bar}->increment->draw;
        }
    }

    $self->{progress_bar}->done if $self->{progress_bar};

    return $all_ok, \@outcomes;
}

# This datastore should be populated by whatever actually downloads the meta yaml file from some remote server.
# (Whostmgr::ModSecurity::VendorList)
sub _init_installed_from {
    my ($self) = @_;
    return if !-f Whostmgr::ModSecurity::abs_vendor_meta_urls();
    my $datastore             = Cpanel::CachedDataStore::loaddatastore( Whostmgr::ModSecurity::abs_vendor_meta_urls(), 0 ) || return;
    my $vendor_installed_from = $datastore->{data}{ $self->vendor_id() };

    # Prior to PBI 27470 (i.e., prior to 11.48), this was not a hash but a string.
    # For compatibility, handle pre-11.48 installed_from data by treating the string
    # as the url.
    if ( 'HASH' eq ref $vendor_installed_from ) {
        $self->{installed_from} = $vendor_installed_from->{url};
        $self->{inst_dist}      = $vendor_installed_from->{distribution};
        $self->{installed}      = 1;
    }
    elsif ( '' eq ref $vendor_installed_from ) {
        $self->{installed_from} = $vendor_installed_from;
        $self->{installed}      = 1;
    }
    $datastore->abort;

    return 1;
}

sub uninstall_most {
    my ($self) = @_;

    if ( -d $self->configs_dir ) {
        File::Path::remove_tree( $self->configs_dir )
          or die lh()->maketext(q{The system could not clean up the configuration files for the vendor.}) . "\n";
    }

    if ( $self->{meta_yaml_file} && -f $self->{meta_yaml_file} ) {
        unlink( $self->{meta_yaml_file} )
          or die lh()->maketext(q{The system could not remove the metadata file for the vendor.}) . "\n";
    }

    if ( $self->{meta_vendor_cache_file} && -f $self->{meta_vendor_cache_file} ) {
        unlink( $self->{meta_vendor_cache_file} )
          or die lh()->maketext(q{The system could not remove the metadata cache file for the vendor.}) . "\n";
    }

    return 1;
}

sub uninstall {
    my ($self) = @_;

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $self->vendor_id );
    my $pkg    = $vendor->{is_pkg};

    $self->disable_configs();    # This must be done before uninstall_most because the config list to disable can't be obtained if the configs are deleted

    my $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    $mcc->disable_vendor( $self->vendor_id );
    $mcc->disable_vendor_updates( $self->vendor_id ) unless $pkg;
    $mcc->remove_all_srrbi_for_vendor( $self->vendor_id );

    my $datastore = Cpanel::CachedDataStore::loaddatastore( Whostmgr::ModSecurity::abs_vendor_meta_urls(), 1 );
    delete $datastore->{data}{ $self->vendor_id };
    $datastore->save();

    if ($pkg) {
        require Cpanel::PackMan;
        eval { Cpanel::PackMan->instance->sys->uninstall($pkg) };
        warn "Failed to uninstall “$pkg”, that will need done manually.\n" if $@;
    }

    $self->uninstall_most;
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    Whostmgr::ModSecurity::TransactionLog::log( operation => 'remove_vendor', arguments => [ $self->vendor_id ] );

    return 1;
}

sub configs_dir {
    my ($self) = @_;
    return ( Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir() . '/' . $self->{vendor_id} );
}

sub configs {
    my ($self) = @_;
    return Whostmgr::ModSecurity::Find::find_vendor_configs( $self->configs_dir );
}

sub in_use {
    my ($self)  = @_;
    my $configs = $self->configs;
    my $count   = 0;
    for my $c (@$configs) {
        if ( $c->{active} ) {
            $count++;
        }
    }
    return $count;
}

#
# Private helpers
#

sub _attributes_in {
    return qw(          name description vendor_url report_url installed_from is_pkg);
}

sub _attributes_out {
    return qw(vendor_id name description vendor_url archive_url report_url installed_from inst_dist dist_md5 dist_sha512 path cpanel_provided enabled installed supported_versions is_pkg);
}

sub is_pkg             { return shift->{is_pkg} }
sub vendor_id          { return shift->{'vendor_id'} }
sub name               { return shift->{'name'} }
sub description        { return shift->{'description'} }
sub distribution       { return shift->{'distribution'} }
sub dist_md5           { return shift->{'dist_md5'} }
sub dist_sha512        { return shift->{'dist_sha512'} }
sub vendor_url         { return shift->{'vendor_url'} }
sub archive_url        { return shift->{'archive_url'} }
sub report_url         { return shift->{'report_url'} }
sub installed_from     { return shift->{'installed_from'} }
sub installed          { return shift->{'installed'} }
sub inst_dist          { return shift->{'inst_dist'} }
sub path               { return shift->{'path'} }
sub supported_versions { return shift->{'supported_versions'} }

sub cpanel_provided {
    my ($self) = @_;
    return ( ( $self->{installed_from} || '' ) =~ m{^https?://httpupdate\.cpanel\.net/} ? 1 : 0 );
}

sub enabled { return shift->{'enabled'} }

sub _vendor_meta_yaml {
    my ($vendor) = @_;
    _validate_vendor($vendor);
    return ( Whostmgr::ModSecurity::vendor_meta_prefix() . '/meta_' . $vendor . '.yaml' );
}

sub _vendor_meta_cache {
    my ($vendor) = @_;
    _validate_vendor($vendor);
    return ( Whostmgr::ModSecurity::vendor_meta_prefix() . '/meta_' . $vendor . '.cache' );
}

sub _validate_vendor {
    my ($vendor) = @_;

    # All vendor names should be the name of a directory directly underneath the vendor prefix.
    my ($valid_vendor) = $vendor =~ m{^([a-zA-Z0-9_\-]+)$}
      or Carp::croak( lh()->maketext( 'The following vendor name is not valid: [_1]', $vendor ) );

    return $valid_vendor;
}

sub _exception_string {
    my ($exception) = @_;
    if ( eval { $exception->isa('Cpanel::Exception') } ) {
        return $exception->get_string;
    }
    return $exception;
}

1;
