package Cpanel::WebServer::Supported::apache::Handler::dso;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/dso.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::dso

=head1 DESCRIPTION

An Apache handler module which supports the mod_php-style loadable
language module.  The name would be more appropriate as 'embed' or
'apache2', but due to cPanel historical reasons, we will continue to
refer to it as 'dso'.

A clearer documentation suite for the base class and an implemented
handler can be found in the I<SEE ALSO> section below.

=head1 SEE ALSO

L<Cpanel::WebServer::Supported::apache::Handler::base>,
L<Cpanel::WebServer::Supported::apache::Handler::cgi>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

use parent 'Cpanel::WebServer::Supported::apache::Handler::base';

use strict;
use warnings;
use Cpanel::Exception      ();
use Cpanel::ProgLang::Conf ();

sub new {
    my ( $class, %args ) = @_;

    # All the arg-validation is done in the init, so we at least need
    # to do that.
    my $self = bless( {}, $class );
    $self->init( \%args );

    # Make sure there's only one dso object assigned to the server for this language.
    # If more than one is assigned, then we must bailout
    my $lang          = $self->get_lang();
    my $conf          = Cpanel::ProgLang::Conf->new( type => $lang->type() );
    my $conf_ref      = $conf->get_conf();
    my ($dso_package) = grep { $conf_ref->{$_} eq 'dso' ? $_ : undef } keys %$conf_ref;
    die Cpanel::Exception::create( 'InvalidParameter', 'You can only configure one version of “[_1]” with the [output,acronym,DSO,Dynamic Shared Object] [asis,Apache] handler.', [ uc $lang->type() ] ) if ( $dso_package && $dso_package ne $self->get_package() );

    # There wasn't already an object for our language, so go ahead and
    # finish up our construction process.
    $self->module_check_and( [qw( mod_so mod_mpm_prefork )] );
    $self->sapi_check('apache2');

    return $self;
}

sub type {
    return 'dso';
}

sub get_mime_type {
    my ($self) = @_;

    # PHP has a hard-coded value; other languages probably do as well.
    # We'll get the mime type out of the lang_obj, rather than having
    # any language-specific stuff here.
    return $self->get_lang_obj()->get_sapi_info('apache2')->{mime_type};
}

sub get_config_string {
    my ($self) = @_;

    my $package = $self->get_package();
    my $path    = $self->get_lang_obj()->get_sapi_info('apache2')->{path};
    my $module  = $self->get_lang_obj()->get_sapi_info('apache2')->{module};
    my $str     = <<"EOF";
# DSO configuration for $package
LoadModule $module $path
EOF
    return $str;
}

1;
