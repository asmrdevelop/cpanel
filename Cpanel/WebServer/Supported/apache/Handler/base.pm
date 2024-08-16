package Cpanel::WebServer::Supported::apache::Handler::base;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::base

=head1 DESCRIPTION

The base class for the Apache handler set.  There are some methods
here which explode on contact, particularly the I<new()> method, so
this class should not be directly instantiable.

When subclassing this package, care should be taken in what directives
you emit.  Any non-core directive should be enclosed in IfModule tags,
to ensure that if the required module(s) are somehow removed or
deactivated, the server will still at least run.  The handlers will
likely become broken, but some of the basic functionality of the
webserver will still be available.

=cut

use strict;
use warnings;
use Cpanel::ProgLang  ();    # PPI USE OK - used via lang_obj attribute in multiple functions
use Cpanel::Locale    ();
use Cpanel::Exception ();

=head1 METHODS

=head2 Cpanel::WebServer::Supported::apache::Handler::base->new()

This method will only throw exceptions, so this base class is not
instantiable.  Subclasses must implement a I<new()> method.

=cut

sub new {
    die Cpanel::Exception::create( 'MissingMethod', [ method => 'new', pkg => ref $_[0] ] );
}

=head2 $handler-E<gt>init()

Performs general argument validation and object creation.

=head3 Required argument keys

=over 4

=item lang_obj

A Cpanel::ProgLang::Object referencing the language package we wish to
use.

=item webserver

A Cpanel::WebServer::Supported::apache object, which we will reference for module requirements in I<module_check_and()> and I<module_check_or()>.

=back

=head3 Returns

Nothing.

=head3 Dies

If argument validation fails, a Cpanel::Exception will result.

=head3 Notes

This method should be called in the constructor for each subclass.

=cut

sub init {
    my ( $self, $args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] )   unless defined $args->{package};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )      unless defined $args->{lang};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'webserver' ] ) unless defined $args->{webserver};
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument must be an object of type “[_2]”.', [ 'webserver', 'Cpanel::WebServer::Supported::apache' ] ) unless eval { $args->{webserver}->isa('Cpanel::WebServer::Supported::apache') };

    $self->{package}   = $args->{package};
    $self->{lang}      = $args->{lang};
    $self->{webserver} = $args->{webserver};

    # The check for an 'inherit' package name is performed because it's the
    # way cpanel decides to allow a user to not have to assign a package
    # to a virtual host.  For example, they can just use whatever the
    # system default it.
    #
    # Since 'inherit' will never be an actually valid package name, we
    # can't generate a Cpanel::ProgLang::Object.

    if ( $self->{package} ne 'inherit' ) {
        $self->{lang_obj} = $args->{lang_obj} || $self->{lang}->get_package( package => $self->{package} );
    }

    return 1;
}

=head2 $handler-E<gt>module_check_and()

Verify that a set of required Apache modules is installed.

=head3 Arguments

=over 4

=item $modules

An array ref of a set of module names that a handler requires in order
to function.

=back

=head3 Returns

Nothing.

=head3 Dies

If all of the required modules are not available, this method will die
with a Cpanel::Exception containing a list of the missing modules.

=head3 Notes

This module is meant to validate whether a set of Apache modules is
available.  This method or I<module_check_or()> should be called from
the constructor of subclasses, to make sure the Apache environment is
valid for the handler in question.

=cut

sub module_check_and {
    my ( $self, $mods ) = @_;

    my $ws_mods      = $self->get_webserver()->modules();
    my @missing_mods = ();
    for my $mod (@$mods) {
        push @missing_mods, $mod unless defined $ws_mods->{$mod};
    }
    die Cpanel::Exception::create( 'FeatureNotEnabled', 'The following [numerate,_1,module is,modules are] required for handler “[_2]”: [list_and,_3]', [ scalar @missing_mods, $self->type(), \@missing_mods ] ) if scalar @missing_mods;
    return 1;
}

=head2 $handler-E<gt>module_check_or()

Verify that one of a set of Apache modules is installed.

=head3 Arguments

=over 4

=item $modules

An array ref of a set of module names that a handler requires at least
one of in order to function.

=back

=head3 Returns

Nothing.

=head3 Dies

If none of the required modules are not available, this method will
die with a Cpanel::Exception containing a list of the modules, any one
of which would satisfy the condition.

=head3 Notes

This module is meant to validate whether one of a set of Apache
modules is available.  This method or I<module_check_and()> should be
called from the constructor of subclasses, to make sure the Apache
environment is valid for the handler in question.

