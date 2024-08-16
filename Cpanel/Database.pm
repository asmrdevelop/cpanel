package Cpanel::Database;

# cpanel - Cpanel/Database.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LoadModule ();
use Cpanel::SafeFind   ();
use Cpanel::Debug      ();
use Cpanel::Hostname   ();

my $singleton;

sub new ( $class, $args = {} ) {

    reset_singleton() if $args->{reset};

    $singleton //= sub {

        # Both must be defined if one is defined.
        if ( length( $args->{db_type} ) xor length( $args->{db_version} ) ) {
            my $missing = $args->{db_type} ? 'db_version' : 'db_type';
            die("You must define a $missing.");
        }

        my $vendor  = $args->{db_type};
        my $version = $args->{db_version};

        if ( !$vendor && !$version ) {
            ( $vendor, $version ) = get_vendor_and_version();
        }

        my $module = get_module_name( $vendor, $version );
        Cpanel::LoadModule::load_perl_module($module);
        return $module->new($args);
      }
      ->();

    return $singleton;
}

sub new_all_supported ( $class, $args = {} ) {

    my @database_objs;

    for my $ns ( _supported_database_namespaces() ) {
        my $dir = _base_dir() . $ns;
        $dir =~ s/::/\//g;

        my $mods = _find_mods($dir);

        for my $mod (@$mods) {
            my $package = $ns . '::' . $mod;
            Cpanel::LoadModule::load_perl_module($package);
            my $obj = $package->new();
            push( @database_objs, $obj ) if $obj->supported;
        }
    }

    return \@database_objs;
}

sub reset_singleton {
    undef $singleton;
    return 1;
}

sub get_vendor_and_version () {
    local $@;
    my ( $version_info, $vendor, $version );

    require Cpanel::AdminBin::Call;
    require Cpanel::MysqlUtils::Version;

    # Non-root users cannot retrieve version information directly.
    if ($>) {
        $version_info = eval { Cpanel::AdminBin::Call::call(qw{ Cpanel mysql GET_VERSION }) };
    }
    else {
        $version_info = eval { Cpanel::MysqlUtils::Version::current_mysql_version() };
    }
    my $err = $@;

    $version = $version_info->{short} || $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
    $vendor  = 'MySQL';

    if ( my $full = $version_info->{full} ) {
        $vendor = q[MariaDB] if $full =~ qr{mariadb}i || $full =~ qr{^1\d\.}a;
    }

    if ($err) {
        Cpanel::Debug::log_info("Problems were encountered while detecting the database version: $err\nContinuing with $vendor $version.");
    }

    return ( $vendor, $version );
}

sub get_module_name ( $db_type, $db_version ) {
    return unless $db_type =~ m/^(?:mariadb|mysql)$/i && $db_version =~ m/^[0-9.]+$/;

    $db_type    =~ s/mysql/MySQL/gi;
    $db_type    =~ s/mariadb/MariaDB/gi;
    $db_version =~ s/\.//g;

    return "Cpanel::Database::${db_type}::${db_type}${db_version}";
}

sub _supported_database_namespaces {
    return ( 'Cpanel::Database::MySQL', 'Cpanel::Database::MariaDB' );
}

sub _base_dir {
    return '/usr/local/cpanel/';
}

sub _find_mods ($dir) {

    my @modules;

    my $wanted = sub {
        return unless -f $File::Find::name;
        return unless $File::Find::name =~ m<\.pm\z>;
        substr( $_, -3 ) = '';
        push( @modules, $_ );
    };

    Cpanel::SafeFind::find( { wanted => $wanted }, $dir );

    return \@modules;
}

1;

sub _localhosts_for_root_user {
    return ( 'localhost', '127.0.0.1', '::1', Cpanel::Hostname::gethostname() );
}

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database

An abstraction for database versions.

=head1 SYNOPSIS

Get a database object for the currently running database:
my $db = Cpanel::Database->new();

Get database objects for all supported databases as an array ref:
my $dbs = Cpanel::Database->new_all_supported();

=head1 DESCRIPTION

The goal of this module is to provide a way to get access to database version specific code without
needing to be aware of the currently installed database on the server.

=head1 METHODS

=head2 new()

Returns a database version specific object based on the currently running database.

Version detection currently only supports MariaDB and MySQL. This will be resolved to support more in the future.

=head3 Arguments passed as a hash ref:

=over

=item * reset ( Optional )

=over

When enabled this will clear the singleton and return a fresh object. Needed when database versions are changed by an upgrade.

=back

=item * db_type -- String ( Optional )

=over

When used with db_version, this will skip database detection and load the specified database. Currently only supports "mysql" and "mariadb".
If this is set, db_version must also be set.

=back

=item * db_version -- String ( Optional )

=over

When used with db_type, this will skip database detection and load the specified database. If this is set, db_type must also be set.

=back

=back

=head2 new_all_supported()

Returns an array ref of database version specific objects that have the 'supported' class attribute enabled.

It currently searches namespaces that are defined by the helper function '_supported_database_namespaces()'.

=head2 reset_singleton()

Clears the singleton. Useful after database upgrades.
