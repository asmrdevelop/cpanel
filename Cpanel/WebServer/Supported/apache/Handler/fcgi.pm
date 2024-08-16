package Cpanel::WebServer::Supported::apache::Handler::fcgi;

# cpanel - Cpanel/WebServer/Supported/apache/Handler/fcgi.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Supported::apache::Handler::fcgi

=head1 SYNOPSIS

    use Cpanel::ProgLang                              ();
    use Cpanel::WebServer::Supported::apache          ();
    use Cpanel::WebServer::Supported::apache::Handler ();

    my $php = Cpanel::ProgLang->new( type => 'php' );
    my $lang_obj = $php->get_package( package => 'ea-php54' );

    my $apache = Cpanel::WebServer->new()->get_server( 'type' => 'apache' );
    my $fcgi = Cpanel::WebServer::Supported::apache::Handler->new( 'type' => 'fcgi', 'lang_obj' => $lang_obj, 'webserver' => $apache );

    my $htaccess_str = $fcgi->get_htaccess_string();

    my $conf_str = $fcgi->get_config_string();

    my $default_str = $fcgi->get_default_string();

    $fcgi->unset_lang_handler();   # deletes /cgi-sys wrapper
    $fcgi->set_lang_handler();     # creates /cgi-sys wrapper

=head1 DESCRIPTION

This package subclasses
L<Cpanel::WebServer::Supported::apache::Handler::base>, and uses the
I<set_lang_handler()> and I<unset_lang_handler()> methods to add and
remove the /cgi-sys/E<lt>packageE<gt> wrapper scripts that cPanel
uses.

=cut

use parent 'Cpanel::WebServer::Supported::apache::Handler::base';

use strict;
use warnings;
use Cpanel::Exception         ();
use Cpanel::FileUtils::Copy   ();
use Cpanel::SafetyBits::Chown ();

=head1 VARIABLES

=over 4

=item $CPANEL_CGISYS_DIR

The system /cgi-sys directory resides here.

=item $CPANEL_WRAPPERS_DIR

Users may place their own wrappers for a given language package into
this directory, which will be used in the place of the default
generated files.

=back

=cut

our $CPANEL_CGISYS_DIR      = '/usr/local/cpanel/cgi-sys';
our $CPANEL_GENERIC_WRAPPER = '/usr/local/cpanel/bin/php-wrapper';
our $CPANEL_WRAPPERS_DIR    = '/var/cpanel/conf/apache/wrappers';

=head1 METHODS

=head2 Cpanel::WebServer::Supported::apache::Handler::fcgi-E<gt>new()

Create a new cgi handler object.  This will typically not be called
directly, but through the
I<Cpanel::WebServer::Supported::apache::Handler::new()> method.

=head3 Required argument keys

See L<Cpanel::WebServer::Supported::apache::Handler::base::init>() for
required arguments.

=head3 Returns

A blessed reference to a
Cpanel::WebServer::Supported::apache::Handler::fcgi object.

=head3 Notes

This calls out to the base class's I<init()>, I<module_check_or()>,
and I<sapi_check()> methods, keeping it simple and easy to understand.

=cut

sub new {
    my ( $class, %args ) = @_;
    my $self = bless( {}, $class );
    $self->init( \%args );
    $self->module_check_or( [qw(mod_fcgid)] );
    $self->sapi_check('fcgi');
    return $self;
}

=head2 $handler-E<gt>type()

Retrieves the name of this handler object.

=head3 Returns

A string of 'fcgi'.

=head3 Notes

This is one of the superclass methods which is required to be
implemented.

=cut

sub type {
    return 'fcgi';
}

=head2 $handler-E<gt>get_htaccess_string()

The configuration needed when updating an Apache .htaccess
file so that the user can change the PHP version associated
to a domain.

=cut

sub get_htaccess_string {
    my ($self) = @_;

    my $package  = $self->get_package();
    my @exts     = sort( $self->get_lang_obj()->get_file_extensions() );
    my $wrappers = join "\n", map { "        FcgidWrapper /usr/local/cpanel/cgi-sys/$package $_" } sort( $self->get_lang_obj()->get_file_extensions() );
    my $str      = <<"EOF";
<IfModule fcgid_module>
    <IfModule mime_module>
        AddHandler fcgid-script @exts
$wrappers
    </IfModule>
</IfModule>
EOF
    return $str;
}

=head2 $handler-E<gt>get_default_string()

The Apache configuration fragment needed to tell Apache that this
is the PHP version and handler to use when the user wants to use
whatever the server is using by default.

=cut

sub get_default_string {
    my ($self) = @_;
    my @exts   = sort( $self->get_lang_obj()->get_file_extensions() );
    my $str    = <<"EOF";
<IfModule fcgid_module>
    <IfModule mime_module>
        AddHandler fcgid-script @exts
    </IfModule>
</IfModule>
EOF
    return $str;
}

=head2 $handler-E<gt>get_config_string()

Retrieve a string which configures the handler in a server-wide
context.

=head3 Returns

A string suitable to write to the server-wide configuration file.

=head3 Notes

This is one of the superclass methods which is required to be
implemented.

=cut

