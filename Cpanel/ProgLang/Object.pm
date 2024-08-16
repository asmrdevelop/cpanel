# Virtual object used to store language-specific implementation.

# cpanel - Cpanel/ProgLang/Object.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# The goal of this is to allow devs to extend (through inheritance).
# It currently contains a basic interface suitable information
# for extracting the most useful information about it.  For example,
# allowing Cpanel::WebServer to query the package so that it can
# set up a handler.

package Cpanel::ProgLang::Object;

=head1 NAME

Cpanel::ProgLang

Note: All Cpanel::ProgLang namespaces and some attribute inconsistencies will change in ZC-1202. If you need to use Cpanel::ProgLang please note the specifics in ZC-1202 so the needful can be had.

=head1 SYNOPSIS

    use Cpanel::ProgLang ();

    my $lang = Cpanel::ProgLang->new( type => 'php' );
    my $lang_obj = $lang->get_package( package => 'ea-php54' );

    my $lang_name = $lang_obj->type();

    my @sapis = $lang_obj->get_sapi_list();

    my $sapi_info = $lang_obj->get_sapi_info('cgi');

    my $version_number = $lang_obj->get_version();

    my $path = $lang_obj->get_install_prefix()

    my $package = $lang_obj->get_package_name();

    my @file_ext = $lang_obj->get_file_extensions();

=head1 DESCRIPTION

Cpanel::ProgLang::Object lives at the intersection between a Cpanel::ProgLang
and a package name; it contains information about the SAPIs that a
given language package supports, pathnames, version numbers, etc.  It
should be considered an opaque interface, and there should be no
dependency on the internal structure; all access should be done via
the accessor functions.  It is strictly read-only; any modifications
to what the object can return is dependent on what RPMs are installed
on the server.

Instances of this module are referred to as I<lang_obj> throughout the
documentation within the Cpanel::ProgLang and Cpanel::WebServer trees.
See L<Cpanel::ProgLang::Overview> for more details.

=cut

use strict;
use warnings;
use Cpanel::Exception ();

our $ObjectBaseType = q{Cpanel::ProgLang::Supported};

=head2 Cpanel::ProgLang::Object-E<gt>new()

=head3 Arguments

=over 4

=item $data

Data structure to be used, formatted similarly to:

    $data = {
        'file_ext' => [
            '.php',
            '.php5',
            '.phtml'
        ],
        'version'        => '5.4.45',
        'install_prefix' => '/opt/cpanel/ea-php54/root',
        'package_name'   => 'ea-php54',
        'sapi' => {
            'apache2' => {
                'path'      => '/opt/cpanel/ea-php54/root/usr/lib64/apache2/modules/libphp5.so',
                'mime_type' => 'application/x-httpd-php'
            },
            'cli' => {
                'path' => '/opt/cpanel/ea-php54/root/usr/bin/php'
            },
            'cgi' => {
                'path' => '/opt/cpanel/ea-php54/root/usr/bin/php-cgi'
            },
            'fcgi' => {
                'path' => '/opt/cpanel/ea-php54/root/usr/sbin/php-fpm'
            }
        },
        'type' => 'php'
    }

Within each I<sapi> key, at least the I<path> key should be present.
If a SAPI has other information that is relevant to callers, then the
data should be included as separate keys.

=back

=head3 Returns

A blessed reference to a Cpanel::ProgLang::Object.

=head3 Notes

There is currently no validation of input data.

=cut

sub new {
    my $class = shift;
    my $data  = shift;

    # TODO: Obscure the contents of the hash to discourage
    #       developers from reaching into it instead of using
    #       the interface.

    die Cpanel::Exception::create( 'InvalidParameter', q{You must specify a valid “[_1]” argument.},        ['data'] )              unless defined $data;
    die Cpanel::Exception::create( 'InvalidParameter', q{The “[_1]” data parameter must be a “[_2]” type.}, [ 'data', 'hashref' ] ) unless ref $data eq 'HASH';

    my @tests = (
        { key => 'type',           type => 'scalar',        refre => qr/^$/ },                      # e.g. 'php'
        { key => 'install_prefix', type => 'scalar',        refre => qr/^$/ },                      # e.g. '/opt/cpanel/package/root'
        { key => 'sapi',           type => 'hashref',       refre => qr/^HASH$/ },
        { key => 'version',        type => 'scalar',        refre => qr/^$/ },                      # e.g. 5.6.30
        { key => 'package_name',   type => 'scalar',        refre => qr/^$/ },                      # e.g. ea-php99
        { key => 'file_ext',       type => 'arrayref',      refre => qr/^ARRAY$/ },                 # e.g. [ '.php', '.php5' ]
        { key => 'lang',           type => $ObjectBaseType, refre => qr/\A\Q$ObjectBaseType\E/ },
    );

    for my $test (@tests) {
        my $key = $test->{key};
        die Cpanel::Exception::create( 'InvalidParameter', q{You must specify the “[_1]” data parameter.} ) unless defined $data->{$key};
        my $value = $data->{$key};
        die Cpanel::Exception::create( 'InvalidParameter', q{The “[_1]” data parameter must be a “[_2]” type.}, [ $key, $test->{type} ] ) unless ref($value) =~ $test->{refre};
    }

    return bless( $data, $class );
}

