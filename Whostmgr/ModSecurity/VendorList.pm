
# cpanel - Whostmgr/ModSecurity/VendorList.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::VendorList;

use strict;
use Cpanel::LoadModule                     ();
use Whostmgr::ModSecurity::Parse           ();
use Whostmgr::ModSecurity::Configure       ();
use Digest::MD5                            ();
use Cpanel::CachedDataStore                ();
use Cpanel::Crypt::GPG::Settings           ();
use Cpanel::Crypt::GPG::VendorKeys::Verify ();
use Cpanel::Exception                      ();
use Cpanel::FileUtils::Copy                ();
use Cpanel::Binaries                       ();
use Cpanel::HttpUtils::ApRestart::BgSafe   ();
use Cpanel::HttpUtils::ApRestart::Defer    ();
use Cpanel::Locale 'lh';
use Cpanel::Logger                          ();
use Cpanel::SafeRun::Errors                 ();
use Cpanel::Sync::Digest                    ();
use Cpanel::TempFile                        ();
use Whostmgr::ModSecurity                   ();
use Whostmgr::ModSecurity::ModsecCpanelConf ();
use Whostmgr::ModSecurity::TransactionLog   ();
use Whostmgr::ModSecurity::Vendor           ();
use Whostmgr::ModSecurity::Vendor::Provided ();

use subs qw(_http_download _zip_check _zip_extract);

=pod

For:

  1. Finding which vendors are already set up
  2. Adding a new vendor
  3. Uninstalling a vendor

=cut

# The least expensive call; all it requires is checking which vendor metadata exists on disk.
sub list_vendor_ids {
    my $dirh;
    _ensure_vendor_meta_dir();

    my @all;

    opendir $dirh, Whostmgr::ModSecurity::vendor_meta_prefix()
      or die lh()->maketext('The vendor metadata directory is not available.') . "\n";
    while ( defined( my $entry = readdir $dirh ) ) {
        if ( $entry =~ m{^meta_(.+)\.yaml$} ) {
            push @all, $1;
        }
    }
    closedir $dirh;

    return \@all;
}

# The medium-expense call; requires loading all vendor metadata from disk.
sub list_objs {
    return [ map { Whostmgr::ModSecurity::Vendor->load( vendor_id => $_ ) } @{ list_vendor_ids() } ];
}

# The most expensive call. Requires:
#   1. Loading all vendor metadata from disk.
#   2. A discovery of the vendor's .conf files on disk (no caching)
#   3. Examining modsec2.cpanel.conf to see which ones are enabled (in-memory caching only)
#   4. Adding in additional entries for vendors that aren't installed, but are known to be installable.
sub list_detail {
    my $vendor_updates = Whostmgr::ModSecurity::ModsecCpanelConf->new->vendor_updates;

    my $installed = [
        map {
            my $vendor_info = $_->export;

            # FIXME: This added detail should be part of the vendor's own output, either by default
            # or via a "detail" method on the vendor. It shouldn't require a call into this module
            # to get at it.
            $vendor_info->{configs} = $_->configs;
            $vendor_info->{in_use}  = $_->in_use;
            $vendor_info->{update}  = $vendor_updates->{ $vendor_info->{vendor_id} } ? 1 : 0;
            $vendor_info;
        } @{ list_objs() }
    ];

    return $installed;
}

sub list_detail_and_provided {

    my $installed = list_detail();
    my $provided  = Whostmgr::ModSecurity::Vendor::Provided::provided_vendors();

    my @installed_and_uninstalled;
    for my $provided_vendor (@$provided) {

        # If this provided vendor is not already installed, then add it to the list.
        if ( !grep { $_->{vendor_id} eq $provided_vendor->vendor_id } @$installed ) {
            push @installed_and_uninstalled, $provided_vendor->export;
        }
    }

    # Add all installed vendors to the list.
    push @installed_and_uninstalled, @$installed;

    return \@installed_and_uninstalled;
}

