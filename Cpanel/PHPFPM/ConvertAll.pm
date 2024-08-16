package Cpanel::PHPFPM::ConvertAll;

# cpanel - Cpanel/PHPFPM/ConvertAll.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PHPFPM::Installed ();
use Cpanel::PHPFPM::Tasks     ();
use Cpanel::PHP::Config       ();
use Cpanel::PHP::Vhosts       ();
use Cpanel::ProgLang          ();
use Cpanel::ServerTasks       ();
use Cpanel::WebServer         ();

use File::Path ();

use Try::Tiny;

our $logger;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::ConvertAll

=head1 SYNOPSIS

use Cpanel::PHPFPM::ConvertAll;

my $ret = Cpanel::PHPFPM::ConvertAll::convert_vhost ($logger, $vhost_entry, $default_php, $php_config_ref);

my $ret = Cpanel::PHPFPM::convert_all ();

=head1 DESCRIPTION

Subroutines for converting accounts to PHP-FPM.

=head1 SUBROUTINES

=head2 log_info

This call replaces the $logger->info.  Depending whether $logger
is defined or not will send it to either $logger or nothing.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.
If logger is defined it will go to $logger->info.

=item C<< $msg >>

The message to log.

=back

B<Returns>:

Nothing.

=cut

sub log_info {
    my ( $logger, $msg ) = @_;

    if ( defined $logger ) {
        $logger->info($msg);
    }

    return;
}

=head2 log_warn

This call replaces the $logger->warn.
If logger is defined it will go to $logger->warn.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.
If logger is defined it will go to $logger->warn.

=item C<< $msg >>

The message to log.

=back

B<Returns>:

Nothing.

=cut

sub log_warn {
    my ( $logger, $msg ) = @_;

    if ( defined $logger ) {
        $logger->warn($msg);
    }

    return;
}

=head2 convert_vhost

This subroutine converts one vhost (domain) to PHP-FPM, all the heavy lifting is in here.  Note this will
exit quickly if the vhost already has PHP-FPM turned on.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.

=item C<< $vhost_entry >>

A vhost_entry ref that comes from this routine and its sister routines.

Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config

=item C<< $default_php >>

The PHP version to use if the vhost is still set to "inherit".   Must be of the form:

'ea-phpXX' e.g. 'ea-php99'

=item C<< $php_config_ref >>

A php_config_ref that comes from this routine and its sister routines.

Cpanel::PHP::Config::get_php_config_for_all_domains

=item C<< $objs_hr >>

The hashref of objects that get passed to
Cpanel::PHP::Vhosts::setup_vhosts_for_php. See that function’s documentation
for more details.

=item C<< $opts_hr >>

The hashref of options that get passed to
Cpanel::PHP::Vhosts::setup_vhosts_for_php. See that function’s documentation
for more details.
=back

B<Returns>:

Returns a 0 if vhost is not converted

Returns a 1 if it is converted and

Returns a -1 if there were errors

=back

=cut

sub convert_vhost {    ## no critic qw(Subroutines::ProhibitManyArgs) -- this likely should have been an object class, but too late now to refactor
    my ( $logger, $vhost_entry, $default_php, $php_config_ref, $objs_hr, $opts_hr ) = @_;

    return 0 if ( $vhost_entry->{'php_fpm'} == 1 );

    # do we need to set php version?

    my $vhost_versions = [$vhost_entry];
    my $domain         = $vhost_entry->{'vhost'};

    # if this is set as inherited we first configure the php version
    if ( exists $vhost_entry->{'phpversion_source'}->{'system_default'}
        && $vhost_entry->{'phpversion_source'}->{'system_default'} == 1 ) {

        $vhost_entry->{'version'} = $default_php;
        $php_config_ref->{$domain}{'phpversion'} = $default_php;

        # we set the version of php first, because at the time of this writing
        # if it is set to inherit (which is this case) you have to set the
        # version first and then the status of php_fpm

        log_info( $logger, "Attempting to set version of php for domain $vhost_entry->{'vhost'}" );
        my $errors               = 0;
        my $setup_vhosts_results = Cpanel::PHP::Vhosts::setup_vhosts_for_php( $vhost_versions, $objs_hr, $opts_hr );
        foreach my $error ( @{ $setup_vhosts_results->{'failure'} } ) {
            log_warn( $logger, $error->get_string() );
            $errors++;
        }

        if ($errors) {
            log_info( $logger, "Failed to set php version" );
            return -1;
        }
        else {
            log_info( $logger, "php version successfully set" );
        }
    }

    # now add php_fpm

    log_info( $logger, "Attempting to set php_fpm for domain $vhost_entry->{'vhost'}" );

    if ( !Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version_cached( $vhost_entry->{'version'} ) ) {

        # The stack trace that accompanies the warning, is not desired in the UI
        log_info( $logger, "PHP-FPM is not available for $vhost_entry->{'version'}, domain ($vhost_entry->{'vhost'}) not converted" );
        return -1;
    }

    my $errors = 0;
    $vhost_entry->{'php_fpm'} = 1;
    my $setup_vhosts_results = Cpanel::PHP::Vhosts::setup_vhosts_for_php( $vhost_versions, $objs_hr, $opts_hr );
    foreach my $error ( @{ $setup_vhosts_results->{'failure'} } ) {
        log_warn( $logger, $error->get_string() );
        $errors++;
    }

    if ($errors) {
        log_info( $logger, "Failed to set php-fpm" ) if $errors;
    }
    else {
        log_info( $logger, "php-fpm successfully set" );
    }

    return -1 if $errors;
    return 1;
}

