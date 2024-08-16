package Cpanel::ProgLang;

# cpanel - Cpanel/ProgLang.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::ProgLang

Note: All Cpanel::ProgLang namespaces and some attribute inconsistencies will change in ZC-1202. If you need to use Cpanel::ProgLang please note the specifics in ZC-1202 so the needful can be had.

=head1 SYNOPSIS

    use Cpanel::ProgLang ();

    my $lang = Cpanel::ProgLang->new( type => 'php' );

=head1 DESCRIPTION

Cpanel::ProgLang is the primary interface for interacting with supported
programming languages.  It sits at the root of a namespace which can
contain any language.  The Cpanel::ProgLang module itself is only
responsible for verifying that a language is indeed supported, loading
the relevant module, and passing back an object.

Any of the modules within the Cpanel::ProgLang tree can throw exceptions,
and will do so instead of any error-return values.  This allows us to
keep the code relatively clean, and focus on data flow, rather than
error handling.

=cut

use strict;
use warnings;    # we want to remove this before we're done
use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Try::Tiny;

=head1 VARIABLES

=head2 @LangMethods

The names of methods which are required for a child language to
operate.  Before returning a valid object, the B<new()> method will
check that the new object can call each of these.  An exception will
be thrown if one is not supported.

=cut

# TODO: add missing methods which are defined in Cpanel::ProgLang::Supported::apache
my @LangMethods = qw(
  new type parent get_package
  get_installed_packages get_system_default_package set_system_default_package
);

=head1 METHODS

=head2 Cpanel::ProgLang-E<gt>new( 'type' =E<gt> $lang )

The only method in the Cpanel::ProgLang class.  It acts as a validator and
module loader for each of the specific language types that cPanel
supports.  Arguments are expected in hash format.

=head3 Required argument keys

=over 4

=item type

The name of the language module.  All language modules should be in
lowercase.

=back

=head3 Returns

An object of type Cpanel::ProgLang::Supported::E<lt>language_typeE<gt>

=head3 Dies

Cpanel::Exceptions are thrown in the cases of:

=over 4

=item *

Missing I<lang> parameter

=item *

Failure to load module

=item *

Missing methods in loaded module

=back

=cut

sub new {
    my ( $class, %args ) = @_;
    my $self = bless( {}, $class );

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'type' ] ) unless defined $args{type};

    # TODO: Look in /var/cpanel/perl/Cpanel/ProgLang for customer-defined override
    my $pkg = sprintf( '%s::Supported::%s', __PACKAGE__, $args{type} );

    try {
        Cpanel::LoadModule::load_perl_module($pkg);
    }
    catch {
        # re-throw as a more meaningful error
        die Cpanel::Exception::create( 'FeatureNotEnabled', '“[_1]” is not installed on the system: [_2]', [ $args{'type'}, $_->get_string() ] );
    };

    # Ensure language implements all required methods
    for my $method (@LangMethods) {
        die Cpanel::Exception::create( 'MissingMethod', [ method => $method, pkg => $pkg ] ) unless $pkg->can($method);
    }

    return $pkg->new( 'parent' => $self );
}

=head1 CONFIGURATION AND ENVIRONMENT

The module has no dependencies on environment variables.  There are no
configuration files which affect this module directly, but there are
configuration-handling modules within the Cpanel::ProgLang namespace.

=head1 DEPENDENCIES

Cpanel::Exception, Cpanel::LoadModule, and Try::Tiny.

=head1 BUGS AND LIMITATIONS

Language names given in uppercase or mixed case can fail, even if the
language is legitimately supported.

There is not currently a way to retrieve a list of supported
languages.

=head1 TODO

Allow users to supply their own modules for languages within
/var/cpanel/perl.

=head1 SEE ALSO

L<Cpanel::ProgLang::Overview>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited.

=cut

1;

__END__