=cut

sub module_check_or {
    my ( $self, $mods ) = @_;

    my $ws_mods   = $self->get_webserver()->modules();
    my @good_mods = ();
    for my $mod (@$mods) {
        push @good_mods, $mod if defined $ws_mods->{$mod};
    }
    die Cpanel::Exception::create( 'FeatureNotEnabled', 'The following [numerate,_1,module is,modules are] required for handler “[_2]”: [list_or,_3]', [ 0, $self->type(), $mods ] ) unless scalar @good_mods;
    return 1;
}

=head2 $handler-E<gt>sapi_check()

=head3 Arguments

=over 4

=item $sapi

The name of a SAPI which is required for the handler to function.

=back

=head3 Returns

Nothing.

=head3 Dies

If the required SAPI is not available, this method will die with a
Cpanel::Exception containing the required SAPI.

=head3 Notes

This module is meant to validate whether one of a set of language
SAPIs is available.  This method should be called from the constructor
of subclasses, to make sure the language environment is valid for the
handler in question.

=cut

sub sapi_check {
    my ( $self, $sapi ) = @_;

    my $sapi_info = $self->get_lang_obj()->get_sapi_info($sapi);
    die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” handler requires the unavailable “[_2]” [output,acronym,SAPI,Server Application Programming Interface].', [ $self->type(), $sapi ] ) unless defined $sapi_info;
    return 1;
}

=head2 $handler-E<gt>type()

This method will only throw exceptions.  Subclasses must implement a
I<type()> method, which should return a scalar of the name of the
type, e.g. 'suphp' or 'cgi'.

=cut

sub type {
    die Cpanel::Exception::create( 'MissingMethod', [ method => 'type', pkg => ref $_[0] ] );
}

=head2 $handler-E<gt>get_package()

Retrieve the name of the language package that this handler object is
using.

=head3 Returns

The name of the language package this handler object is using.

=cut

sub get_package {
    my ($self) = @_;
    return $self->{package};
}

=pod

=head2 $handler-E<gt>get_lang_obj()

Retrieve the I<lang_obj> which this handler is using.

=head3 Returns

A Cpanel::ProgLang::Object.

=cut

sub get_lang_obj {
    my ($self) = @_;

    return $self->{lang_obj};
}

=pod

=head2 $handler-E<gt>get_webserver()

Retrieve the I<webserver> which this handler is using.

=head3 Returns

A Cpanel::WebServer object

=cut

sub get_webserver {
    my ($self) = @_;
    return $self->{webserver};
}

=pod

=head2 $handler-E<gt>get_lang()

Retrieve the I<lang> which this handler is using.

=head3 Returns

A Cpanel::ProgLang object

=cut

sub get_lang {
    my ($self) = @_;
    return $self->{lang};
}

=head2 $handler-E<gt>get_mime_type()

When Apache is loading a file, it associates the file with a
behavior (e.g. handler) and content (e.g. media-type, language,
character set, etc).  This method specifically retrieves the
media type (e.g. mime-type) for a handler so that files can
be processed correctly.

For example, .gif images have a mime-type of image/gif.

This tells the web server how to process the media type.

=head3 Returns

The name of the mime-type which is associated with a package.

=head3 Notes

We may consider changing the type name to use the handler type in
place of the webserver type.

=cut

sub get_mime_type {
    my ($self) = @_;
    return 'application/x-httpd-' . $self->get_package();
}

=head2 $handler-E<gt>get_config_string()

This method returns a configuration fragment (string) that
can be used by Apache.  The configuration fragment tells Apache
about an available (but not necessarily used) content handler.

For example, if you want to make ea-php54 and ea-php55 available
to users, then this method will be called twice for each PHP package.
The result will be 2 PHP configuration sections that are added to
/etc/apache2/conf.d/php.conf.

This method will only throw exceptions.  Subclasses must implement a
I<get_config_string()> method, which should return a scalar with the
configuration string that would correctly exist in a server-level
configuration file.

It should include the language name and package, and should wrap any
directives in IfModule tags, if the directives are not in the Apache
core.

For example, a CGI handler might generate a config string like:

  # CGI configuration for $langtype $package
  <IfModule actions_module>
    Action $mime_type /cgi-bin/${package}-loader
  </IfModule>

=cut

sub get_config_string {
    die Cpanel::Exception::create( 'MissingMethod', [ method => 'get_config_string', pkg => ref $_[0] ] );
}

