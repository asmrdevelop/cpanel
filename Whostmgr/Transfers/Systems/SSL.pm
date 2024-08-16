package Whostmgr::Transfers::Systems::SSL;

# cpanel - Whostmgr/Transfers/Systems/SSL.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::CachedDataStore         ();
use Cpanel::FileUtils::Dir          ();
use Cpanel::SSL::Utils              ();
use Cpanel::LoadFile                ();
use Cpanel::PEM                     ();
use Cpanel::SSLInstall::Batch       ();
use Cpanel::SSLStorage::Migration   ();
use Cpanel::SQLite::AutoRebuildBase ();

use Try::Tiny;

our $MAX_SSL_OBJECT_SIZE = 1024**2;    # ONE MEG

use base qw(
  Whostmgr::Transfers::SystemsBase::userdataBase
);

sub get_prereq {
    return [ 'IPAddress', 'Domains', 'userdata' ];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores [output,abbr,SSL,Secure Sockets Layer] keys, certificates, and virtual host entries.') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    $self->_migrate_homedir_to_sslstorage();

    $self->_restore_ssl_vhosts();

    Cpanel::SSL::Utils::clear_cache();

    return 1;
}

*restricted_restore = \&unrestricted_restore;

sub _restore_ssl_vhosts {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $ssl_vhost_names_ar = $self->_get_ssl_vhost_names();

    # validated in AccountRestoration.pm if restricted
    my $main_domain = $self->{'_utils'}->main_domain();

    if (@$ssl_vhost_names_ar) {

        # This will already be done during the initial restore
        local $Cpanel::SQLite::AutoRebuildBase::SKIP_INTEGRITY_CHECK = 1;

        my @batch = map {
            [ $_, $self->_get_ssl_key_crt_cab($_) ],
        } @$ssl_vhost_names_ar;

        my ( $results_ar, $finally ) = Cpanel::SSLInstall::Batch::install_for_user(
            $newuser,
            \@batch,
        );

        # We do not create the virtual hosts at this point.
        # Only the vhost configs are created.
        # In Vhosts.pm we will create the actual virtual host
        # entries in httpd.conf
        $finally->skip();

        for my $result_ar (@$results_ar) {
            my ( $status, $result, $apache_error ) = @$result_ar;

            my $out_method = $status ? 'out' : 'warn';

            $self->$out_method( $result . ( $apache_error ? "Error from Apache: $apache_error" : '' ) );
        }
    }

    # AutoSSL / SSL Setup moved to PostRetoreActions since it was happening too soon
    # and using up too much RAM

    # SSLStorage will fill up the CachedDataStore cache
    Cpanel::CachedDataStore::clear_cache();

    return;
}

sub _get_ssl_key_crt_cab {
    my ( $self, $vhost_name ) = @_;

    if ( $self->{'_apache_tls_dir'} ) {
        return $self->_get_apache_tls_resources($vhost_name);
    }

    return $self->_get_pre_apache_tls_resources($vhost_name);
}

sub _get_apache_tls_resources {
    my ( $self, $vhost_name ) = @_;

    my $pem = Cpanel::LoadFile::load("$self->{'_apache_tls_dir'}/$vhost_name");
    my ( $key, $cert, @cab ) = Cpanel::PEM::split($pem);

    return ( $key, $cert, join( "\n", @cab ) );
}

sub _get_pre_apache_tls_resources {
    my ( $self, $vhost_name ) = @_;

    my %FILES;

    my ( $read_ok, $userdata ) = $self->read_extracted_userdata_for_domain("${vhost_name}_SSL");

    if ( !$read_ok ) {
        die $self->_locale()->maketext( "The system failed to read SSL information for the domain “[_1]” from the account backup because of an error: [_2]", $vhost_name, $userdata );
    }

    my ($keybase)  = ( $userdata->{'sslcertificatekeyfile'} =~ m!([^/]*)$! );
    my ($certbase) = ( $userdata->{'sslcertificatefile'}    =~ m!([^/]*)$! );
    my $cabbase;

    if ( $userdata->{'sslcacertificatefile'} ) {
        ($cabbase) = ( $userdata->{'sslcacertificatefile'} =~ m!([^/]*)$! );
    }

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    my $key  = Cpanel::LoadFile::load("$extractdir/sslkeys/$keybase");
    my $leaf = Cpanel::LoadFile::load("$extractdir/sslcerts/$certbase");

    my $cab;

    #A failure to load here needn’t be considered fatal because we’ll
    #probably be able to fetch the CA bundle from the certificate’s
    #caIssuers property.
    try {
        $cab = $cabbase && Cpanel::LoadFile::load("$extractdir/sslcerts/$cabbase");
    }
    catch {
        $self->warn("Failed to load “$vhost_name”’s CA bundle: $_");
    };

    return ( $key, $leaf, $cab );
}

sub _get_ssl_vhost_names {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();
    if ( -d "$extractdir/apache_tls" ) {
        $self->{'_apache_tls_dir'} = "$extractdir/apache_tls";
        return Cpanel::FileUtils::Dir::get_directory_nodes( $self->{'_apache_tls_dir'} );
    }

    #----------------------------------------------------------------------
    # Pre-Apache-TLS logic:
    #
    #We can treat both pre-SSLStorage and SSLStorage backups the same way
    #because the userdata files will point to the correct file to load, and
    #the files are saved in sslkeys and sslcerts in both pre-SSLStorage and
    #SSLStorage/ID names.

    #TODO: Toughen this logic against extra _SSL files.
    #ArchiveManager has logic to get the list of subdomains.

    #As it happens, this logic duplicates Cpanel::Config::userdata::Load;
    #however, that's ok here because the account archive format is independent
    #of how the server stores active user data.
    my @ssldomains;
    my ( $find_ok, $cpmove_userdata_dir ) = $self->find_extracted_userdata_dir();

    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists($cpmove_userdata_dir);
    if ($nodes_ar) {
        return [ map { m<\A(.*)_SSL> ? $1 : () } @$nodes_ar ];
    }

    return [];
}

sub _migrate_homedir_to_sslstorage {
    my ($self) = @_;

    my $newuser = $self->{'_utils'}->local_username();

    my $extractdir = $self->{'_archive_manager'}->trusted_archive_contents_dir();

    return 1 if -e "$extractdir/has_sslstorage";

    $self->start_action("Migrating pre-SSLStorage home directory resources…");

    my ( $ok, $msg, $warning_messages ) = Cpanel::SSLStorage::Migration::homedir_to_sslstorage($newuser);
    if ( !$ok ) {
        $self->warn($msg);
    }
    if ($warning_messages) {
        $self->warn($_) for @$warning_messages;
    }

    return 1;
}

1;
