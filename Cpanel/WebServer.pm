package Cpanel::WebServer;

# cpanel - Cpanel/WebServer.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer

=head1 SYNOPSIS

    use Cpanel::ProgLang      ();
    use Cpanel::WebServer ();

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $ws = Cpanel::WebServer->new();

    my $servers = $ws->get_server_list();

    my $apache = $ws->get_server( 'type' => 'apache' );

    my $package = $ws->get_vhost_lang_package( 'lang' => $php, 'user' => 'bob', 'vhost' => 'bob.com' );

    my $packages = $ws->get_vhost_lang_packages( 'lang' => $php, 'user' => 'bob' );

=head1 DESCRIPTION

Cpanel::WebServer is the primary interface for interacting with
supported web service-related programs.  It sits at the root of a
namespace which can contain any web-related service.  The
Cpanel::WebServer module serves as an implementation-agnostic frontend
to all the typical configuration actions we want to perform on a
webserver.

Any of the modules within the Cpanel::WebServer tree can throw
exceptions, and will do so instead of any error-return values.  This
allows us to keep the code relatively clean, and focus on data flow,
rather than error handling.

Please see L<Cpanel::WebServer::Overview> for documentation on the
nomenclature we use throughout this module tree, concerning I<lang>,
I<lang_obj>, and I<package>.

=cut

use strict;
use warnings;
use Cpanel::Exception           ();
use Cpanel::LoadModule          ();
use Cpanel::WebServer::Userdata ();
use Try::Tiny;

=head1 VARIABLES

=head2 @ServerMethods

The names of methods which are required for a child webserver to
operate.  Before returning a handle to a specific webserver object,
the B<get_server()> method will verify that the new object can call
each of these.  An exception will be thrown if one is not supported.

=cut

my @ServerMethods = qw(
  type modules config
  get_default_handler set_default_package
  make_handler set_package_handler
  get_available_handlers
);

=head1 METHODS

All methods validate whether they have received the correct arguments,
and will throw a Cpanel::Exception if a required argument is missing.

=head2 Cpanel::WebServer-E<gt>new()

Creates a new object.

=head3 Returns

A new Cpanel::WebServer object.

=head3 Notes

There is very little state that this object keeps at the moment.

=cut

sub new {
    return bless( {}, shift );
}

=head2 $webserver-E<gt>get_server_list()

Retrieve a list of supported server types.

=head3 Returns

A hashref containing information about each of the active webserver
types.  Keys are of the type, and values are hashrefs containing
arbitrary information about each type.

=head3 Notes

Currently this returns a hard-coded list of a single item, since
Apache is the only supported webserver at the moment.

=cut

sub get_server_list {
    my $self = shift;

    # TODO: Automate how we discover web servers on the system by looking
    #       in /var/cpanel/perl/Cpanel/WebServer for customer-defined override
    #       and additional supported servers.
    return {
        apache => { name => 'Apache' },
    };
}

=head2 $webserver-E<gt>get_server()

Get a handle to a webserver-specific implementation

=head3 Required argument keys

=over 4

=item type

The type of webserver to which we want a handle.  Recognized types are
the keys which are returned from I<get_server_list()>.

=back

=head3 Returns

An object from one of the classes within the
Cpanel::WebServer::Supported namespace.

=head3 Dies

Cpanel::Exceptions are thrown in the cases of:

=over 4

=item *

Failure to load module

=item *

Missing methods in loaded module

=back

=head3 Notes

=cut

sub get_server {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'type' ] ) unless defined $args{'type'};

    my $type = $args{'type'};
    return $self->{_server}{$type} if $self->{_server}{$type};
    my $list = $self->get_server_list();
    die Cpanel::Exception::create( 'FeatureNotEnabled', 'The “[_1]” web server type is not supported.', [$type] ) unless defined $list->{$type};

    # TODO: Look in /var/cpanel/perl/Cpanel/WebServer for customer-defined override
    #       and additional supported servers.
    my $pkg = sprintf( '%s::Supported::%s', __PACKAGE__, $type );

    try {
        Cpanel::LoadModule::load_perl_module($pkg);
    }
    catch {
        my $ex = $_;
        die Cpanel::Exception::create( 'FeatureNotEnabled', 'The system was unable to load the “[_1]” web server type: [_2]', [ $type, $ex->get_string() ] );
    };

    for my $method (@ServerMethods) {
        die Cpanel::Exception::create( 'MissingMethod', [ method => $method, pkg => $pkg ] ) unless $pkg->can($method);
    }

    return ( $self->{_server}{$type} ||= $pkg->new() );
}