=head2 _convert_domains

This subroutine converts the domains passed in (via php_config_ref) to
PHP-FPM.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.

=item C<< $php_config_ref >>

This structure contains 1 or many vhosts to be converted.

=item C<< $default_php >>

If the domain does not have the version of PHP set, it will be set
to $default_php.

=item C<< $do_restart >>

If set to 1 or not defined it will rebuild the underlying files and
restart Apache and Apache FPM.

=back

B<Returns>: 1

=cut

sub _convert_domains {
    my ( $logger, $php_config_ref, $default_php, $do_restart ) = @_;

    $do_restart //= 1;

    my $versions_ref = Cpanel::PHP::Vhosts::get_php_vhost_versions_from_php_config($php_config_ref);
    my $total        = @{$versions_ref};
    my $idx          = 0;
    my $percent;

    my $php_config_final_ref = {};

    my $objs_hr = { proglang_php => Cpanel::ProgLang->new( type => 'php' ), webserver => Cpanel::WebServer->new() };

    my %updatecache_users;
    foreach my $vhost_entry ( @{$versions_ref} ) {
        $percent = ( $idx / $total ) * 100.0;

        log_info( $logger, "Converting Domain $vhost_entry->{'vhost'} for user $vhost_entry->{'account'}" );

        log_info( $logger, sprintf( "Percentage Complete %.2f", $percent ) );

        $idx++;

        next if ( $vhost_entry->{'php_fpm'} == 1 );

        local $@;

        eval { convert_vhost( $logger, $vhost_entry, $default_php, $php_config_ref, $objs_hr, { skip_userdata_cache_update => 1 } ); };

        if ($@) {
            log_warn( $logger, "$@" );
        }

        # We still want to make sure we update the cache if one fails
        # Since we cannot predict what the failure will be we set
        # the %updatecache_users hash even if we have an exception

        $updatecache_users{ $vhost_entry->{'account'} } = 1;
        $php_config_final_ref->{ $vhost_entry->{'vhost'} } = $php_config_ref->{ $vhost_entry->{'vhost'} };
    }

    if ( scalar keys %updatecache_users ) {

        # Only do an update if we changed at least one user
        # as update() will fail if no users are passed
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update( keys %updatecache_users, { force => 1 } );
    }

    Cpanel::PHP::Vhosts::rebuild_configs_and_restart($php_config_final_ref) if $do_restart;

    return 1;
}

=head2 convert_all

This subroutine converts all domains/vhosts on the server to use PHP-FPM.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.

=back

B<Returns>: 1

=cut

sub convert_all {
    my ($logger) = @_;

    # need default php

    my $php         = Cpanel::ProgLang->new( type => 'php' );
    my $default_php = $php->get_system_default_package();

    my $default_php_fpm_installed = Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version_cached($default_php);
    if ( !$default_php_fpm_installed ) {
        log_warn( $logger, "PHP-FPM is not installed for the Default PHP" );
        return 0;
    }

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_all_domains();

    return _convert_domains( $logger, $php_config_ref, $default_php, 1 );
}

=head2 convert_user_domain

This subroutine converts this one domain to PHP_FPM.

=over 3

=item C<< $logger >>

Cpanel::Logger object where all actions and warnings are reported to.

=item C<< $domain >>

The domain to convert.

=item C<< $do_restart >>

If set to 1 or not defined it will rebuild the underlying files and
restart Apache and Apache FPM.

=back

B<Returns>: 1

=cut

sub convert_user_domain {
    my ( $logger, $domain, $do_restart ) = @_;

    $do_restart //= 1;

    # need default php
    my $php         = Cpanel::ProgLang->new( type => 'php' );
    my $default_php = $php->get_system_default_package();

    my $default_php_fpm_installed = Cpanel::PHPFPM::Installed::is_fpm_installed_for_php_version_cached($default_php);
    if ( !$default_php_fpm_installed ) {
        log_warn( $logger, "PHP-FPM is not installed for the Default PHP" );
        return 0;
    }

    my $php_config_ref = Cpanel::PHP::Config::get_php_config_for_domains_consider_addons( [$domain] );

    return _convert_domains( $logger, $php_config_ref, $default_php, $do_restart );
}

=head2 queue_convert_domain

This subroutine queues up a queueprocd entry to convert this domain.

=over 3

=item C<< $domain >>

The domain to convert.

=back

B<Returns>: 1

=cut

sub queue_convert_domain {
    my ($domain) = @_;

    try {
        Cpanel::PHPFPM::Tasks::queue_enable_fpm_domain_in_dir($domain);
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], $Cpanel::PHPFPM::Constants::delay_for_rebuild, "enable_fpm" );
        Cpanel::ServerTasks::schedule_task( ['PHPFPMTasks'], 240,                                           "ensure_fpm_on_boot" );
    }
    catch {
        print "ERROR QUEUING :$_:\n";
    };

    return 1;
}

1;
