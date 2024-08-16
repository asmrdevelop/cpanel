package Cpanel::WebServer::Supported::apache;

# cpanel - Cpanel/WebServer/Supported/apache.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache

=head1 SYNOPSIS

    use Cpanel::ProgLang      ();
    use Cpanel::WebServer ();

    my $ws = Cpanel::WebServer->new();
    my $apache = $ws->get_server( 'type' => 'apache' );


=head1 DESCRIPTION

Cpanel::WebServer::Supported::apache module adds program-specific
support for the Apache webserver.  It implements all of the methods
required by the Cpanel::WebServer object.  Typically, a caller would
not interact with this object directly; the main Cpanel::WebServer
object will make the necessary calls into this one.

Any of the modules within the Cpanel::WebServer tree can throw
exceptions, and will do so instead of any error-return values.  This
allows us to keep the code relatively clean, and focus on data flow,
rather than error handling.

Please see Cpanel::WebServer::Overview for documentation on the
nomenclature we use throughout this module tree, concerning I<lang>,
I<lang_obj>, and I<package>.

=cut

use strict;
use warnings;
use Cpanel::CachedCommand                          ();
use Cpanel::WebServer::Userdata                    ();
use Cpanel::Config::LoadCpUserFile                 ();
use Cpanel::Config::LoadUserDomains                ();
use Cpanel::ConfigFiles::Apache                    ();
use Cpanel::Exception                              ();
use Cpanel::LoadModule                             ();
use Cpanel::ProgLang                               ();    # PPI USE OK - used via lang_obj attribute in multiple functions
use Cpanel::ProgLang::Conf                         ();
use Cpanel::AcctUtils::DomainOwner::Tiny           ();
use Cpanel::WebServer::Supported::apache::Handler  ();
use Cpanel::WebServer::Supported::apache::Htaccess ();

use Try::Tiny;

our $CONFIG_DIR = '/etc/cpanel/ea4';

=head2 Cpanel::WebServer::Supported::apache-E<gt>new()

Create a new Apache webserver object.

=head3 Optional arguments

=over 4

=item config

SCALAR -- Path to a Cpanel::ConfigFiles::Apache compatible config file on the local filesystem

=back

=head3 Returns

A blessed reference to a Cpanel::WebServer::Supported::apache object.

=cut

sub new {
    my ( $class, %args ) = @_;
    my %data;

    $data{_type}   = 'apache';
    $data{_config} = Cpanel::ConfigFiles::Apache->new( $args{config} );

    return bless( \%data, $class );
}

=head2 $apache-E<gt>type()

Retrieve the type of webserver object.

=head3 Returns

The name of our subclass, 'apache'.

=head3 Notes

This will be more useful later on, when we have multiple webservers in
use, and the caller needs to know what type it's dealing with.

=cut

sub type {
    my $self = shift;
    return lc $self->{_type};
}

=head2 $apache-E<gt>modules()

Retrieve a list of modules supported by Apache

=head3 Returns

An array ref of the supported modules.

=cut

sub modules {
    my $self = shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles::Apache::modules');
    $self->{_modules} ||= Cpanel::ConfigFiles::Apache::modules::get_supported_modules();
    return $self->{_modules};
}

=head2 $apache-E<gt>is_directive_supported()

Returns a boolean value if the directive can be used within an Apache configuration file.

=head3 Returns

Truthy value if supported, otherwise false.

=cut

sub is_directive_supported {
    my ( $self, $directive ) = @_;
    my $bin    = $self->config()->bin_httpd();
    my $buffer = Cpanel::CachedCommand::cachedmcommand_cleanenv2( 3600, { 'command' => [ $bin, '-L' ], 'errors' => 0, 'return_ref' => 1 } );
    my $ref    = ref $buffer eq 'SCALAR' ? $buffer : \$buffer;                                                                                 # mimick cachedmcommand_r_cleanenv() check
    return ( $$ref =~ /^\Q$directive\E\s+/mi ? 1 : 0 );
}

=head2 $userdata-E<gt>config()

Retrieve the Cpanel::ConfigFiles::Apache object.

=head3 Returns

An object of type Cpanel::ConfigFiles::Apache.

=head3 Notes

This is likely of limited use for most outside callers.

=cut

sub config {
    my $self = shift;
    return $self->{_config};
}

=pod

