package Whostmgr::Templates::Command;

# cpanel - Whostmgr/Templates/Command.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OS                                        ();
use Cpanel::Config::Httpd::EA4                        ();
use Cpanel::Server::Type                              ();
use Cpanel::Hash                                      ();
use Cpanel::LoadFile                                  ();
use Cpanel::LoadModule                                ();
use Cpanel::Locale                                    ();
use Cpanel::Template                                  ();
use Whostmgr::ACLS                                    ();
use Whostmgr::Templates::Command::Directory           ();
use Cpanel::Server::WebSocket::App::Shell::WHMDisable ();
use Cpanel::Server::Type                              ();
use Cpanel::FeatureFlags                              ();

use Try::Tiny;

my $command_tmpl;
my $cache_key;

=head1 DESCRIPTION

Utility functions to process and cache command.tmpl

=cut

=head1 SUBROUTINES

=cut

sub _get_cache_dir {
    return Whostmgr::Templates::Command::Directory::get_cache_dir();
}

=head2 clear_cache

=head3 Purpose

Clear memory cache

=cut

sub clear_cache {
    $command_tmpl = undef;
    return;
}

=head2 clear_cache_key

=head3 Purpose

Reset user cache key

=cut

sub clear_cache_key {
    $cache_key = undef;
    return;
}

=head2 cached_load

=head3 Purpose

Process command.tmpl and cache result in memory and on disk

=head3 Returns

=over

=item Processed command.tmpl data

=back

=cut

sub cached_load {
    return $command_tmpl if $command_tmpl;

    $cache_key ||= _get_user_cache_key();

    _load_cache();
    return $command_tmpl if $command_tmpl;

    # This used to be wrapped in try {}, however if it failed
    # the UI broke because it would return undef and no template
    # would be there.  We have since fixed _generate_cache() to
    # work without root privs so there so no longer be a concern
    # about it generating an exception under normal circumstances.
    _generate_cache();

    return $command_tmpl;
}

=head2 get_cache_key

=head3 Purpose

Returns the cache key for a reseller

=head3 Returns

=over

=item user cache key

=back

=cut

sub get_cache_key {
    return $cache_key if $cache_key;
    return $cache_key = _get_user_cache_key();
}

sub _is_ea3 {
    return 0;
}

sub _get_user_cache_key {

    my @cache_items = (
        Cpanel::Config::Httpd::EA4::is_ea4() ? 4 : 0,
        _postgres_installed(),
        Cpanel::OS::is_cloudlinux() ? 1 : 0,

        # build revision
        ( stat('/usr/local/cpanel/version') )[9],

        # license
        ( stat('/usr/local/cpanel/cpanel.lisc') )[9],

        # feature flags
        Cpanel::FeatureFlags::last_modified(),

        scalar( _get_current_locale() ),

        # If Cpanel::Template::Plugin::Whostmgr is not loaded
        # fallback to the manual read.
        $Cpanel::Template::Plugin::Whostmgr::max_users // Cpanel::Server::Type::get_max_users(),

        Cpanel::Server::Type::is_dnsonly(),

        Cpanel::Server::WebSocket::App::Shell::WHMDisable->is_on(),
    );

    my @acls = map { $Whostmgr::ACLS::ACL{$_} } sort keys %Whostmgr::ACLS::ACL;

    return $cache_key = Cpanel::Hash::get_fastest_hash( join( '', ( @cache_items, @acls ) ) );
}

sub _postgres_installed {
    return ( -e '/usr/bin/psql' || -e '/usr/local/bin/psql' ) ? 1 : 0;
}

sub _load_cache {
    my $datastore_file = _get_datastore_file();
    return unless -e $datastore_file;

    $command_tmpl = ${ Cpanel::LoadFile::loadfile_r($datastore_file) };
    return;
}

sub _generate_cache {
    local $ENV{'cp_security_token'} = '/cpsess0000000000';

    my ( $status, $template_data ) = Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'menu/command.tmpl',
            'data'          => {},
        },
    );

    if ( !$status ) {
        die "Failed to generate cache: $template_data";
    }

    $command_tmpl = $$template_data;

    # We may call this code from SecurityPolicy, where we run unprivileged.
    # We need to generate the template but not write it to disk.
    return if $>;
    my $cache_dir = _get_cache_dir();
    if ( !-e $cache_dir ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
        Cpanel::SafeDir::MK::safemkdir( $cache_dir, '0700' );
    }

    #Don’t die() just because we fail to write out a cache file.
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');
        Cpanel::FileUtils::Write::overwrite( _get_datastore_file(), $command_tmpl, 0600 );
    }
    catch {
        warn "Failed to write cache: $_";
    };

    return;
}

sub _get_datastore_file {
    my $cache_dir = _get_cache_dir();
    return "$cache_dir/$cache_key";
}

sub _get_current_locale {
    return Cpanel::Locale::lh()->get_language_tag();
}

1;
