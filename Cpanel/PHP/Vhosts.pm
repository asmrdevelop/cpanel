package Cpanel::PHP::Vhosts;

# cpanel - Cpanel/PHP/Vhosts.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::PHPFPM                       ();
use Cpanel::PHPFPM::Get                  ();
use Cpanel::ProgLang                     ();
use Cpanel::WebServer                    ();
use Cpanel::HttpUtils::ApRestart::BgSafe ();

=pod

=encoding utf-8

=head1 NAME

Cpanel::PHP::Vhosts - Modify and fetch php settings for a vhost.

=head1 SYNOPSIS

 my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_users( [$user] );

 my $php_vhost_versions = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config($php_config_ref);

 my $setup_vhosts_for_php = Cpanel::PHP::Vhosts::setup_vhosts_for_php($php_vhost_versions);

=head1 DESCRIPTION

This module primary purpose is to perform the steps needed
to setup the each virtualhost and the user's home directory
with the php configuration.

It also provides a convenience get_php_vhost_versions_from_php_config
function which allows the configuration to be modified before
it is passed to setup_vhosts_for_php.

=head1 NOTES

This modules requires EasyApache4 and will return empty results if it
is not installed.

=head1 METHODS

=head2 setup_vhosts_for_php

This function configures each vhost and creates the needed
files in the users home directory based on the php configuration
passed in.

=head3 Warning - Slow!

This module function uses the Cpanel::WebServer module to setup
php for each virtualhost.  Cpanel::WebServer has to be run at the user
and will calls adminbins with esclated privs.  This is not currently
very efficient.

=head3 Arguments

Thje first argument is an arrayref from get_php_vhost_versions_from_php_config

The second is a hashref of objects that can be passed to avoid their creation
in this function:

   proglang_php:  A Cpanel::ProgLang->new( type => 'php' ) object
   webserver:     A Cpanel::WebServer->new() object

The third is a hashref of options to pass to set_vhost_lang_packages

=head3 Return Value

A hashref similar to the below:

 {
    'succcess' => ['happy',....],
    'failure'  => [Cpanel::Exception,...]
 }

=cut

sub setup_vhosts_for_php {
    my ( $php_vhost_versions, $objs_hr, $opts_hr ) = @_;

    $opts_hr ||= {};
    my $php                                   = ( $objs_hr && $objs_hr->{'proglang_php'} ) || Cpanel::ProgLang->new( type => 'php' );
    my $ws                                    = ( $objs_hr && $objs_hr->{'webserver'} )    || Cpanel::WebServer->new();
    my $responsible_for_userdata_cache_update = $opts_hr->{'skip_userdata_cache_update'} ? 0 : 1;
    my $ref                                   = { 'success' => [], 'failure' => [] };
    my %all_users;

    foreach my $vhost ( @{$php_vhost_versions} ) {
        next unless $vhost->{'account'};
        local $@;
        eval {
            Cpanel::PHPFPM::set_php_fpm( $vhost->{'account'}, $vhost->{'vhost'}, $vhost->{'php_fpm'}, $vhost->{'php_fpm_pool_parms'} );

            # set_vhost_lang_packages already updates the userdata
            # cache.  We do not need to do it here
            my $returns = $ws->set_vhost_lang_packages(
                %$opts_hr,
                'skip_userdata_cache_update' => 1,                        # This function will do the update unless the caller is responsible
                'user'                       => $vhost->{'account'},      #
                'vhosts'                     => [ $vhost->{'vhost'} ],    #
                'lang'                       => $php,                     #
                'package'                    => $vhost->{'version'}       #
            );

            foreach my $key (qw(success failure)) {
                push @{ $ref->{$key} }, @{ $returns->{$key} };
            }
        };

        # We still want to make sure we update the cache if one fails
        # Since we cannot predict what the failure will be we set
        # the %all_users hash even if we have an exception
        warn if $@;

        $all_users{ $vhost->{'account'} } = 1;

        Cpanel::PHP::Vhosts::_update_local_ini_for_user( $php, $vhost );
    }

    # WHM calls php_set_vhost_versions for multiple vhost at once so we take
    # care of the cache update instead of allowing set_vhost_lang_packages to do
    # this since there can be 100s of vhosts in a single call
    if ( $responsible_for_userdata_cache_update && scalar keys %all_users ) {

        # Only do an update if we changed at least one user
        # as update() will fail if no users are passed
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update( keys %all_users, { force => 1 } );
    }

    return $ref;
}

=head2 _update_local_ini_for_user

If the user has a custom session.save_path set in their local ini files, and
the custom session.save_path appears to be associated with a cPanel default
session directory for a version of EA4 PHP, then update the session.save_path
to point toward the updated version of PHP that the user/domain is updating to

=head3 Arguments

The first argument is a 'Cpanel::ProgLang::Supported::php' object

The second argument is a hashref similar to the below:

