package Cpanel::AdvConfig::postgres;

# cpanel - Cpanel/AdvConfig/postgres.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::FileUtils::Copy       ();
use Cpanel::Logger                ();
use Cpanel::SafeDir::MK           ();
use Cpanel::CPAN::Hash::Merge     ();
use Cpanel::PostgresUtils         ();
use Cpanel::PostgresUtils::PgPass ();

my $conf;
my $logger = Cpanel::Logger->new();

sub get_config {
    my $args_ref = shift;

    my $configs = build_configs();

    if ( !$configs->{'status'} ) {
        $logger->warn( $configs->{'message'} );
        return;
    }

    # There's caching going on all over the place, so reset the $conf
    if ( exists $args_ref->{'reload'} && $args_ref->{'reload'} ) {
        $conf = {};
    }

    if ( $conf->{'_initialized'} ) {
        return wantarray ? ( 1, $conf ) : $conf;
    }

    if ( $args_ref->{'opts'}->{'allow_no_password'} ) {
        $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $configs->{'trusted'} );
    }
    else {
        $conf = Cpanel::CPAN::Hash::Merge::merge( $conf, $configs->{'defaults'} );
    }

    $conf->{'_initialized'} = 1;
    return wantarray ? ( 1, $conf ) : $conf;
}

sub update_templates {
    my $versioned_service = shift || die "service not specified...can't determine location of templates";
    foreach my $dir ( '/var/cpanel/templates', '/var/cpanel/templates/' . $versioned_service ) {
        Cpanel::SafeDir::MK::safemkdir( $dir, '0755' ) unless ( -d $dir );
    }
    my $system_template = '/usr/local/cpanel/src/templates/' . $versioned_service . '/main.default';
    unless ( -e $system_template ) {
        $logger->warn("Can't locate cPanel supplied template for $versioned_service.  Is this a new unsupported version?");
        $system_template = '/usr/local/cpanel/src/templates/postgres/main.default';
    }
    my $system_mtime    = ( stat($system_template) )[9];
    my $target_template = '/var/cpanel/templates/' . $versioned_service . '/main.default';
    if ( -e $target_template ) {
        my $target_mtime = ( stat($target_template) )[9];
        return if ( $target_mtime > $system_mtime );
    }
    Cpanel::FileUtils::Copy::safecopy( $system_template, $target_template );
    chmod oct(644), $target_template;
}

sub build_configs {

    my $pg_data = Cpanel::PostgresUtils::find_pgsql_data();
    if ( !$pg_data ) {
        return { 'status' => 0, 'message' => 'PostgreSQL not installed' };
    }

    my $version = Cpanel::PostgresUtils::get_version();
    if ( !$version ) {
        return { 'status' => 0, 'message' => 'Could not determine PostgreSQL version' };
    }

    # Defaults
    my $conf_defaults = {
        '_initialized'      => 0,
        '_target_conf_file' => $pg_data . '/pg_hba.conf',
        'hba'               => [
            {
                type     => 'local',
                database => 'samerole',
                user     => 'all',
                ip       => '',
                mask     => '',
                method   => 'md5',
                option   => '',
            },
            {
                type     => 'host',
                database => 'samerole',
                user     => 'all',
                ip       => '127.0.0.200',
                mask     => '255.255.255.255',
                method   => 'pam',
                option   => ( $version >= 8.4 ? 'pamservice=postgresql_cpses' : 'postgresql_cpses' ),
            },
            {
                type     => 'host',
                database => 'samerole',
                user     => 'all',
                ip       => '127.0.0.1',
                mask     => '255.255.255.255',
                method   => 'md5',
                option   => '',
            },
            {
                type     => 'host',
                database => 'samerole',
                user     => 'all',
                ip       => '::1/128',
                mask     => '',
                method   => 'md5',
                option   => '',
            },
            {
                type     => 'local',
                database => 'all',
                user     => 'postgres',
                ip       => '',
                mask     => '',
                method   => 'md5',
                option   => '',
            },
            {
                type     => 'host',
                database => 'all',
                user     => 'postgres',
                ip       => '127.0.0.1',
                mask     => '255.255.255.255',
                method   => 'md5',
                option   => '',
            },

        ],
    };

    my $pg_user = Cpanel::PostgresUtils::PgPass::getpostgresuser();
    if ( !$pg_user ) {
        return { 'status' => 0, 'message' => 'PostgreSQL not installed' };
    }

    my $trusted = {
        '_initialized'      => 0,
        '_target_conf_file' => $pg_data . '/pg_hba.conf',
        'hba'               => [
            {
                type     => 'local',
                database => 'template1',
                method   => ( $version >= 9.1 ? 'peer' : 'ident' ),
                user     => $pg_user,
                ip       => '',
                mask     => '',
                option   => '',
            },
        ],
    };

    return { 'status' => 1, 'defaults' => $conf_defaults, 'trusted' => $trusted };
}

1;