sub get_config_string {
    my ($self) = @_;

    my $package  = $self->get_package();
    my $type     = $self->get_mime_type();
    my @wrappers = map { "FcgidWrapper /usr/local/cpanel/cgi-sys/$package $_" } sort( $self->get_lang_obj()->get_file_extensions() );
    local $" = "\n  ";
    my $str = <<"EOF";
# FCGI configuration for $package
<IfModule fcgid_module>
  @wrappers
</IfModule>
EOF
    return $str;
}

=pod

=head2 $handler-E<gt>set_lang_handler()

Creates the wrapper script needed by Apache to execute scripts
in CGI-mode.  The wrapper script is needed to ensure users cannot
override the interpreter before execution.

=head3 Returns

True

=head3 Dies

If it's unable to perform an I/O operation, it dies with a
Cpanel::Exception.

=head3 Notes

Users can supply their own wrapper scripts, by placing them in
$CPANEL_WRAPPERS_DIR, and naming them as the package name of the
language they're supporting.  If the user-supplied script is not
found, we will generate a default one.

=cut

sub set_lang_handler {
    my ($self) = @_;

    my $cgisys_file = $self->get_cgisys_filename();
    my $wrapper     = "$CPANEL_WRAPPERS_DIR/" . $self->get_package();

    if ( -e $wrapper ) {
        if ( !unlink $cgisys_file ) {
            if ( exists $!{'ENOENT'} && !$!{'ENOENT'} ) {
                die Cpanel::Exception::create( 'IO::UnlinkError', [ 'path' => $cgisys_file, 'error' => $! ] );
            }
        }
        Cpanel::FileUtils::Copy::safecopy( $wrapper, $cgisys_file );
    }
    elsif ( $self->get_package =~ /^ea-php\d+$/ ) {
        if ( !unlink $cgisys_file ) {
            if ( exists $!{'ENOENT'} && !$!{'ENOENT'} ) {
                die Cpanel::Exception::create( 'IO::UnlinkError', [ 'path' => $cgisys_file, 'error' => $! ] );
            }
        }
        Cpanel::FileUtils::Copy::safecopy( $CPANEL_GENERIC_WRAPPER, $cgisys_file );
    }
    else {
        open my $fh, '>', $cgisys_file
          or die Cpanel::Exception::create( 'IO::FileOpenError', [ 'path' => $cgisys_file, 'mode' => '>', 'error' => $! ] );

        my $lang_obj = $self->get_lang_obj();
        my $type     = uc $lang_obj->type();
        my $package  = $lang_obj->get_package_name();

        my $sapi   = $lang_obj->get_sapi_info('fcgi');
        my $binary = $sapi->{'path'};

        my $pkg  = __PACKAGE__;
        my $date = localtime;

        print $fh <<"EOF";
#!/bin/bash
#
# Creation Date: $date
# Creation Source: $pkg
#
# If you want to customize the contents of this script, then place
# a copy at $CPANEL_WRAPPERS_DIR/$package.  This will ensure
# that that it is reinstalled when Apache is updated, or the
# $type handler configuration is changed.

exec $binary
EOF
        close $fh
          or die Cpanel::Exception::create( 'IO::FileWriteError', [ 'path' => $cgisys_file, 'error' => $! ] );
    }

    Cpanel::SafetyBits::Chown::safe_chown( 0, 10, $cgisys_file );
    chmod 0755, $cgisys_file
      or die Cpanel::Exception::create( 'IO::ChmodError', [ 'path' => $cgisys_file, 'error' => $! ] );

    return 1;
}

=head2 $handler-E<gt>unset_lang_handler()

One of the optional methods, which is run as the system is getting
ready to configure something else in the place of the current
configuration.  This cleans up the /cgi-sys wrappers that cPanel
needs.

=head3 Returns

Nothing.

=head3 Dies

Any I/O error will result in a Cpanel::Exception.

=head3 Notes

In order to not leave old scripts lying around in the filesystem,
we'll go ahead and clean them up immediately as we don't need them any
longer.

=cut

sub unset_lang_handler {
    my ($self) = @_;

    # Clean up the cgi-sys wrapper file
    my $fname = $self->get_cgisys_filename();

    if ( !unlink $fname ) {

        # If the file didn't already exist, don't blow up
        if ( exists $!{'ENOENT'} && !$!{'ENOENT'} ) {
            die Cpanel::Exception::create( 'IO::UnlinkError', [ 'path' => $fname, 'error' => $! ] );
        }
    }
    return 1;
}

=pod

=head2 $handler-E<gt>get_cgisys_filename()

Retrieves the name of the /cgi-sys wrapper script for our package.

=head3 Returns

The filename of the /cgi-sys wrapper

=cut

sub get_cgisys_filename {
    my ($self) = @_;
    return "$CPANEL_CGISYS_DIR/" . $self->get_package();
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which are
required or generated by this module.

=head1 DEPENDENCIES

Cpanel::Exception, Cpanel::FileUtils::Copy, Cpanel::SafetyBits::Chown,
and Cpanel::WebServer::Supported::apache::Handler::base.

=head1 BUGS AND LIMITATIONS

Unknown

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>,
L<Cpanel::WebServer::Supported::apache>,
L<Cpanel::WebServer::Supported::apache::Handler>,
L<Cpanel::WebServer::Supported::apache::Handler::base>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;