=head2 $webserver-E<gt>get_vhost_lang_package()

Retrieve the language package from a single virtual host a user owns.

=head3 Required argument keys

=over 4

=item user

The user who owns the virtual host we want to query.

=item lang

The language for which we want the virtual host's package name.  This
argument should be something which was returned by
Cpanel::ProgLang-E<gt>new().

=item vhost

The name of the virtual host for which we want the package name.

=back

=head3 Returns

The package name which corresponds to the I<lang> argument for the
supplied user.

=head3 Notes

This method and the plural version below should be renamed to reflect
the fact that it's returning more than just package info.

=cut

sub get_vhost_lang_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )  unless defined $args{'user'};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )  unless defined $args{'lang'};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $args{'vhost'};

    my $userdata = Cpanel::WebServer::Userdata->new( 'user' => $args{user} );
    return $userdata->get_vhost_lang_package( lang => $args{lang}, vhost => $args{vhost} );
}

=head2 $webserver-E<gt>get_vhost_lang_packages()

Retrieve the language package names from all of the virtual hosts a
user owns.  This is the batch form of I<get_vhost_lang_package()>
above.

=head3 Required argument keys

=over 4

=item user

The user whose virtual hosts we want to query.

=item lang

The language for which we want the virtual hosts' package names.  This
argument should be something which was returned by
Cpanel::ProgLang-E<gt>new().

=back

=head3 Returns

An array ref containg a hashref for each virtual host.  The hashref
will contain data as the following:

    $retval = {
        'vhost'        => 'user.com',
        'version'      => 'ea-lang123',
        'account'      => 'user'
        'documentroot' => '/home/user/public_html',
        'homedir'      => '/home/user',
        'main_domain'  => 1,
    }

=head3 Notes

=cut

sub get_vhost_lang_packages {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) unless defined $args{'user'};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] ) unless defined $args{'lang'};

    my @data;

    my $userdata = Cpanel::WebServer::Userdata->new( 'user' => $args{user} );
    my $vhosts   = $userdata->get_vhost_list();

    for my $vhost (@$vhosts) {
        my $vdata   = $userdata->get_vhost_data( 'vhost' => $vhost );
        my $package = $self->get_vhost_lang_package( %args, 'vhost' => $vhost );
        push @data,
          {
            'vhost'        => $vhost,
            'version'      => $package,
            'account'      => $args{'user'},
            'documentroot' => $vdata->{'documentroot'},
            'homedir'      => $vdata->{'homedir'},
            'main_domain'  => $userdata->is_main_vhost($vhost),
          };
    }

    return \@data;
}

=head2 $webserver-E<gt>get_userdata( user =E<gt> $user )

Retrieve handle to a userdata object.

=head3 Required argument keys

=over 4

=item user

The username about which we want to retrieve information.

=back

=head3 Returns

A Cpanel::WebServer::Userdata object.

=head3 Notes

The userdata instance caches a single user to reduce the load of
continuously validating it, as well as reading the content off of
disk repeatedly.  However, if you retrieve the userdata for a
different user on a subsequent call using the same instance, then
the cache is invalidated, and all caching applies to the new user.

This ensures:

=over 2

=item * This module doesn't cache more than it should during the
life of the instance (e.g. don't keep a persistent instance lying
around!).

=item *

We don't cache data that's already cached.

=back

=cut

sub get_userdata {
    my ( $self, %args ) = @_;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) unless defined $args{'user'};
    my $ud;

    # look to see if we already cached this user's userdata
    if ( $self->{_userdata} ) {
        $ud = $self->{_userdata};

        # we stored a different user, create a new one
        if ( $ud->user() ne $args{user} ) {
            delete $self->{_userdata};
            $ud = undef;
        }
    }

    unless ($ud) {
        $ud = Cpanel::WebServer::Userdata->new( user => $args{user} );
        $self->{_userdata} = $ud;
    }

    return $ud;
}

=head2 $webserver-E<gt>set_vhost_lang_package()

This method sets the package name to be used for a language, for a
given user/virtual host.

=head3 Required argument keys

=over 4

=item user

The username for which we want to change settings.

=item vhost

The virtual host for which we want to change settings.

=item lang

The language for which we need to change settings.  This argument
should be something which was returned by Cpanel::ProgLang-E<gt>new().

=item package

The name of the language package that we want the supplied virtual
host to use.

=back

=head3 Returns

Nothing.

=head3 Dies

If either of the two operations (setting the configuration file,
setting the virtual host itself) fails, we will roll the settings
back, and throw a Cpanel::Exception.

