package Cpanel::WebServer::Supported::apache::Handler::suphp;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/suphp.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::suphp

=head1 DESCRIPTION

An Apache handler module which supports the suPHP module.  suPHP
performs security checks on scripts and directories, and sets its
execution user/group IDs to that of the script owner.

A clearer documentation suite for the base class and an implemented
handler can be found in the I<SEE ALSO> section below.

=head1 TODO

The I<set_lang_handler()> and I<unset_lang_handler()> methods should
update the /etc/suphp.conf file, to add/remove whatever mime types
would be necessary to support our packages.

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

sub new {
    my ( $class, %args ) = @_;

    my $self = bless( {}, $class );
    $self->init( \%args );
    $self->module_check_and( ['mod_suphp'] );
    $self->sapi_check('cgi');
    return $self;
}

sub type {
    return 'suphp';
}

sub get_config_string {
    my ($self) = @_;

    my $package = $self->get_package();
    my $type    = $self->get_mime_type();
    my $str     = <<"EOF";
# suPHP configuration for $package
<IfModule suphp_module>
  suPHP_Engine on
  <Directory />
    suPHP_AddHandler $type
  </Directory>
</IfModule>
EOF
    return $str;
}

sub get_mime_type {
    my ($self) = @_;

    # NOTE: We're overriding the mime header because the suphp EA4 package
    #       deploys a hard-coded /etc/suphp.conf.  This conf hard-codes
    #       the names of the PHP package mime headers for php 5.4, 5.5,
    #       and 5.6.  THIS IS BAD, especially if we add a new PHP version.
    #
    #       So, if you want to use base::get_mime_type (instead of overriding
    #       here), then you'll need to add a set_lang_handler() which updates
    #       /etc/suphp.conf with the correct [handlers] section.

    return 'application/x-httpd-' . $self->{'lang_obj'}->get_package_name();
}

1;