sub add {
    my ( $yaml_url, $update_validation_callback ) = @_;

    my $logger = Cpanel::Logger->new;

    if ( defined( my $vendor_id = _extract_vendor_id_from_meta_yaml_url($yaml_url) ) ) {

        # In the case of an update, let update() handle this, since the validation performed
        # by the backup restore may fail if update() hasn't moved the included config files
        # back into place yet.
        my $mcc;
        if ( !$update_validation_callback ) {
            $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new;
            $mcc->backup;
        }

        if ( ref eval { Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id ) } ) {
            die lh()->maketext('You have already installed that vendor.') . "\n";
        }

        my ( $vendor, $yaml_file );
        eval {

            # 1. Download the vendor metadata, and load it.

            my $tf           = Cpanel::TempFile->new();
            my $yaml_tempdir = $tf->dir;

            my $yaml_basename = '/meta_' . $vendor_id . '.yaml';
            $yaml_file = Whostmgr::ModSecurity::vendor_meta_prefix() . $yaml_basename;
            my $yaml_tempfile = $yaml_tempdir . $yaml_basename;

            _http_download from => $yaml_url, to => $yaml_tempfile;

            # Verify the signature if downloading from httpupdate.

            if ( $yaml_url =~ qr{^https?://(.*\.cpanel\.net)(.*)} && Cpanel::Crypt::GPG::Settings::signature_validation_enabled() ) {
                _http_download from => $yaml_url . '.asc', to => $yaml_tempfile . '.asc';
                _verify_signature( $yaml_tempfile, $yaml_tempfile . '.asc', $1, $2 );
            }

            # If download and signature verification succeeds, copy YAML file to final location.

            _ensure_vendor_meta_dir();
            Cpanel::FileUtils::Copy::safecopy( $yaml_tempfile, $yaml_file );

            # Load YAML vendor metadata.

            $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
            if ( !$vendor->archive_url ) {
                die lh()->maketext(
                    'The vendor metadata does not contain an entry for your version of [asis,ModSecurity], “[_1]”. The only [numerate,_2,version,versions] of [asis,ModSecurity] this rule set supports [numerate,_3,is,are] [list_and_quoted,_4].',
                    Whostmgr::ModSecurity::version(),
                    scalar( @{ $vendor->supported_versions } ),
                    scalar( @{ $vendor->supported_versions } ),
                    $vendor->supported_versions
                ) . "\n";
            }

            if ( $vendor->in_use ) {

                # This is an unusual condition that should never occur.
                #
                # If this were an update, update() would have already moved the old configs out of the way before calling
                # add(), so there should be no circumstance under which the vendor object loaded from a freshly downloaded
                # YAML file shows any in_use (because even if the includes are still present, the won't show up in in_use
                # unless the configs are also present). If it does show up, this is most likely a sign that this is a fresh
                # install on top of leftover config files which already have includes, and wiping out those leftover configs
                # would likely result in a broken Apache configuration. This state could arise if someone manually deleted the
                # YAML file, making it appear that the vendor was not yet installed. We need to clean up the old includes.

                $vendor->disable_configs();
                $logger->warn(
                    sprintf(    # do not translate
                        'While installing the vendor “%s”, the system encountered unexpected configuration files already enabled for a previous vendor with the same id. Because the vendor install process removes these files prior to installing the new ones, leaving the existing includes would run the risk of putting the Apache configuration in an invalid state. As a precaution, these configuration files are now disabled. If the new vendor has the same configuration files, they will be re-enabled.',
                        $vendor->vendor_id
                    )
                );
            }

            # 2. If this add has a validation callback (used in the case where this add is actually
            # part of an update), then run that.
            if ($update_validation_callback) {
                $update_validation_callback->($vendor);
            }

            # 3. Download and extract the rule set and extract the rule set and extract the rule set and extract the rule set
            my $tempdir = $tf->dir;
            my $zipfile = $tempdir . '/rules.zip';
            _http_download from => $vendor->archive_url, to => $zipfile;
            _zip_check from => $zipfile, name => $vendor->vendor_id . '/', md5 => $vendor->dist_md5, sha512 => $vendor->dist_sha512;
            _zip_extract from => $zipfile, into => Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir(), vendor_id => $vendor->vendor_id;

            # 4. Record the installed_from URL for this vendor
            my $datastore = Cpanel::CachedDataStore::loaddatastore( Whostmgr::ModSecurity::abs_vendor_meta_urls(), 1 );
            $datastore->{data}{$vendor_id} = { url => $yaml_url, distribution => $vendor->distribution };
            $datastore->save();

            # 5. Enable everything, unless this is an update, in which case it should be left as-is, and update()
            # will handle enabling the appropriate things.
            unless ($update_validation_callback) {
                $vendor->enable;
                $vendor->enable_updates;
                $vendor->enable_configs;
            }
        };
        if ( my $add_enable_exception = $@ ) {
            unless ( eval { $add_enable_exception->isa('Cpanel::Exception::ModSecurity::VendorUpdateUnnecessary') } ) {
                $logger->warn( lh()->maketext( 'The system could not add the vendor: [_1]', $add_enable_exception ) );
            }
            eval {
                unlink $yaml_file;                       # first things first, just get this file out of the way, since it needs to be deleted even if the vendor was never instantiated
                unlink $yaml_file . '.asc';              # unlink the signature also
                $vendor->uninstall_most() if $vendor;    # only uninstall_most because we want to keep the installed_from entry

                # Restore the modsec2.cpanel.conf datastore to the state it was in before we started making any changes.
                $mcc->restore_backup if $mcc;
            };
            if ( my $uninstall_exception = $@ ) {
                $logger->warn( lh()->maketext( 'The system could not uninstall the vendor: [_1]', $uninstall_exception ) );
            }
            die $add_enable_exception;
        }

        $vendor->init_dynamic;    # Because we're making changes outside of the actual vendor object, we need to reinitialize some of it before returning it
        $mcc->purge_backup if $mcc;
        Whostmgr::ModSecurity::TransactionLog::log( operation => 'add_vendor', arguments => { url => $yaml_url } );
        return $vendor;
    }

    die lh()->maketext('The provided URL does not point to a valid vendor specification [asis,YAML] file.') . "\n";
}