=head3 Notes

The procedure involves changing the configuration files, then changing
the package to match.  If there is an error, we will try to revert the
settings to the previous values.  Since it is simpler to change the
configuration file setting, we'll do that first, so in the case of a
rollback, we'll only need to reset the config file.  If we do indeed
fail, and do a rollback, the original exception will be thrown.

=cut

sub set_vhost_lang_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )    unless defined $args{user};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] )   unless defined $args{vhost};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] ) unless defined $args{package};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )    unless defined $args{lang};

    my $userdata = $self->get_userdata( user => $args{user} );

    # Save the old package name, in case we need to roll it back
    my $old_pkg = $userdata->get_vhost_lang_package( vhost => $args{vhost}, lang => $args{lang} );

    # TODO: In the future, we wouldn't want to hard-code Apache if we supported multiple server types
    my $server = $self->get_server( type => 'apache' );

    try {
        $server->set_vhost_lang_package( vhost => $args{vhost}, lang => $args{lang}, package => $args{package}, userdata => $userdata, old_package => $old_pkg );
        $userdata->set_vhost_lang_package( vhost => $args{vhost}, lang => $args{lang}, package => $args{package}, old_package => $old_pkg, skip_userdata_cache_update => $args{skip_userdata_cache_update} ) if $old_pkg ne $args{package};
    }
    catch {
        my $ex = $_;

        # Roll back the setting, in case we can't get the webserver to
        # be happy.  The setting is the easier of the two to change,
        # and we'll have already succeeded in changing it, so we
        # should be able to easily revert it.
        $server->set_vhost_lang_package( vhost => $args{vhost}, lang => $args{lang}, package => $old_pkg, userdata => $userdata );
        $userdata->set_vhost_lang_package( vhost => $args{vhost}, lang => $args{lang}, package => $old_pkg );

        # We still do want to throw the exception
        die $ex;
    };

    return 1;
}

=head2 $webserver-E<gt>set_vhost_lang_packages()

This method sets the package names to be used for a language, for a
given set of virtual hosts owned by a user.  This is the batch form of
I<set_vhost_lang_package()> above.

=head3 Required argument keys

=over 4

=item user

The username for which we want to change settings.

=item vhosts

An array ref to a list of virtual host names which we want to change.

=item lang

The language for which we need to change settings.  This argument
should be something which was returned by Cpanel::ProgLang-E<gt>new().

=item package

The name of the language package that we want the supplied virtual
hosts to use.

=back

=head3 Returns

A hash ref, containing two array refs to the successful and failed
virtual host names, as the following:

    $retval = {
        'success' => (
            'foo.com',
            'bar.com',
            'baz.com',
        ),
        'failure' => (
            'xip.com is not owned by user bob',
            'doo.com is really broken in some other way',
        ),
    }

=head3 Dies

Instead of dying if there was any error, this method will collate the
errors, and return them as part of the return structure.

=head3 Notes

=cut

sub set_vhost_lang_packages {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] )                                      unless defined $args{user};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhosts' ] )                                    unless defined $args{vhosts};
    die Cpanel::Exception::create( 'InvalidParameter', 'The parameter “[_1]” must be an arrayref.', ['vhosts'] ) unless ref $args{vhosts} eq 'ARRAY';
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'package' ] )                                   unless defined $args{package};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )                                      unless defined $args{lang};

    my ( @ok, @errors );
    my $vhosts = delete $args{'vhosts'};
    for my $vhost (@$vhosts) {
        try {
            $self->set_vhost_lang_package( 'vhost' => $vhost, %args );
            push @ok, $vhost;
        }
        catch {
            my $ex = $_;
            push @errors, Cpanel::Exception::create( 'InvalidParameter', 'The system failed to apply the “[_1]” version to “[_2]”: [_3]', [ uc $args{lang}->type(), $vhost, $ex ] );
        };
    }
    return { 'success' => \@ok, 'failure' => \@errors };
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

Cpanel::Exception, Cpanel::LoadModule, Cpanel::WebServer::Userdata,
and Try::Tiny.

=head1 TODO

Verify that any regular expressions use \Q\E as necessary.

Each function that we need to do on an individual webserver, we will
need to eventually (a) figure out which webservers are installed and
active, and (b) loop through them, calling out to each one.  Under
ordinary circumstances, a caller should not have to think about which
webservers are installed.  Functions such as set_vhost_lang_package
will need this behaviour.

We need to look in /var/cpanel/perl for other user-supplied webserver
modules we may need to load.

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
