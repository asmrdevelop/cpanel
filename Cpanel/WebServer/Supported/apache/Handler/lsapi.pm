package Cpanel::WebServer::Supported::apache::Handler::lsapi;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/lsapi.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::lsapi

=head1 DESCRIPTION

An Apache handler module which supports the mod_lsapi module.  mod_lsapi
performs security checks on scripts and directories, and sets its
execution user/group IDs to that of the script owner.

A clearer documentation suite for the base class and an implemented
handler can be found in the I<SEE ALSO> section below.

=head1 SEE ALSO

L<Cpanel::WebServer::Supported::apache::Handler::base>,
L<Cpanel::WebServer::Supported::apache::Handler::cgi>

=head1 LICENSE AND COPYRIGHT

Copyright 2017, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

use parent 'Cpanel::WebServer::Supported::apache::Handler::base';
use strict;
use warnings;

sub new {
    my ( $class, %args ) = @_;

    my $self = bless( {}, $class );
    $self->init( \%args );
    $self->module_check_and( ['mod_lsapi'] );
    $self->sapi_check('cgi');
    return $self;
}

sub type {
    return 'lsapi';
}

sub get_config_string {
    my ($self) = @_;

    my $package = $self->get_package();
    my $type    = $self->get_mime_type();
    my @exts    = sort $self->get_lang_obj()->get_file_extensions();
    my $str     = <<"EOF";
# lsapi configuration for $package
<IfModule lsapi_module>
    lsapi_engine On
    AddHandler $type @exts
</IfModule>
EOF
    return $str;
}

sub get_mime_type {
    my ($self) = @_;

    # NOTE: We're overriding the mime header because the lsapi EA4 package
    #       deploys a hard-coded /etc/container/php.handler.
    #       This conf hard-codes the names of the PHP package mime headers
    #       THIS IS BAD, especially if we add a new PHP version.
    #
    #       So, if you want to use base::get_mime_type (instead of overriding
    #       here), then we'd need to add a set_lang_handler() which updates
    #       /etc/container/php.handler with the correct [handlers] section.
    return 'application/x-httpd-' . $self->{'lang_obj'}->get_package_name() . "___lsphp";    # Look for '3 underscores' at https://cpanel.wiki/display/EA/Adding+a+PHP+Handler for more details
}

1;