# Update an existing vendor based on a provided URL to the vendor metadata YAML file.
# This doesn't have to be the same URL it was originally installed from as long as it
# has the same vendor_id in the filename.
sub update {
    my ( $yaml_url, $skip_defer ) = @_;
    my $tf      = Cpanel::TempFile->new();
    my $tempdir = $tf->dir;

    my $logger = Cpanel::Logger->new();

    my $vendor_id = _extract_vendor_id_from_meta_yaml_url($yaml_url)
      || die lh()->maketext('The provided URL does not point to a valid vendor specification [asis,YAML] file.') . "\n";

    my $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );

    # 0. Discover all current configs for the vendor and store them in a list called prev_configs.
    my %prev_configs = map { $_->{config} => 1 } @{ $vendor->configs };

    # 1. Move current configs and metadata into a temporary directory in case we have to restore it.
    my $configs_dir = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir() . '/' . $vendor_id;
    my $yaml_file   = Whostmgr::ModSecurity::vendor_meta_prefix() . '/meta_' . $vendor_id . '.yaml';

    my $defer = do {
        if ($skip_defer) {
            undef;
        }
        else {
            my $obj = Cpanel::HttpUtils::ApRestart::Defer->new( 'lexical' => 1 );
            $obj->block_restarts();
            $obj;
        }
    };

    Cpanel::LoadModule::load_perl_module('File::Copy');
    Cpanel::LoadModule::load_perl_module('File::Copy::Recursive');

    # Unlike rename(), this will work across filesystem boundaries
    eval {
        File::Copy::move( $yaml_file, "$tempdir/metadata" )                or die $!;
        File::Copy::Recursive::dirmove( $configs_dir, "$tempdir/configs" ) or die $!;
    };
    if ($@) {
        die lh()->maketext( q{Before the update, the system failed to move the current configuration files, metadata, or both to a temporary directory: [_1]}, $@ ) . "\n";
    }

    my $mcc = Whostmgr::ModSecurity::ModsecCpanelConf->new( skip_restart => 1 );
    $mcc->backup;

    # 2. Call add() on this YAML URL.
    eval {
        my $update_validation_callback = sub {
            my $updated_vendor = shift;
            if ( $updated_vendor->distribution && $updated_vendor->distribution eq $vendor->inst_dist ) {
                die Cpanel::Exception::create( 'ModSecurity::VendorUpdateUnnecessary', [ vendor_id => $vendor->vendor_id, distribution => $vendor->inst_dist ] );
            }
        };
        add( $yaml_url, $update_validation_callback );
    };

    #    If it fails:
    #     - Verify that the new configs and metadata have already been cleaned up when the install
    #       aborted. If not, consider cleaning them up.
    #     - Move the things in the temporary directory back to where they came from.
    if ( my $exception = $@ ) {

        # If the failed add also left junk behind, get rid of it. (This can't be the original data,
        # because if we had failed to save that in the temporary directory, we would have already died
        # before running the add.)
        if ( -e $configs_dir ) {
            File::Copy::Recursive::dirmove( $configs_dir, "$tempdir/trash" );
        }
        if ( -e $yaml_file ) {
            unlink $yaml_file;
        }

        eval {
            File::Copy::Recursive::dirmove( "$tempdir/configs", $configs_dir ) or die $!;
            File::Copy::move( "$tempdir/metadata", $yaml_file )                or die $!;
            $mcc->restore_backup;
        };
        my $restore_exception = $@;
        if ($restore_exception) {
            die lh()->maketext( q{An error occurred in the attempt to update the vendor. The system could not restore the original configuration: [_1]}, $restore_exception ) . "\n";
        }
        die $exception;
    }

    $mcc->purge_backup;

    # If it succeeds:
    #     - Compare the new list of configs against prev_configs. Any which exist now but didn't exist
    #       in prev_configs should be automatically enabled. (Configs that already existed but were
    #       disabled should be left disabled.) Configs that are enabled but have been deleted will
    #       also need to be disabled.

    $vendor = Whostmgr::ModSecurity::Vendor->load( vendor_id => $vendor_id );
    my %new_configs = map { $_->{config} => 1 } @{ $vendor->configs };

    my @deleted_configs = grep { !$new_configs{$_} } sort keys %prev_configs;
    my @added_configs   = grep { !$prev_configs{$_} } sort keys %new_configs;

    $mcc->manipulate(
        sub {
            my $data = shift;
            delete @{ $data->{active_configs} }{@deleted_configs};
        }
    );

    my %have_ids;
    for my $config ( keys %new_configs ) {
        my $result = Whostmgr::ModSecurity::Parse::get_chunk_objs( Whostmgr::ModSecurity::get_safe_config_filename($config) );
        for my $chunk ( @{ $result->{chunks} } ) {
            $have_ids{ $chunk->id } = 1 if $chunk->id;
        }
    }

    $mcc->remove_srrbi_for_vendor(
        $vendor_id,
        sub {
            my $id = shift;
            if ( !$have_ids{$id} ) {
                $logger->info( lh()->maketext( 'The system has removed [asis,SecRuleRemoveById] for rule ID “[_1]”. The rule no longer exists.', $id ) );
                return 1;
            }
            return;
        }
    );

    for my $added (@added_configs) {
        Whostmgr::ModSecurity::Configure::make_config_active($added);
    }

    $defer->allow_restarts() if $defer;

    # Queue an Apache restart
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();

    Whostmgr::ModSecurity::TransactionLog::log( operation => 'update_vendor', arguments => { url => $yaml_url } );

    return { vendor => $vendor->export, diagnostics => { "prev_configs" => [ map { { config => $_ } } keys %prev_configs ], "new_configs" => $vendor->configs, "deleted_configs" => \@deleted_configs, "added_configs" => \@added_configs } };
}