=head2 $apache-E<gt>get_handler_types()

Retrieves a list of handler types (e.g. cgi, fastcgi, etc) the system
knows how to configure if your system supported it.

NOTE: This doesn't mean the handlers are supported on your system.  You
must use the Handler interface directly to determine if the handler
is supported.

=head3 Returns

ARRAY ref -- list of strings that represent a handler type that can be passed
to I<make_handler()>

=cut

sub get_handler_types {
    my $self = shift;
    return Cpanel::WebServer::Supported::apache::Handler->new( webserver => $self )->get_handler_types();
}

=pod

=head2 $apache-E<gt>make_handler( type => $type )

Retrieve the currently-configured handler for a package.

It handles the details of creating a new content handler for Apache.
Content handlers are used by Apache to ensure that applications are
executed by the correct service/binaries.  For more information
about Apache content handlers, please read:

  https://httpd.apache.org/docs/current/handler.html

=head3 Require argument keys

=over 4

=item type

SCALAR -- dso, suphp, none, cgi, etc

=item lang_obj

OBJECT -- type Cpanel::ProgLang::Object

=back

=head3 Returns

An instance of the handler type I<Cpanel::WebServer::Supported::apache::Handler::*>

=cut

sub make_handler {
    my ( $self, %args ) = @_;

    for (qw( type lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $hndl_type = $args{type};
    my $lang      = $args{lang};
    my $package   = $args{package};
    my $lang_type = $lang->type();

    my $handler = $self->{_handler}->{$lang_type}->{$package}->{$hndl_type};

    unless ($handler) {
        my $hndl = Cpanel::WebServer::Supported::apache::Handler->new( webserver => $self );
        $handler = $hndl->get_handler(%args);
        $self->{_handler}->{$lang_type}->{$package}->{$hndl_type} = $handler;
    }

    return $handler;
}

=pod

=head2 $apache-E<gt>make_htaccess( user => $user )

Handles the step needed to create an instance of a user's Htaccess
object.  This object is needed to manipulate the content-handler used
by Apache to execute applications.

=cut

sub make_htaccess {
    my ( $self, %args ) = @_;

    for (qw( user )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $userdata = $args{userdata} || Cpanel::WebServer::Userdata->new( user => $args{user} );

    return Cpanel::WebServer::Supported::apache::Htaccess->new( userdata => $userdata );
}

=pod

=head2 $apache-E<gt>get_config_string()

Generates the text needed to support a programming language in Apache.
It's common to take this text and place it in the Apache conf.d directory
so it can be included on start-up (e.g. conf.d/php.conf).

=head3 Required argument keys

=over 4

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to configure.

=item conf

An object from Cpanel::ProgLang::Conf-E<gt>new(), of the language type we want
to configure.

=back

=head3 Returns

A string which can be used for a configuration file for the supplied
language.

=head3 Dies

If any of the package names or handler types are invalid, a
Cpanel::Exception will result.

=head3 Notes

Previous implementations relied on a 'dryrun' key as part of the
configuration structure; this method can be called directly, and no
configuration changes will be enacted.  To write the config string,
the output of this method should be passed into the
I<write_config_file()> method.

=cut

sub get_config_string {
    my ( $self, %args ) = @_;

    for (qw( lang conf )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $conf = $args{conf};
    my $lang = $args{lang};
    my $type = $lang->type();

    my $str = <<"EOF";
# This file was automatically generated by the Cpanel $type
# Configuration system.  If you wish to change the way $type is being
# handled by Apache on your system, use the
# /usr/local/cpanel/bin/rebuild_phpconf script or the WHM interface.
#
# Manual edits of this file will be lost when the configuration is
# rebuilt.

# These initial handlers serve as fallback in case there is any
#  time between when configuration has changed and when it takes effect.
# We use CGI style since it is simple and the default we use elsewhere.
# If the version is not set to CGI they will get a 404 until the new
#  configuration takes effect which is better than serving source
#  code until the new configuration takes effect.
<IfModule actions_module>
[% fallbacks %]
</IfModule>

EOF

    my $fallbacks = "";
    my $ref       = $conf->get_conf();
    my $default   = delete $ref->{default};
    my %handlers;

    # this is sorted so that the language definitions are easier to find in the Apache config
    for my $package ( sort keys %$ref ) {
        $fallbacks .= "  Action application/x-httpd-$package /cgi-sys/$package\n";

        my $handler = $ref->{$package};

        # put in try block in case bad package name in config
        try {
            $handlers{$package} = $self->make_handler( type => $handler, lang => $lang, package => $package );
            if ( $handler eq 'fcgi' ) {
                $str .= "# FCGI configuration for $package - nothing needed here\n\n";
            }
            elsif ( $package ne $default ) {
                $str .= $handlers{$package}->get_config_string() . "\n";
            }
        };
    }

    chomp($fallbacks);
    $str =~ s/\[\% fallbacks \%\]/$fallbacks/;

    $str .= "# Set $default as the system default for $type\n";
    $str .= $handlers{$default}->get_default_string();
    $str .= "\n";
    $str .= $handlers{$default}->get_config_string();
    $str .= "\n\n# End of autogenerated $type configuration.\n";

    return $str;
}

=head2 $userdata-E<gt>write_config_file( lang => $lang, conf_str => $conf_str )

Write the configuration file for the supplied language.

=head3 Required argument keys

=over 4

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to configure.

=item conf_str

A configuration file string, which will be written out for the Apache
server.  It's common to use the result of the I<$self->get_config_string()>
method.

=back

=head3 Returns

Truthy value on success, or dies

=head3 Dies

Any I/O errors will result in a Cpanel::Exception.

=head3 Notes

This is strictly for writing out the file contents.  No restart is
performed here, and none should be added.  The caller should do that
as necessary.

If the Cpanel::ConfigFiles::Apache object has any language-specific
key, as it does for file_conf_php_conf, it will use that.  Otherwise,
it will manufacture a path of
E<lt>dir_confE<gt>/E<lt>langtypeE<gt>.conf.

=cut

sub write_config_file {
    my ( $self, %args ) = @_;

    for (qw( lang conf_str )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $lang     = $args{lang};
    my $conf_str = $args{conf_str};

    # If we have a language-specific key within the apacheconf object,
    # go ahead and call it; otherwise, manufacture a path that's
    # <conf_dir>/<language>.conf
    my $type     = $args{lang}->type();
    my $lang_key = "file_conf_${type}_conf";

    my $path = $self->{_config}->can($lang_key) ? $self->{_config}->$lang_key() : $self->{_config}->dir_conf() . "/$type.conf";
    open my $fh, '>', $path or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, mode => '>', error => $! ] );
    print {$fh} $conf_str;
    close $fh or die Cpanel::Exception::create( 'IO::FileWriteError', [ path => $path, error => $! ] );

    return 1;
}

=head2 $apache-E<gt>restart()

Restart the Apache server, and wait for the restart to complete.

=head3 Returns

Result of Cpanel::HttpUtils::ApRestart::safeaprestart().

=head3 Notes

It might be useful to move this functionality out of the ApRestart
module, and put it directly in here; it's likely that once we
generalize out the webserver programs far enough, the typical "restart
the webserver" action will want to restart one or more of them.

=cut

sub restart {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart');
    return Cpanel::HttpUtils::ApRestart::safeaprestart();
}

=head2 $apache-E<gt>queue_restart()

Queue an Apache restart via the Cpanel::TaskQueue.  The call will
return immediately, and the restart will happen Soon(tm).

=head3 Returns

The result of Cpanel::HttpUtils::ApRestart::BgSafe::restart.

=head3 Notes

It might be useful to move this functionality out of the ApRestart
module, and put it directly in here; it's likely that once we
generalize out the webserver programs far enough, the typical "restart
the webserver" action will want to restart one or more of them.

=cut

sub queue_restart {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::ApRestart::BgSafe');
    return Cpanel::HttpUtils::ApRestart::BgSafe::restart();
}

=head2 $apache-E<gt>get_default_handler()

Retrieve a handler for the "system default" package for the supplied
language.

=head3 Required argument keys

=over 4

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to query.

=back

=head3 Returns

An object which is a subclass of
Cpanel::WebServer::Supported::apache::Handler::base.

=head3 Notes

If there is no setting, this will probably blow up.

=cut

sub get_default_handler {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] ) unless defined $args{lang};

    my $lang         = $args{lang};
    my $conf         = Cpanel::ProgLang::Conf->new( type => $lang->type() );
    my $package      = $conf->get_system_default_package();
    my $handler_type = $conf->get_package_info( package => $package );

    return $self->make_handler( lang => $lang, package => $package, type => $handler_type );
}

=head2 $apache-E<gt>set_default_package()

Set the "system default" package for the supplied language.

=head3 Required argument keys

=over 4

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to configure.

=item package

The package name we want to set as the system default.

=back

=head3 Returns

Nothing.

=head3 Dies

If there is an error in setting the package, this function will
attempt to roll back the changes, and throw the original
Cpanel::Exception.

=head3 Notes

=cut

sub set_default_package {
    my ( $self, %args ) = @_;

    for (qw( lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $lang        = $args{lang};
    my $new_package = $args{package};

    my $type = $lang->type();

    # 1. Get current default language handler object
    my $conf        = Cpanel::ProgLang::Conf->new( type => $lang->type() );
    my $old_handler = $self->get_default_handler( lang => $lang );
    my $old_package = $old_handler->get_lang_obj->get_package_name();

    try {
        # Update cPanel with new default package
        $conf->set_system_default_package( info => $new_package );

        # Update Apache
        my $conf_str = $self->get_config_string( lang => $lang, conf => $conf );
        $self->write_config_file( lang => $lang, conf_str => $conf_str );
        $self->queue_restart() if defined $args{'restart'} and $args{'restart'};
    }
    catch {

        # 4. If either of these updates fail, reset back to previous setting
        my $ex = $_;

        # Update cPanel with old default package
        $conf->set_system_default_package( info => $old_package );

        # Update Apache
        my $conf_str = $self->get_config_string( lang => $lang, conf => $conf );
        $self->write_config_file( lang => $lang, conf_str => $conf_str );

        # NOTE: No need to restart if we failed since that's the last step above

        # Pass the exception we caught back up to the caller
        die $ex;
    };

    return 1;
}

=head2 $apache-E<gt>set_package_handler()

Applies a content handler to a package so that applications of that type
can be executed.  This makes its changes in the global Apache configuration
area (e.g. conf.d/php.conf).  The result of this change is that a virtual
host is forced to use the admin-specified Apache handler assigned to a
package.

While the user is free to choose a different package (e.g. ea-php99) for
their virtual host, they cannot choose the handler (e.g. suphp).

=head3 Required argument keys

=over 4

=item handler

An object derived from
Cpanel::WebServer::Supported::apache::Handler::base.

=back

=head3 Returns

True

=head3 Dies

If there is an error setting the handler, this method will attempt to
roll back to the previous configuration.  It will throw a
Cpanel::Exception, which should include the error message which caused
the initial failure.

=head3 Notes

If a handler implements the I<unset_lang_handler()> or
I<set_lang_handler()> methods, they will be called at the appropriate
times.

=cut

sub set_package_handler {
    my ( $self, %args ) = @_;

    for (qw( type lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $type    = $args{type};       # e.g. suphp
    my $lang    = $args{lang};       # an instance of Cpanel::ProgLang::Supported::*
    my $package = $args{package};    # e.g. ea-php99

    # It doesn't make sense to allow packages to inherit their Apache handler.  You
    # can set them to a specific Apache handler, or disable ('none' handler), but
    # certainly not inherit.
    die Cpanel::Exception::create( 'AttributeNotSet', q{You can not set a package to the “[_1]” [asis,Apache] handler.}, [$type] ) if $type eq 'inherit';

    my $new_handler = $self->make_handler(%args);

    # Get current handler for this package so we can revert if needed
    my $conf        = Cpanel::ProgLang::Conf->new( type => $lang->type() );
    my $old_type    = $conf->get_package_info( package => $package );
    my $old_handler = $self->make_handler( lang => $lang, package => $package, type => $old_type );

    try {
        # Update cPanel
        $conf->set_package_info( package => $package, info => $type );

        # Update Apache
        $old_handler->unset_lang_handler() if $old_handler->can('unset_lang_handler');
        my $conf_str = $self->get_config_string( lang => $lang, conf => $conf );
        $self->write_config_file( lang => $lang, conf_str => $conf_str );
        $new_handler->set_lang_handler() if $new_handler->can('set_lang_handler');
        $self->queue_restart()           if $args{restart};
    }
    catch {
        # If either of these updates fail, reset back to previous setting
        my $ex = $_;

        # Update cPanel
        $conf->set_package_info( package => $package, info => $old_type );

        # Update Apache
        $new_handler->unset_lang_handler() if $new_handler->can('unset_lang_handler');
        my $conf_str = $self->get_config_string( lang => $lang, conf => $conf );
        $self->write_config_file( lang => $lang, conf_str => $conf_str );
        $old_handler->set_lang_handler() if $old_handler->can('set_lang_handler');

        # NOTE: No need to restart if we failed since that's the last step above

        # Pass the exception we caught back up to the caller
        die $ex;
    };

    return 1;
}

=pod

=head2 $apache-E<gt>update_user_package_handlers()

Updates each virtual host's .htaccess file with a
content handler that matches the requested package.

This is useful when the handler for a package has changed,
but each vhost using that package hasn't updated the
mime-type in their .htaccess file.  Without this change,
a user could be left without the ability to serve
applications.

=head3 INPUT

=over 2

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to configure.

=item package

The package name we want to set as the system default.

=back

=head3 OUTPUT

=over 2

=item Returns truthy value on success

=back

=head3 EXCEPTIONS

=over 2

=item Emits Cpanel::Exception(s) on failure

=back

=cut

sub update_user_package_handlers {
    my ( $self, %args ) = @_;

    for (qw( lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $lang    = $args{lang};       # an instance of Cpanel::ProgLang::Supported::*
    my $package = $args{package};    # e.g. ea-php99
    my @error;
    my %users;

    Cpanel::Config::LoadUserDomains::loadtrueuserdomains( \%users, 1 );

    while ( my ( $user, $domain ) = each(%users) ) {
        next unless $domain;                                    # some accounts are invalid and don't contain a domain in the /etc/trueusersdomain configuration file (thanks Perk...)
        my $cfg = try { Cpanel::Config::LoadCpUserFile::load_or_die($user) };
        next unless $cfg;
        next if $cfg->{PLAN} =~ /Cpanel\s+Ticket\s+System/i;    # Accounts like this are created by the autofixer2 create_temp_reseller_for_ticket_access script when cpanel support logs in

        my $userdata = Cpanel::WebServer::Userdata->new( user => $user );

        for my $vhost ( @{ $userdata->get_vhost_list() } ) {

            try {
                my $pkg = $userdata->get_vhost_lang_package( lang => $lang, vhost => $vhost );
                if ( $pkg eq $package ) {

                    # Found a vhost using $package, now update the vhost to ensure
                    # it's using the correct handler.
                    $self->set_vhost_lang_package( userdata => $userdata, vhost => $vhost, lang => $lang, package => $package );
                }
            }
            catch {
                push @error, $_;
            };
        }
    }

    die Cpanel::Exception::create( 'Collection', [ exceptions => \@error ] ) if @error > 1;
    die $error[0]                                                            if @error == 1;

    return 1;
}

=pod

=head2 $apache-E<gt>get_available_handlers()

Returns which handlers are available for a package.

Available means that the package itself supports the SAPI,
and the web server has the necessary modules loaded.

=head3 Arguments

=over 4

=item lang

An instance of Cpanel::ProgLang.

=item package

The package name

=back

=head3 Returns

A hash ref which maps handlers to instances of the
associated Handler object.

=cut

sub get_available_handlers {
    my ( $self, %args ) = @_;
    my %handlers;

    for (qw( lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $lang    = $args{lang};
    my $package = $args{package};

    my $hndl = Cpanel::WebServer::Supported::apache::Handler->new( webserver => $self );

    # Only return handlers that support the language's SAPI interfaces.
    my $lang_obj = $lang->get_package( package => $package );

    for my $sapi ( $lang_obj->get_sapi_list(), 'suphp', 'lsapi', 'none' ) {
        $sapi = 'dso' if $sapi eq 'apache2';
        my $handler = try { $self->make_handler( type => $sapi, lang => $lang, package => $package, lang_obj => $lang_obj ) };
        $handlers{$sapi} = $handler if $handler;
    }

    return \%handlers;
}

=head2 $apache-E<gt>set_vhost_lang_package()

Sets the language package for a given virtual host.

=head3 Required argument keys

=over 4

=item userdata

An object of type Cpanel::WebServer::Userdata, which references the
user who owns the virtual host to be modified.

=item vhost

The name of the virtual host to be configured.

=item lang

An object from Cpanel::ProgLang-E<gt>new(), of the language type we want
to configure.

=item package

The package name that the virtual host should use.

=back

=head2 Optional argument keys

=over 4

=item old_package

Pass this in to prevent a lookup of the old package, which will
speed up execution of this function.

=back

=head3 Returns

Nothing.

=head3 Dies

If there is an error setting the handler, this method will attempt to
roll back to the previous configuration.  It will throw a
Cpanel::Exception, which should include the error message which caused
the initial failure.

=head3 Notes

If a handler defines the I<unset_vhost_handler> and/or
I<set_vhost_handler> routines, they will be called at the appropriate
times.

=cut

sub set_vhost_lang_package {
    my ( $self, %args ) = @_;

    for (qw( userdata vhost lang package )) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $_ ] ) unless defined $args{$_};
    }

    my $userdata = $args{userdata};
    my $vhost    = $args{vhost};
    my $lang     = $args{lang};
    my $new_pkg  = $args{package};
    my $old_pkg  = $args{old_package};    # We look it up if its not passed

    # Prevent arbitrary path traversal using invalid domain
    # get_vhost_map performs poorly with many domains.  This
    # was switched to getdomainowner to mirror the change in CPANEL-31058
    if ( !Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $vhost, { default => '' } ) ) {
        die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The supplied domain name is invalid.' );
    }

    my $conf     = Cpanel::ProgLang::Conf->new( type => $lang->type() );
    my $htaccess = $self->make_htaccess( user => $userdata->user(), userdata => $userdata );
    my $new_type = $new_pkg eq 'inherit' ? 'inherit' : $conf->get_package_info( package => $new_pkg );

    if ( $new_pkg ne 'inherit' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::PHPFPM::Get');
        if ( Cpanel::PHPFPM::Get::get_php_fpm( $userdata->user(), $vhost ) ) {
            $new_type = 'fpm';
        }
    }

    my $new_handler = $self->make_handler( lang => $lang, package => $new_pkg, type => $new_type );

    $old_pkg ||= $userdata->get_vhost_lang_package(%args);
    my $old_type = $old_pkg eq 'inherit' ? 'inherit' : $conf->get_package_info( package => $old_pkg );
    $old_pkg = $old_type = 'inherit' unless $old_type;
    my $old_handler = $self->make_handler( lang => $lang, package => $old_pkg, type => $old_type );
    return _update_vhost( $old_handler, $htaccess, $userdata, $new_handler, $vhost, $lang, $new_pkg, $old_pkg, %args );
}

sub _update_vhost {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $old_handler, $htaccess, $userdata, $new_handler, $vhost, $lang, $new_pkg, $old_pkg, %args ) = @_;

    try {
        $old_handler->unset_vhost_handler() if $old_handler->can('unset_vhost_handler');
        $htaccess->set_handler( %args, handler => $new_handler );

        # Cpanel::WebServer::set_vhost_lang_package already changes the userdata
        # we should not do it twice
        $new_handler->set_vhost_handler() if $new_handler->can('set_vhost_handler');
    }
    catch {
        my $ex = $_;

        # Set everything back.  Hopefully we won't blow up here too.
        $new_handler->unset_vhost_handler() if $new_handler->can('unset_vhost_handler');
        $htaccess->set_handler( %args, handler => $old_handler );
        $userdata->set_vhost_lang_package( vhost => $vhost, lang => $lang, package => $old_pkg );
        $old_handler->set_vhost_handler() if $old_handler->can('set_vhost_handler');

        # TODO:  Word this so we can pass $ex back in the string.
        die Cpanel::Exception::create( 'AttributeNotSet', qq{There was an error setting package “[_1]” for virtual host “[_2]”. Restoring the previous setting: [_3]}, [ $new_pkg, $vhost, $ex ] );
    };

    return 1;
}

=head1 DEPENDENCIES

Cpanel::ConfigFiles::Apache::modules, Cpanel::ConfigFiles::Apache,
Cpanel::Exception, Cpanel::HttpUtils::ApRestart::BgSafe, Cpanel::ProgLang,
Cpanel::ProgLang::Conf, Cpanel::LoadModule,
Cpanel::WebServer::Supported::apache::Handler,
Cpanel::WebServer::Supported::apache::Htaccess, and Try::Tiny.

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>, L<Cpanel::WebServer>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