=head2 $lang_obj-E<gt>type()

Retrieves the language type.

=head3 Returns

The name of the language in question, e.g. 'php'.

=cut

sub type {
    my $self = shift;
    return lc $self->{type};
}

=pod

=head2 $lang_obj-E<gt>get_lang()

Retrieves the Cpanel::ProgLang::Supported::* instance that created the object.

=head3 Returns

The instance of the object.

=cut

sub get_lang {
    my $self = shift;
    return $self->{lang};
}

=pod

=head2 $lang_obj-E<gt>get_sapi_list()

Retrieves the list of supported SAPIs.

=head3 Returns

A list of SAPIs.

=cut

sub get_sapi_list {
    my $self = shift;
    my @keys = sort keys %{ $self->{sapi} };
    return @keys;
}

=head2 $lang_obj-E<gt>get_sapi_info()

=head3 Arguments

=over 4

=item $sapi

The name of the SAPI for which we want information.

=back

=head3 Returns

A hash ref of relevant data to the supplied SAPI.  It will contain at
least the I<path> key, which will contain a path to a binary, but may
contain other keys.  For example:

    $retval = {
        'path' => '/opt/cpanel/ea-php54/root/usr/bin/php',
    },

Or:

    $retval = {
        'path'      => '/usr/lib64/httpd/modules/libphp5.so',
        'mime_type' => 'application/x-httpd-php',
    }

=head3 Notes

The function will return a copy of the internal data, so any
modification by callers will not affect the internal state of the
object.

An unrecognized SAPI type will return undef.  Dying with an exception
might be more appropriate.

=cut

sub get_sapi_info {
    my $self = shift;
    my $sapi = shift;
    my $ref;

    die Cpanel::Exception::create( 'InvalidParameter', q{You must specify a valid “[_1]” argument.}, ['sapi'] ) unless defined $sapi;

    if ( $self->{sapi}->{$sapi} ) {
        my %data = %{ $self->{sapi}->{$sapi} };
        $ref = \%data;
    }
    else {
        die Cpanel::Exception::create( 'FeatureNotEnabled', q{The “[_1]” [output,acronym,SAPI,Server Application Programming Interface] is not supported by the “[_2]” package.}, [ $sapi, $self->get_package_name() ] );
    }

    return $ref;
}

=head2 $lang_obj-E<gt>get_version()

Retrieve the version number of the language package.

=head3 Returns

The version number of the language package, e.g. '5.4.23'.

=cut

sub get_version {
    my $self = shift;
    return $self->{version};
}

=head2 $lang_obj-E<gt>get_install_prefix()

Retrieve the install path of the language package.

=head3 Returns

The absolute path to the root of the language package's SCL
installation.

=head3 Notes

Almost all of the EasyApache4 code assumes that the various language
packages will be installed using the SCL (Software Collections)
mechanism.  This function will return the path to the root of the SCL,
such as '/opt/cpanel/ea-php54/root'.

=cut

sub get_install_prefix {
    my $self = shift;
    return $self->{install_prefix};
}

=head2 $lang_obj-E<gt>get_package_name()

Retrieve the package name of our language package.

=head3 Returns

The name of the package which this object uses, e.g. 'ea-php54'.

=cut

sub get_package_name {
    my $self = shift;
    return $self->{package_name};
}

=head2 $lang_obj-E<gt>get_file_extensions()

Retrieve the relevant file extensions for this language and/or
package.

=head3 Returns

A list of file extensions which this language should handle.  For
example:

    @retval = ( '.php5', '.php' ,'.phtml' );

=cut

sub get_file_extensions {
    my $self = shift;
    return @{ $self->{file_ext} };
}

=head1 CONFIGURATION AND ENVIRONMENT

The module has no dependencies on environment variables or
configuration files.  The data contained within may reflect one or
both, but that is not the concern of this module.

=head1 DEPENDENCIES

None.

=head1 BUGS AND LIMITATIONS

Instances of this module should not be created manually; each module
within Cpanel::ProgLang::Supported should create this as a result of the
I<get_package()> method.

=head1 TODO

The constructor does no validation of input data, so a caller could
pass in a bad structure which would cause all the methods to return
undef.

=head1 SEE ALSO

L<Cpanel::ProgLang::Overview>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
