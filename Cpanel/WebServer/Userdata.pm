package Cpanel::WebServer::Userdata;

# cpanel - Cpanel/WebServer/Userdata.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::WebServer::Userdata

=head1 SYNOPSIS

    use Cpanel::WebServer::Userdata ();

    my $userdata = Cpanel::WebServer::Userdata->new( 'user' => 'bob' );

    my $username = $userdata->user();

    my ( $uid, $gid ) = $userdata->id();

    my $vhost_map = $userdata->get_vhost_map();

    my $vhosts = $userdata->get_vhost_list();

    if ( $userdata->is_main_vhost( 'vhost' => 'bob.com') ) {
        print "yaay!";
    }

    my $vhost_data = $userdata->get_vhost_data( 'vhost' => 'bob.com' );

    my $docroot = $userdata->get_vhost_key( 'vhost' => 'bob.com', 'key' => 'documentroot' );

    my $lang = Cpanel::ProgLang->new( type => 'php );
    my $php_pkg = $userdata->get_vhost_lang_package( 'vhost' => 'bob.com', 'lang' => $lang );

    $userdata->set_vhost_lang_package( 'vhost' => 'bob.com', 'lang' => $lang, 'package' => 'ea-php54' );

=head1 DESCRIPTION

Cpanel::WebServer::Userdata is the primary interface for interacting
with the data which surrounds each user and virtual host.  Most of the
data resides in the /var/cpanel/userdata directory tree, but some may
be moved around as necessary, and so this class should be considered
an opaque interface to this set of data.

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
use Cpanel::LoadModule                   ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AccessIds::Normalize         ();
use Cpanel::Config::userdata::Simple     ();
use Cpanel::Exception                    ();
use Cpanel::ProgLang::Object             ();    # PPI USE OK - use with lang variable in several functions

=pod

=head1 METHODS

=head2 Cpanel::WebServer::Userdata-E<gt>new()

Create a new Userdata object.

=head3 Required argument keys

=over 4

=item user

The name of the user for whom we wish to retrieve data

=back

=head3 Returns

A blessed object of type Cpanel::WebServer::Userdata.

=head3 Dies

The constructor pre-retrieves some information which will be needed by
other methods, and which may have a significant setup cost, and does
validate that the passed-in user is actually a valid user.  A
Cpanel::Exception will result in the case of failure.

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user' ] ) unless defined $args{'user'};

    my @info = Cpanel::AccessIds::Normalize::normalize_user_and_groups( $args{user} );

    my %data = (
        _user => $args{user},
        _id   => \@info,
    );

    return bless( \%data, $class );
}

=pod

=head2 $userdata-E<gt>user()

Retrieve the username for this userdata set.

=head3 Arguments

=over 4

=item $user

The name of the user for whom we want to retrieve data.  Typically,
this method will be called without a username; this argument is mostly
for the constructor to be able to cache data.

=back

=head3 Returns

A username assigned to the Cpanel::WebServer::Userdata instance.

=cut

sub user {
    my $self = shift;
    return $self->{_user};
}

=pod

=head2 $userdata-E<gt>id()

Retrieve the uid/gid for this userdat set.

=head3 Returns

An array of ( uid, gid ).

=cut

sub id {
    my $self = shift;
    return @{ $self->{_id} };
}

=pod

=head2 $userdata-E<gt>get_vhost_map()

Retrieve a map of virtual host names.  When writing to userdata files,
cPanel requires that the subdomain name for an addon is used, rather
than the actual addon domain name.

For example, bob.com is user bob's primary domain, and he adds
alice.com as an addon domain.  alice.bob.com will be created to hold
the domain information, and cPanel expects code to use this subdomain
name when writing to the userdata.  This map will allow callers to use
alice.com to refer to this domain.

=head3 Returns

A hash ref of the type:

    $retval = {
        'bob.com' => {
            'real' => 'bob.com',
            'main' => 1,
        },
        'alice.com' => {                # An addon domain
            'real' => 'alice.bob.com',
            'main' => 0,
        },
        'foo.bob.com' => {              # A subdomain
            'real' => 'foo.bob.com',
            'main' => 0,
        }
    }

