package Cpanel::ProgLang::Supported::php;

# cpanel - Cpanel/ProgLang/Supported/php.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::ProgLang::Supported::php

Note: All Cpanel::ProgLang namespaces and some attribute inconsistencies will change in ZC-1202. If you need to use Cpanel::ProgLang please note the specifics in ZC-1202 so the needful can be had.

=head1 SYNOPSIS

    use Cpanel::ProgLang ();

    my $php = Cpanel::ProgLang->new( type => 'php' );

    my $lang_type = $php->type();

    my $parent = $php->parent();

    my @packages = $php->get_installed_packages();

    if ( $php->is_package_installed( 'package' => 'ea-php54' ) {
        print "hooray\n";
    }

    my $sys_package = $php->get_system_default_package();

    $php->set_system_default_package( 'package' => 'ea-php54' );

    my $lang_obj = $php->get_package( 'package' => 'ea-php54' );

    my $ini = $php->get_ini( 'package' => 'ea-php54' );

=head1 DESCRIPTION

Cpanel::ProgLang::Supported::php is the language-specific driver class to
allow the cPanel webserver configuration mechanism to support PHP as
an application language.

Typically, this will not be instantiated directly, but rather
retrieved through the Cpanel::ProgLang-E<gt>new() method.

Most methods within this class will expect arguments as a series of
hash keys and values, and will die with a Cpanel::Exception if one of
the required arguments is not present.

=cut

use v5.014;
use strict;
use warnings;
use Cpanel::Exception        ();
use Cpanel::ProgLang::Conf   ();
use Cpanel::ProgLang::Object ();
use Cpanel::CachedCommand    ();
use Cpanel::LoadModule       ();
use Cpanel::SysPkgs::SCL     ();
use Cpanel::Imports;

=head2 Cpanel::ProgLang::Supported::php-E<gt>new()

Create a new PHP object.

=head3 Required argument keys

=over 4

=item parent

A handle to the Cpanel::ProgLang object which should have called this
method.

=back

=head3 Returns

A blessed reference to a Cpanel::ProgLang::Supported::php object.

=head3 Dies

If no PHP installations can be found, a Cpanel::Exception will result.

=head3 Notes

Currently, this expects all PHP installations to use 'ea-php' as the
start of the package name.  Once the EA4 package manager can supply
the appropriate information, this should depend on provided resources
instead.

This should not be called directly.  The Cpanel::ProgLang-E<gt>new()
method should be used instead.

The parent member is currently unused.  It may not be needed at all.

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'parent' ] ) unless defined $args{'parent'};

    my @installed;

    for my $pkg ( @{ Cpanel::SysPkgs::SCL::get_scl_versions(qr/\w+-php/) } ) {
        my $need_dir = Cpanel::SysPkgs::SCL::get_scl_prefix($pkg) . "/root/etc";
        if ( -d $need_dir ) {
            push @installed, $pkg;
        }
        else {
            logger->warn("Ignoring SCL “$pkg” because it does not have the right /etc dir ($need_dir).\n");    # plain warn() results in yellow box in cPanel that says "A warning occurred while processing this directive. [show]"
        }
    }

    die Cpanel::Exception::create( 'FeatureNotEnabled', q{“[_1]” is not installed on the system.}, ['PHP'] ) unless @installed;
    return bless( { _type => 'php', _installed => \@installed, _parent => $args{'parent'} }, $class );
}

=head2 $php-E<gt>type()

Retrieve the language type.

=head3 Returns

The language type for this object, which will be 'php'.

=cut

sub type {
    my $self = shift;
    return lc $self->{_type};
}

=head2 $php-E<gt>parent()

Retrieve the parent Cpanel::ProgLang object.

=head3 Returns

A reference to the creator of this object.

=cut

sub parent {
    my $self = shift;
    return $self->{_parent};
}

=head2 $php-E<gt>get_installed_packages()

Retrieve the installed packages for our language.

=head3 Returns

An array ref of installed package names for this language type.

=head3 Notes

This method returns a copy of the list of package names, so any
modifications by callers will not disrupt the internal state of the
object.

=cut

sub get_installed_packages {
    my $self      = shift;
    my @installed = sort @{ $self->{_installed} };
    return \@installed;
}

=head2 $php-E<gt>is_package_installed()

Retrieve the installed state of a language package.

=head3 Required argument keys

=over 4

=item package

The name of a package which we would like the installed state.

=back

=head3 Returns

1 if the supplied package is installed, or is 'inherit'; 0 otherwise.

=cut

sub is_package_installed {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{'package'};

    my $package = $args{'package'};
    return 1 if $package eq 'inherit';
    return grep( /\A\Q$package\E\z/, @{ $self->{_installed} } ) ? 1 : 0;
}

=head2 $php-E<gt>get_system_default_package()

Retrieve the currently-set system default package name for PHP.

=head3 Returns

The package name of the current system default setting.  If there is
no current setting, undef.

=cut

sub get_system_default_package {
    my $self = shift;
    my $conf = Cpanel::ProgLang::Conf->new( type => $self->type() );
    return $conf->get_system_default_package();
}

=head2 $php-E<gt>set_system_default_package()