{
 'account'            => 'bob',
 'documentroot'       => '/home/bob/public_html',
 'homedir'            => '/home/bob',
 'main_domain'        => 1,
 'php_fpm'            => 1,
 'php_fpm_pool_parms' => { ... }
 'version'            => 'ea-php99',
 'phpversion_source'  => 'domain:foo.tld',
 'vhost'              => 'bob.tld'
},

=head3 Return Value

This function returns undef, or it dies for various reasons.

=cut

sub _update_local_ini_for_user {
    my ( $php, $vhost ) = @_;

    my $local_ini = $vhost->{documentroot} . '/php.ini';

    return unless -s $local_ini;

    my $package    = $vhost->{version} eq 'inherit' ? $php->get_system_default_package() : $vhost->{version};
    my $ini        = $php->get_ini( 'package' => $package );
    my $directives = $ini->get_basic_directives( path => $local_ini );

    my $session_save_path;
    foreach my $directive (@$directives) {

        # 1.  It needs to be the correct key
        # 2.  Ensure that the session directory is different
        # 3.  Only update the session directory if it appears to be using the
        #     cPanel default for the former PHP version
        if (   $directive->{key} eq 'session.save_path'
            && $directive->{value} ne "/var/cpanel/php/sessions/$package"
            && $directive->{value} =~ m{^/var/cpanel/php/sessions/ea-php[0-9]+$} ) {

            $session_save_path = '/var/cpanel/php/sessions/' . $package;
            last;
        }
    }

    if ($session_save_path) {
        require Cpanel::AccessIds::ReducedPrivileges;
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                $ini->set_directives(
                    path       => $local_ini,
                    directives => { 'session.save_path' => $session_save_path },
                    userfiles  => 1,
                );
            },
            $vhost->{account},
        );
    }

    return;
}

=head2 get_php_vhost_versions_from_php_config

Convert output from Cpanel::PHP::Config into data that can
be consumed by setup_vhosts_for_php

=head3 Arguments

A hashref from Cpanel::PHP::Config::get_php_config_for*

=head3 Return Value

An arrayref similar to the below:

 [
   {
    'account'            => 'bob',
    'documentroot'       => '/home/bob/public_html',
    'homedir'            => '/home/bob',
    'main_domain'        => 1,
    'php_fpm'            => 1,
    'php_fpm_pool_parms' => { ... }
    'version'            => 'ea-php99',
    'phpversion_source'  => 'domain:foo.tld',
    'vhost'              => 'bob.tld'
   },
   ...

=cut

sub get_php_vhost_versions_from_php_config {
    my ($php_config_ref) = @_;
    my %HAS_FPM;
    return [
        map {
            {
                'account'            => $php_config_ref->{$_}{'username'},
                'account_owner'      => $php_config_ref->{$_}{'owner'},
                'documentroot'       => $php_config_ref->{$_}{'documentroot'},
                'homedir'            => $php_config_ref->{$_}{'homedir'},
                'main_domain'        => ( $php_config_ref->{$_}{'domain_type'} && $php_config_ref->{$_}{'domain_type'} eq 'main' ) ? 1 : 0,
                'php_fpm'            => ( ( $php_config_ref->{$_}{'phpversion_or_inherit'} && $php_config_ref->{$_}{'phpversion_or_inherit'} eq 'inherit' ) ? 0                                                                               : ( $HAS_FPM{$_} ||= Cpanel::PHPFPM::Get::get_php_fpm( $php_config_ref->{$_}{'username'}, $_ ) ) ),
                'php_fpm_pool_parms' => ( $HAS_FPM{$_}                                                                                                      ? Cpanel::PHPFPM::get_php_fpm_pool_parms_from_php_config( $php_config_ref->{$_} ) : {} ),
                'version'            => $php_config_ref->{$_}{'phpversion'},          # This won't have string 'inherit' anymore. This will have the inherited PHP version instead.
                'phpversion_source'  => $php_config_ref->{$_}{'phpversion_source'},
                'vhost'              => $_,
            }
        } keys %$php_config_ref
    ];
}

=head2 get_vhosts_by_php_version

This is called by the API layer to get all vhosts that are using a given PHP version.

=head3 Arguments

The first parameter must be the php version number (i.e. ea-php99) followed by
a hashref from Cpanel::PHP::Config::get_php_config_for*

=head3 Return Value

This function returns an array of vhosts that are using the given PHP version as argument, or returns empty array.

=cut

sub get_vhosts_by_php_version {
    my ( $php_version, $php_config_ref ) = @_;
    my @vhosts_by_php_version = grep { $php_version eq $php_config_ref->{$_}{'phpversion_or_inherit'} } ( keys %$php_config_ref );

    return \@vhosts_by_php_version;
}

=head2 php_set_vhost_versions_as_root

This is called from bin/admin/Cpanel/multilang to allow the cPanel UI
set the php version of a set of vhosts.  This code also moves PHP-FPM
around with the new version.

=head3 Arguments

The first parameter must be the php version number (i.e. ea-php99) followd by
the vhosts you want to set the php version for.

=head3 Return Value

This function returns a 1, or it dies for various reasons.

=cut

sub php_set_vhost_versions_as_root {
    my ( $version, $supplied_vhost, $php_config_ref, $rebuild_configs_and_restart ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'version' ] )  if !$version;
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'vhost' ] )    if !$supplied_vhost;
    die Cpanel::Exception::create( 'InvalidParameter', [ 'name' => 'version' ] )  if !( $version =~ m/^(\w+-php|inherit)/ );
    die Cpanel::Exception::create( 'RootRequired',     [ 'name' => 'not root' ] ) if $> != 0;

    my $vhost_versions = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config($php_config_ref);

    # If the web server is litespeed, we will let them switch from a FPM setup
    # to a PHP version without FPM since FPM is not compatible with litespeed.
    # They would had to have been setup with FPM before the switch to litespeed.
    my $names_list = join( '|', map { '^' . $_, '/' . $_ } qw{litespeed lscgid} );
    require Cpanel::PsParser;
    my $litespeed_running = Cpanel::PsParser::get_pids_by_name( qr/$names_list/i, [ "root", "nobody" ] );
    $litespeed_running = $litespeed_running ? 1 : 0;

    foreach my $vhost ( @{$vhost_versions} ) {
        if ( exists $vhost->{'php_fpm'} && $vhost->{'php_fpm'} == 1 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The system cannot set the [asis,PHP] version to “[asis,inherit]” on a domain configured with [asis,PHP-FPM]' )
              if ( $version eq "inherit" );

            require Cpanel::PHPFPM::Installed;
            if ( !Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version_cached($version) ) {
                $vhost->{'php_fpm'} = 0;
            }
        }
    }

    my $package = $version;

    if ( defined $package ) {
        for (@$vhost_versions) {
            $_->{'version'} = $package;
        }
        foreach my $domain ( keys %{$php_config_ref} ) {
            $php_config_ref->{$domain}{'phpversion'} = $package;
        }
    }

    # vhost_version is now up to date with all we want to change in the various vhosts

    my $ref = { 'vhosts' => [], 'errors' => [] };

    if ( !$php_config_ref->{$supplied_vhost} ) {
        push @{ $ref->{'errors'} }, Cpanel::Exception::create( 'InvalidParameter', 'No users correspond to the domain “[_1]”.', [$supplied_vhost] );
    }

    my $setup_vhosts_results = Cpanel::PHP::Vhosts::setup_vhosts_for_php($vhost_versions);

    push @{ $ref->{'errors'} }, @{ $setup_vhosts_results->{'failure'} };

    if ( @{ $ref->{'errors'} } ) {
        die Cpanel::Exception::create( 'Collection', [ 'exceptions' => $ref->{'errors'} ] )->get_string();
    }

    if ($rebuild_configs_and_restart) { rebuild_configs_and_restart() }

    return 1;
}