sub preview {
    my ($url) = @_;

    if ( defined( my $vendor_id = _extract_vendor_id_from_meta_yaml_url($url) ) ) {
        my $tf       = Cpanel::TempFile->new();
        my $tempfile = $tf->file;
        _http_download from => $url, to => $tempfile;

        # vendor_id must be specified even if we're explicitly specifying the file from which to load because
        # nothing other than the filename dictates the vendor_id (and we just extracted it above).
        my $vendor = Whostmgr::ModSecurity::Vendor->load( meta_yaml_file => $tempfile, vendor_id => $vendor_id, installed_from => $url );

        # We have to delete the 'enabled' flag on the API side because the Angular UI code is
        # unable to properly handle the eventual modsec_add_vendor call (where 'enabled' is the
        # name of the attribute which causes the vendor to become enabled) if the preview reports
        # that the vendor is disabled.
        my $vendor_info = $vendor->export;
        delete $vendor_info->{enabled};
        return $vendor_info;
    }

    die lh()->maketext('The provided URL does not point to a valid vendor specification [asis,YAML] file.') . "\n";
}

sub _extract_vendor_id_from_meta_yaml_url {
    my $url = shift;
    if ( $url =~ m{^https?://.*/meta_([a-zA-Z0-9_\-]+)\.yaml$} ) {
        return $1;
    }
    return;
}

sub _ensure_vendor_meta_dir {
    my $dir = Whostmgr::ModSecurity::vendor_meta_prefix();
    if ( !-d $dir ) {
        my $orig_umask = umask 0077;
        mkdir $dir;
        umask $orig_umask;
    }
    return;
}

sub _ensure_vendor_configs_dir {
    my $dir = Whostmgr::ModSecurity::config_prefix() . '/' . Whostmgr::ModSecurity::vendor_configs_dir();
    if ( !-d $dir ) {
        my $orig_umask = umask 0077;
        mkdir $dir;
        umask $orig_umask;
    }
    return;
}

my $curl_bin;

sub _http_download {
    my %args = @_;
    my $from = $args{from} || _missing_parameter( '_http_download', 'from' );
    my $to   = $args{to}   || _missing_parameter( '_http_download', 'to' );

    # If we would use find(), it would return undef
    # which would call this every single time _http_download is called
    $curl_bin ||= Cpanel::Binaries::path('curl');

    if ( $from =~ m{^https?://} ) {

        # 1. follow redirects, 2. quiet, 3. silent, 4. but don't be silent if there's an error, 5. treat server errors (e.g., 404, 500, etc.) as failures
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( $curl_bin, '-LqsSf', '-o', $to, $from );

        if ($?) {
            my $exception = $@;
            die lh()->maketext( 'The system could not download the file “[_1]”: [_2]', $from, $output ) . "\n";
        }

        if ( !-f $to ) {
            die lh()->maketext( 'The system could not find the downloaded file: [_1]', $to ) . "\n";
        }

        return 1;
    }

    die lh()->maketext('The URL you requested is invalid or not a supported scheme.') . "\n";
}

my $unzip_bin;

sub _zip_extract {
    my %args      = @_;
    my $from      = $args{from}      || _missing_parameter( '_zip_extract', 'from' );
    my $into      = $args{into}      || _missing_parameter( '_zip_extract', 'into' );
    my $vendor_id = $args{vendor_id} || _missing_parameter( '_zip_extract', 'vendor_id' );

    # Avoid this being called every time _zip_extract() is called
    $unzip_bin ||= Cpanel::Binaries::path('unzip');

    # Allowing this to do the initial creation will keep the permissions the way we want them.
    _ensure_vendor_configs_dir();

    # If the directory already exists (possibly containing old data), remove it.
    my $predicted_dir_name = $into . '/' . $vendor_id;
    if ( -d $predicted_dir_name ) {
        Cpanel::LoadModule::load_perl_module('File::Path');
        File::Path::rmtree($predicted_dir_name);    # This is only OK because we also clean out any old includes for the vendor
    }

    my $output = Cpanel::SafeRun::Errors::saferunallerrors( $unzip_bin, '-n', $from, '-d', $into );

    die $output if $?;

    return 1;
}

sub _zip_check {
    my %args = @_;
    my $from = $args{from} || _missing_parameter( '_zip_check', 'from' );
    my $name = $args{name} || _missing_parameter( '_zip_check', 'name' );

    # Check digests for zip file.
    # Cpanel::Crypt::GPG::Settings::allowed_digest_algorithms() will factor in the "allow weak checksums" tweak setting.

    my $digest_ok = 0;

    for my $algo ( Cpanel::Crypt::GPG::Settings::allowed_digest_algorithms() ) {
        my $expected_digest = $args{$algo};
        my $real_digest     = Cpanel::Sync::Digest::digest( $from, { algo => $algo } );

        if ( $real_digest eq $expected_digest ) {
            $digest_ok = 1;
            last;
        }
    }

    if ( !$digest_ok ) {
        die lh()->maketext('The downloaded vendor archive does not match the expected digest ([asis,MD5] or [asis,SHA512]).') . "\n";
    }

    $unzip_bin ||= Cpanel::Binaries::path('unzip');
    my $output = Cpanel::SafeRun::Errors::saferunallerrors( $unzip_bin, '-t', $from, $args{name} );
    if ($?) {
        die lh()->maketext('The archive downloaded for that vendor did not contain the expected directory.') . "\n";
    }

    return 1;
}

sub _missing_parameter {
    my ( $func, $param ) = @_;
    die lh()->maketext( q{An internal error occurred while the system attempted to install the vendor. The system could not find the “[_2]” parameter in the “[_1]” function. In some cases, this may indicate corrupt or incomplete vendor metadata.}, $func, $param ) . "\n";
}

sub _verify_signature {
    my ( $file, $sig, $mirror, $url ) = @_;

    my ( $gpg, $gpg_msg ) = Cpanel::Crypt::GPG::VendorKeys::Verify->new(
        vendor     => 'cpanel',
        categories => Cpanel::Crypt::GPG::Settings::default_key_categories(),
    );

    if ( !$gpg ) {
        die lh()->maketext( "Failed to create gpg object: [_1]", $gpg_msg );
    }

    my ( $success, $msg ) = $gpg->files( files => $file, sig => $sig, mirror => $mirror, url => $url );

    if ( !$success ) {
        die lh()->maketext( "Signature verification failed for file “[_1]” using signature “[_2]”: [_3]", $file, $sig, $msg );
    }
    unlink $sig if -f $sig;
    return;
}

1;