Set the system default package name for PHP.

=head3 Required argument keys

=over 4

=item package

The name of a package to use for the system default.

=back

=head3 Returns

The result of the Cpanel::ProgLang::Conf object making the setting.

=head3 Dies

If the package argument is not valid, a Cpanel::Exception will result.

=head3 Notes

=cut

sub set_system_default_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{'package'};
    unless ( $self->is_package_installed(%args) ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', q{The “[_1]” version “[_2]” is not installed on the system.}, [ 'PHP', $args{'package'} ] );
    }

    my $conf = Cpanel::ProgLang::Conf->new( type => $self->type() );
    return $conf->set_system_default_package( info => $args{'package'} );
}

=head2 $php-E<gt>get_package()

Generate a Cpanel::ProgLang::Object which contains the specifics for a
package.

=head3 Required argument keys

=over 4

=item package

The name of the package for which we want a Cpanel::ProgLang::Object.

=back

=head3 Returns

A blessed reference to a Cpanel::ProgLang::Object.

=head3 Dies

If the specified package is not installed, a Cpanel::Exception will
result.

=cut

sub get_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{'package'};

    my $package = $args{'package'};
    my %data    = ( type => 'php' );

    # get installation prefix directory
    my $prefix = Cpanel::SysPkgs::SCL::get_scl_prefix($package);
    die Cpanel::Exception::create( 'FeatureNotEnabled', q{The “[_1]” package “[_2]” is not installed on the system.}, [ 'PHP', $package ] ) unless $prefix;
    $data{install_prefix} = "$prefix/root";

    # get list of PHP's capabilities
    my $path = "$data{install_prefix}/usr/bin/php-cgi";
    if ( -x $path ) {
        $data{sapi}{cgi} = $data{sapi}{fcgi} = { path => $path };    # PHP supports both cgi and fcgi with the same binary
    }

    # NOTE: We're not going to pass this along to the user.  We just need this so that
    # we can get the PHP version.
    $path = "$data{install_prefix}/usr/bin/php";
    $data{sapi}{cli} = { path => $path } if -x $path;

    # Disable FPM for now (ZC-1185)
    #$path = "$data{install_prefix}/usr/sbin/php-fpm";
    # we do not want this to advertise this handler
    #$data{sapi}{fpm} = { path => $path } if -x $path;

    # TODO: check for litespeed support

    # Get PHP version using one of the following sapis (not apache2)
    my $sapi = ( grep { defined $data{sapi}{$_} && defined $data{sapi}{$_}{path} } qw( cli cgi ) )[0];
    die Cpanel::Exception::create( 'FeatureNotEnabled', q{The “[_1]” package does not provide an executable binary.}, [$package] ) unless $sapi;
    my $vline   = ( split( /\n+/, Cpanel::CachedCommand::cachedcommand( $data{sapi}{$sapi}{path}, '-n', '-v' ) ) )[0];
    my $version = $vline ? ( split( /\s+/, $vline ) )[1] : undef;    # e.g. PHP 5.4.45 (cli) (built: Sep  9 2015 14:26:04)
    die Cpanel::Exception::create( 'FeatureNotEnabled', q{The “[_1]” package does not expose a version number.}, [$package] ) if ( !$version || $version !~ /^\d+\./ );
    $data{version} = $version;

    # NOTE: This assumes redhat directory style
    my $major = $version =~ s/\A(\d+)\..*\z/$1/r;
    my $lib   = 'lib64';
    $path = "$data{install_prefix}/usr/$lib/apache2/modules/libphp$major.so";                                                         # php6 anyone?
    $data{sapi}{apache2} = { path => $path, mime_type => 'application/x-httpd-php', module => qq{php${major}_module} } if -s $path;

    $data{package_name} = $package;
    $data{file_ext}     = [ '.php', ".php$major", '.phtml' ];
    $data{lang}         = $self;

    delete $data{sapi}{cli};                                                                                                          # remember, we're not passing this back to the user

    return Cpanel::ProgLang::Object->new( \%data );
}

=head2 $php-E<gt>get_ini()

Retrieve a Cpanel::ProgLang::Supported::php::Ini object.

=head3 Required argument keys

=over 4

=item package

The package name for which we need the Ini object.

=back

=head3 Returns

A Cpanel::ProgLang::Supported::php::Ini object.

=head3 Notes

This is a language-specific method, in contrast with most of the
methods above.

=cut

sub get_ini {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{package};

    Cpanel::LoadModule::load_perl_module('Cpanel::ProgLang::Supported::php::Ini');

    return Cpanel::ProgLang::Supported::php::Ini->new( lang => $self, package => $args{package} );
}

=head1 CONFIGURATION AND ENVIRONMENT

The module has no dependencies on environment variables.  Any of the
configuration files for this language should be handled by the
I<Cpanel::ProgLang::Conf> class.

=head1 DEPENDENCIES

Cpanel::Exception, Cpanel::ProgLang::Conf, Cpanel::ProgLang::Object,
Cpanel::ProgLang::Supported::php::Ini, and Cpanel::SysPkgs::SCL

=head1 SEE ALSO

L<Cpanel::ProgLang::Overview>, L<Cpanel::ProgLang>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;