=head2 rebuild_configs_and_restart($php_config_ref)

Rebuilds PHP configurations and restarts apache and fpm services. Called from
L<C<php_set_vhost_versions_as_root>|/php_set_vhost_versions_as_root>
and C<bin/admin/Cpanel/multilang>.

=head3 Arguments

A hashref from
C<Cpanel::PHP::Config::get_php_config_for*>

=head3 Return Value

Nothing if successful, or a thrown
L<C<Cpanel::Exception>|Cpanel::Exception> on failure.

=cut

sub rebuild_configs_and_restart {
    my ($php_config_ref) = @_;
    rebuild_configs_and_restart_fpm($php_config_ref);
    Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    return;
}

=head2 rebuild_configs_and_restart_fpm($php_config_ref)

Rebuilds PHP configurations and restarts fpm services. Called from
L<C<php_set_vhost_versions_as_root>|/php_set_vhost_versions_as_root>
and C<bin/admin/Cpanel/multilang>.

Unlink rebuild_configs_and_restart_fpm this does not restart apache

=head3 Arguments

A hashref from
C<Cpanel::PHP::Config::get_php_config_for*>

=head3 Return Value

Nothing if successful, or a thrown
L<C<Cpanel::Exception>|Cpanel::Exception> on failure.

=cut

sub rebuild_configs_and_restart_fpm {
    my ($php_config_ref) = @_;

    require Cpanel::PHPFPM::Tasks;
    return if eval {
        Cpanel::PHPFPM::rebuild_files(
            $php_config_ref,
            $Cpanel::PHPFPM::SKIP_HTACCESS,
            $Cpanel::PHPFPM::DO_RESTART,
            $Cpanel::PHPFPM::REBUILD_VHOSTS,
        );
        Cpanel::PHPFPM::Tasks::bg_ensure_fpm_on_boot();
        1;
    };

    # workaround for MissingException false positive in cplint
    my $exception_class_name = 'Cpanel::Exception';
    die Cpanel::Exception::create_raw( $exception_class_name, "Problems with PHP-FPM: $@" );
}

1;
