package Cpanel::WebServer::Supported::apache::Handler;

# cpanel - Cpanel/WebServer/Supported/apache/Handler.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler

=head1 SYNOPSIS

    use Cpanel::WebServer::Supported::apache::Handler ();

    my $handler = Cpanel::WebServer::Supported::apache::Handler->new( 'type' => 'suphp' );

=head1 DESCRIPTION

Apache has content handlers, which do whatever processing a given type
of content requires.  Each language will have backend handler types
which do the processing for that language, and return the generated
pages.

This Handler module is simply an input validator, similar to the
Cpanel::ProgLang module - all the work is done in the submodules, and this
entry point is merely a validator and object creator.  The I<new()>
method is the only one in this module.

=cut

use strict;
use warnings;
use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Try::Tiny;

=head1 GLOBAL VARIABLES

=head2 @REQUIRED_METHODS

Each handler implementation must implement the following methods:

=over 2

=item new()

=item get_config_string()

=item get_default_string()

=item get_htaccess_string()

=back

=cut

our @REQUIRED_METHODS = qw( new get_config_string get_default_string get_htaccess_string );

=head1 METHODS

=head2 Cpanel::WebServer::Supported::apache::Handler-E<gt>new()

Get an instance to the Apache Handler object.

=head3 INPUT

=over 2

=item webserver

Reference to a Cpanel::WebServer object.

=back

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'webserver' ] ) unless defined $args{webserver};

    # TODO validate webserver arg

    return bless( { _webserver => $args{webserver} }, $class );
}

=pod

=head2 $apache-E<gt>get_handler( type => $type, lang_obj => $lang_obj )

Retrieve an instance of a supported Apache handler.

=head3 INPUT

=over 2

=item type

The string representation (SCALAR) of the handler we want to create (e.g. "suphp").

=item lang_obj

An instance (BLESSED REF) to a Cpanel::ProgLang::Object object.

=back

=head3 OUTPUT

An instance (sub-class) of Cpanel::WebServer::Supported::apache::Handler::base.
This instance has the necessary methods and calls needed to update Apache
configuration files.

=head3 EXCEPTIONS

Trying to create an instance of a handler which isn't supported.

=cut

sub get_handler {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'type' ] )    unless defined $args{type};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )    unless defined $args{lang};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{package};
    die Cpanel::Exception::create( 'InvalidParameter', q{You cannot create instances of the “[_1]” [asis,Apache] handler.}, ['base'] ) if $args{type} eq 'base';

    # TODO: Look in # /var/cpanel/perl/Cpanel/WebServer/Supported/apache/Handler for
    # customer-defined override or additional handler implementations
    my $pkg = sprintf( '%s::%s', __PACKAGE__, $args{type} );

    try {
        Cpanel::LoadModule::load_perl_module($pkg);
    }
    catch {
        # re-throw as a more meaningful error
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” [asis,Apache] handler is not installed on the system.', [ $args{type} ] );
    };

    # Ensure handler implements all required methods
    for my $method (@REQUIRED_METHODS) {
        die Cpanel::Exception::create( 'MissingMethod', [ method => $method, pkg => $pkg ] ) unless $pkg->can($method);
    }

    # ->new is expected to throw exceptions so we suppress stack
    # traces since they are slow
    my $suppress = Cpanel::Exception::get_stack_trace_suppressor();

    # Create a new instance of the requested handler.  This passes along an optional lang_obj argument
    # if the caller already has access to it.  This reduces the expense of creating a another one.
    return $pkg->new( lang => $args{lang}, package => $args{package}, webserver => $self->{_webserver}, lang_obj => $args{lang_obj} );
}

=pod

=head2 I<$apache-E<gt>get_handler_types()>

Retrieves a list of known Apache handlers that can be configured
if they were supported.  Your must use I<get_handler()> to determine
if the handler type is supported.

=head3 OUTPUT

An ARRAY REF of SCALAR values (strings) representing handlers
Apache knows how to configure if it were supported.

=cut

sub get_handler_types {
    my $self = shift;

    # TODO: Look in /var/cpanel/perl/Cpanel/WebServer/Supported/apache/Handler for
    # custoer-defined override or additional handler implementations
    my $mod_path = __PACKAGE__;
    $mod_path =~ s/::/\//g;
    my $basedir = sprintf( '/usr/local/cpanel/%s', $mod_path );

    my @handlers = map {
        my $tmp = s/\.pm$//r;
        $tmp =~ s{^\Q$basedir/\E}{}r;
    } grep( !/base\.pm$/i, glob("$basedir/*.pm") );    # Users cannot instantiate 'base' handler

    return \@handlers;
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which this
module requires or creates.

=head1 DEPENDENCIES

Cpanel::Exception, Cpanel::LoadModule, and Try::Tiny.

=head1 TODO

Add a local search path for third-party modules, perhaps in
/var/cpanel/perl.

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>,
L<Cpanel::WebServer::Supported::apache>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;