=head3 Dies

If the main userdata file (/var/cpanel/userdata/E<lt>userE<gt>/main)
can not be loaded, a Cpanel::Exception will result.

=head3 Notes

This map is likely not very interesting to outside users.  This simply
allows the module to map things so users can supply better-known names
for domains, and have them work as expected.

=cut

sub get_vhost_map {
    my $self = shift;
    my $user = $self->user();
    my %map;    # in order to change an addon domain, you must set it using the subdomain it creates

    return $self->{_cache}->{vhost_list} if $self->{_cache}->{vhost_list};

    my $data = Cpanel::Config::userdata::Simple::get_cpanel_userdata($user);
    die Cpanel::Exception::create( 'InvalidUsername', [ value => $user ] ) unless defined $data->{main_domain};

    $map{ $data->{main_domain} } = { real => $data->{main_domain}, main => 1 };

    my %addon_subs;

    while ( my ( $addon, $sub ) = each( %{ $data->{addon_domains} } ) ) {
        $map{$addon}      = { real => $sub, main => 0 };
        $addon_subs{$sub} = $addon;
    }

    for my $sub ( @{ $data->{sub_domains} } ) {
        next if $addon_subs{$sub};    # skip the subdomain each addon creates
        $map{$sub} = { real => $sub, main => 0 };
    }

    $self->{_cache}->{vhost_list} = \%map;

    return \%map;
}

=pod

=head2 $userdata-E<gt>get_vhost_list()

Retrieve the list of virtual hosts for the configured user.

=head3 Returns

An array ref of the virtual hosts which the user has configured.

=cut

sub get_vhost_list {
    my $self = shift;
    my $map  = $self->get_vhost_map();
    return [ keys %$map ];
}

=pod

=head2 $userdata-E<gt>is_main_vhost()

Check whether the supplied virtual host name is the primary for the
user.

=head3 Required argument keys

=over 4

=item vhost

The name of the virtual host to check

=back

=head3 Returns

1 if the supplied domain is the primary, 0 otherwise.

=cut

sub is_main_vhost {
    my $self  = shift;
    my $vhost = shift;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $vhost;

    my $map = $self->get_vhost_map();
    return ( $map->{$vhost}->{main} || 0 );
}

=pod

=head2 $userdata-E<gt>get_vhost_data()

Retrieve the entire set of data for a given virtual host.

=head3 Required argument keys

=over 4

=item vhost

The name of the virtual host for which we want the data

=back

=head3 Returns

A hash ref containing all the data for the given virtual host.

=cut

sub get_vhost_data {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $args{vhost};

    return Cpanel::Config::userdata::Simple::get_cpanel_vhost_userdata( $self->user(), $args{'vhost'} );
}

=pod

=head2 $userdata-E<gt>get_vhost_key()

Retrieve a single key for a given virtual host.

=head3 Required argument keys

=over 4

=item vhost

The name of the virtual host for which we want the data

=item key

The name of the key to be retrieved.

=back

=head3 Returns

The value of the supplied key, if it exists.  A nonexistent key will
return undef.

=cut

sub get_vhost_key {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $args{vhost};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'key' ] )   unless defined $args{key};

    my $ref = $self->get_vhost_data(%args);
    return $ref->{ $args{'key'} };
}

=pod

=head2 $userdata-E<gt>get_vhost_lang_package()

Retrieve the package name which is configured for a given virtual host.

=head3 Required argument keys

=over 4

=item lang

An object returned from Cpanel::ProgLang-E<gt>new(), of the language type
to be queried.

=item vhost

The name of the virtual host to be queried.

=back

=head3 Returns

The package name which is configured for the supplied virtual
host/language.  'inherit' if nothing is configured.

=cut

