package Cpanel::Template::Plugin::CpanelOS;

# cpanel - Cpanel/Template/Plugin/CpanelOS.pm      Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::CpanelOS

=head1 DESCRIPTION

Template Toolkit plugin which allows templates to call Cpanel::OS directly,
rather than continuing to use the properties from there indirectly.

=head1 METHODS

=cut

use parent 'Template::Plugin';

use Template::Exception ();
use Cpanel::OS          ();
use Cpanel::Set         ();

use Try::Tiny;

=head2 $obj = I<CLASS>->new( $context, @properties )

Create an instance of the plugin. Accepts a L<Template::Context> for the first
parameter, as specified by the parent class. This is transparent to use in the
template itself. Additional parameters represent a declaration of which
L<Cpanel::OS> properties are being used in the template.

    [% USE CpanelOS ('property1', 'property2'); %]

Properties which are listed but do not exist in L<Cpanel::OS> will immediately
throw an exception at the time of plugin initialization. Additionally,
properties used but not listed will B<always> throw an exception, even if they
do exist.  If you want to avoid this behavior because you are using the C<TRY>
exception handling mechanism native to Template Toolkit, you can list these in
an arrayref passed as the C<exempt> named parameter instead:

    [% USE CpanelOS ('property1', 'property2', exempt=['property3']); %]

It will also accept a simple scalar in the case of a single exempt property.

=cut

sub new ( $class, $context, @properties ) {

    # Extract exempted properties, if requested:
    my $config = ref( $properties[-1] ) eq 'HASH' ? pop(@properties) : {};
    $config->{'exempt'} //= [];
    $config->{'exempt'} = [ $config->{'exempt'} ] if ref( $config->{'exempt'} ) eq '';
    $context->throw( 'CpanelOS', 'The “exempt” named parameter needs to be an arrayref or non-ref scalar' ) unless ref( $config->{'exempt'} ) eq 'ARRAY';
    my @exempt_properties = $config->{'exempt'}->@*;

    # Bail out if a non-exempt property does not exist:
    my @missing_properties = Cpanel::Set::difference( \@properties, [ Cpanel::OS::supported_methods(), qw(distro major minor build) ] );    # Core properties don't show up under Cpanel::OS::supported_methods
    if ( scalar @missing_properties ) {
        $context->throw( 'CpanelOS', 'The following declared properties do not exist in the current version of cPanel: ' . join( q{, }, @missing_properties ) );
    }

    return bless { _CONTEXT => $context, _declared_properties => \@properties, _exempt_properties => \@exempt_properties }, $class;
}

=head2 $obj->list_contains_value( $key, $value )

Pass-through to C<list_contains_value> in L<Cpanel::OS>. Throws an exception in
the same way as direct invocation of a property would (see below).

    [% USE CpanelOS ('property'); %]

    [% IF CpanelOS.list_contains_value( "property", "item" ) %]
        show some text
    [% END %]

=cut

sub list_contains_value ( $self, $key, $value ) {
    $self->{'_CONTEXT'}->throw( 'CpanelOS', "The “$key” Cpanel::OS property was not declared at plugin initialization" ) unless $self->_is_declared($key);
    return try {
        Cpanel::OS::list_contains_value( $key, $value );
    }
    catch {
        my $ex = $_;
        chomp $ex unless ref $ex;
        $self->{'_CONTEXT'}->throw( 'CpanelOS', $ex );
    };
}

=head1 PROPERTIES

=head2 CORE PROPERTIES

=over

=item * distro

=item * major

=item * minor

=item * build

=back

Invoke the core properties inherent to an OS, which are handled specially by
L<Cpanel::OS>.  These should B<not> be used without considering whether another
property should be created or already exists. They are, almost always, not the
question users of this plugin should be asking.

These properties are not subject to the normal exempt/non-exempt behavior. You
can still list them during initialization, and it's probably better practice to
do that anyway.

=cut

# These are fine as-is, because they don't take args:
*distro = \&Cpanel::OS::distro;
*major  = \&Cpanel::OS::major;
*minor  = \&Cpanel::OS::minor;
*build  = \&Cpanel::OS::build;

=head2 NORMAL PROPERTIES

Other properties are invoked as method calls from within a template. Template
Toolkit can, as you may know, handle simple scalar values, arrayrefs, and
hashrefs returned in this way; see L<Template::Manual> for more information.

Attempting to invoke a property which does not exist will result in the plugin
throwing a L<Template::Exception> object with the error passed along from
L<Cpanel::OS>.

As mentioned in the constructor's documentation, properties of this kind not
declared at plugin initialization will never work and always throw an
exception.

=cut

our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    $Cpanel::OS::AUTOLOAD = $AUTOLOAD;
    my $sub = $AUTOLOAD =~ s/.*:://r;

    # Short-circuit if instance can() do what is asked:
    my $can = $self->can($sub);
    return $can->( $self, @_ ) if defined $can;

    # Bail out if (non-core) property is undeclared:
    $self->{'_CONTEXT'}->throw( 'CpanelOS', "The “$sub” Cpanel::OS property was not declared at plugin initialization" ) unless $self->_is_declared($sub);

    return try {
        Cpanel::OS::AUTOLOAD(@_);
    }
    catch {
        my $ex = $_;
        chomp $ex unless ref $ex;
        $self->{'_CONTEXT'}->throw( 'CpanelOS', $ex );
    };
}

sub DESTROY { }

sub _is_declared ( $self, $property ) {
    return scalar( grep { $_ eq $property } $self->{'_declared_properties'}->@*, $self->{'_exempt_properties'}->@* ) > 0;
}

1;