=head2 $handler-E<gt>get_default_string()

This method returns a configuration fragment (string) that
can be used by Apache.  The configuration fragment tells Apache
to use a particular content-handler and language by default when
it finds a matching extension.

For example, if you have ea-php54 and ea-php55 configured as
available content handlers, this method is called once.  The
result is a configuration fragment that's applied to
/etc/apache2/conf.d/php.conf which specifies either ea-php54
or ea-php55 as the "default" handler unless the user specified
a different one in their .htaccess file.

=head3 Returns

A scalar with a default type configuration string.

=head3 Notes

I<This> implementation generates a simple AddHandler with the mime-type
and extensions from the lang_obj, and is useful for handlers like CGI
and suPHP.  Subclasses should override this as needed.

=cut

sub get_default_string {
    my ($self) = @_;

    my $type = $self->get_mime_type();
    my @exts = sort $self->get_lang_obj()->get_file_extensions();
    my $str  = <<"EOF";
<IfModule mime_module>
  AddHandler $type @exts
</IfModule>
EOF
    chomp $str;
    return $str;
}

=head2 $handler-E<gt>get_htaccess_string()

Retrieves a string which can be added to an .htaccess file, to enable
a given content-handler.  This allows the user to override the
system default package a different one.

For example, if the system administrator defined ea-php99 as the
default for PHP applications.  However, if the user wants to
instead use ea-php55, the user can override the default
by placing the result of this method within their .htaccess file.

=head3 Returns

A string appropriate for adding to an .htaccess file.

=head3 Notes

This implementation uses the default string, and adds a package name
and language type.  Subclasses should override as necessary.

=cut

sub get_htaccess_string {
    my ($self) = @_;

    my $default = $self->get_default_string();

    my $locale  = Cpanel::Locale->get_handle();
    my $comment = Cpanel::Locale->get_handle()->maketext( q{Set the “[_1]”[comment,package name] package as the default “[_2]”[comment,language name] programming language.}, $self->get_package(), uc $self->get_lang()->type() );

    return "# $comment\n$default";
}

=pod

=head1 HANDLER HOOK POINTS

There are several methods which we make available as possible "hook"
points.  These hooks allow each handler to perform additional (optional)
functionality.  For more information about each hook, please refer to
the corresponding section, or look at the
Cpanel::WebServer::Supported::apache source code.  Some handlers may need
additional setup, either server-wide, or per-virtual host.  These hooks
allow handlers to perform additional work when needed.

The return values of these methods are ignored, and these methods are
expected to live.

=head2 $handler-E<gt>set_lang_handler()

This can be potentially called twice.

The first time it may be called is for the new handler.  It's called
I<AFTER> the Apache configuration is written, but before the service
is restarted.

It can be called a second time if the system failed to apply the new
handler and is trying to restore the previous setting.  In this case,
this method is called on the old handler I<AFTER> it has updated
the Apache configuration file.

Takes no arguments.

=head2 $handler-E<gt>unset_lang_handler()

This can be potentially called twice.

The first time it may be called is for the old handler.  It's called
I<BEFORE> the Apache configuration is written.

It can be called a second time if the system failed to apply the new
handler and is trying to restore the previous setting.  In this case,
this method is called on the new handler I<BEFORE> it has updated
the Apache configuration file.

Takes no arguments.

=head2 $handler-E<gt>set_vhost_handler()

This can be potentially called twice.

The first time it may be called is for the new handler.  It's called
I<AFTER> the virtual host's .htaccess file has been updated.

It can be called a second time if the system failed to apply the new
handler and is trying to restore the previous setting.  In this case,
this method is called on the old handler I<AFTER> the virtual host's
.htaccess file has been updated.

Takes no arguments.

=head2 $handler-E<gt>unset_vhost_handler()

This can be potentially called twice.

The first time it may be called is for the old handler.  It's called
I<BEFORE> the virtual host's .htaccess file has been updated.

It can be called a second time if the system failed to apply the new
handler and is trying to restore the previous setting.  In this case,
this method is called on the new handler I<BEFORE> the virtual host's
.htaccess file has been updated.

Takes no arguments.

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which are
required or created by the handler base.

=head1 DEPENDENCIES

Cpanel::Exception.

=head1 BUGS AND LIMITATIONS

Unknown.

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>,
L<Cpanel::WebServer::Supported::apache>,
L<Cpanel::WebServer::Supported::apache::Handler>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;