sub get_vhost_lang_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'lang' ] )  unless defined $args{lang};
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'vhost' ] ) unless defined $args{vhost};

    my $vhost = $args{vhost};
    my $lang  = $args{lang};

    # CPANEL-3068: Prevent arbitrary path traversal using invalid domain
    if ( Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($vhost) ne $self->user() ) {
        die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The supplied domain name is invalid.' );
    }

    my $key = sprintf( '%s' . 'version', $lang->type() );
    my $ref = Cpanel::Config::userdata::Simple::get_cpanel_vhost_userdata( $self->user(), $vhost );

    return ( $ref->{$key} || 'inherit' );
}

=pod

=head2 $userdata-E<gt>set_vhost_lang_package()

Set the package name for a given virtual host/language.

=head3 Required argument keys

=over 4

=item lang

An object returned from Cpanel::ProgLang-E<gt>new(), of the language type
to be set.

=item vhost

The name of the virtual host to be configured.

=item package

The name of the package to be configured.

=back

=head3 Returns

1

=head3 Dies

If the supplied package name is not installed on the server, a
Cpanel::Exception will result.

=head3 Notes

Once the data is moved from the /var/cpanel/userdata directory tree
into the home directory, this method will no longer call an adminbin.

=cut

sub set_vhost_lang_package {
    my ( $self, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter',  [ name => 'vhost' ] )   unless defined $args{vhost};
    die Cpanel::Exception::create( 'MissingParameter',  [ name => 'lang' ] )    unless defined $args{lang};
    die Cpanel::Exception::create( 'MissingParameter',  [ name => 'package' ] ) unless defined $args{package};
    die Cpanel::Exception::create( 'FeatureNotEnabled', q{“[_1]” version “[_2]” is not installed on the system.}, [ uc $args{'lang'}->type(), $args{'package'} ] )
      unless $args{'lang'}->is_package_installed( 'package' => $args{'package'} );

    my $vhost   = $args{vhost};
    my $lang    = $args{lang};
    my $package = $args{package};

    # Prevent arbitrary path traversal using invalid domain
    my $map = $self->get_vhost_map();
    die Cpanel::Exception::create( 'DomainNameNotAllowed', 'The supplied domain name is invalid.' ) unless defined $map->{$vhost};

    # once we migrate the vhost package to the user's home directory, we don't
    # need the userdata/adminbin stuff anymore.
    if ( $> == 0 ) {
        my $key = sprintf( '%s' . 'version', $lang->type() );
        Cpanel::Config::userdata::Simple::set_cpanel_vhost_userdata( $self->user(), $map->{$vhost}->{real}, { $key => $package }, { skip_userdata_cache_update => $args{'skip_userdata_cache_update'} } );
    }
    else {
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');    # this gets loaded into whm via Whostmgr::API::1::Lang::PHP
        Cpanel::AdminBin::Call::call( 'Cpanel', 'multilang', 'SET_VHOST_LANG_PACKAGE', $vhost, $lang->type(), $package );
    }

    return 1;
}

=pod

=head1 CONFIGURATION AND ENVIRONMENT

Since this module is intended to abstract the configuration files
within /var/cpanel/userdata, they are used heavily.  There is also the
intention to move some of the web-language-specific into the user home
directories, so files within /home/<user>/.cpanel will also be used by
this module.

There are no environment variables which are required or produced by
this module.

=head1 DEPENDENCIES

Cpanel::AccessIds::Normalize, Cpanel::AdminBin::Call,
Cpanel::Config::userdata::Simple, and Cpanel::ProgLang::Object

=head1 BUGS AND LIMITATIONS

Unknown

=head1 TODO

Move the language-specific data into ~/.cpanel for each user.

Once the language-specific data is moved into the home directory,
remove all traces of the Cpanel::AdminBin::Call.

=head1 SEE ALSO

L<Cpanel::WebServer::Overview>

L<Cpanel::Config::WebVhosts> - A similar, more tightly-focused abstraction
around userdata.

L<Cpanel::Config::WebVhost::http>, L<Cpanel::Config::WebVhost::https> -
Abstractions around the vhost configurations.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
