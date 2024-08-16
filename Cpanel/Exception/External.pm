package Cpanel::Exception::External;

# cpanel - Cpanel/Exception/External.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Exception::External - 3rd-party-safe instantiation of Cpanel::Exception

=head1 SYNOPSIS

    use Cpanel::Exception::External ();

    #This throws an exception of class “Cpanel::Exception::Market::OrderNotFound”.
    die Cpanel::Exception::External::create( 'Market::OrderNotFound' );

    die Cpanel::Exception::External::create( 'Market::OrderNotFound', \%args );

=head1 DESCRIPTION

This module can create externally-consumable
exceptions. It will refuse to create exceptions that are not subclasses of
C<Cpanel::Exception::External::Base>.

3rd-party developers may call into this module to give specific information
about a failure to cPanel’s framework layer.

B<IMPORTANT!!>: This module represents the B<ONLY> method that cPanel
documents for creating C<Cpanel::Exception> instances. cPanel does B<NOT>
guarantee that creation of exceptions by other means, or that creation of
exceptions that cPanel does not document for creation by 3rd-party code,
will continue to work from version to version. B<CAVEAT PROGRAMMATOR!>

=head1 SPECIFIC EXAMPLE

The UAPI call C<Market::set_url_after_checkout()> calls into a cPanel Market
provider module that may be cPanel’s own or may be a third-party module.
These called modules can throw C<Cpanel::Exception::Market::OrderNotFound>
to indicate that the logged-in provider user doesn’t have an order with the
referenced ID.

The UAPI layer catches this exception and packages the relevant information
into that API call’s C<data> before rethrowing the exception. The API caller
then, on parsing the error, checks the response’s C<data> to see if the API
call included the specific indicator of that specific error.

In this case, C<OrderNotFound> prompts the browser, rather than aborting the
checkout entirely, to invite the user to log in as a different user on the
provider’s store rather than giving up on the entire checkout process.

=head1 RATIONALE (FOR CPANEL DEVELOPERS)

cPanel’s exception system was developed to satisfy internal needs only; there
was no apparent need to communicate machine-parsable details of an error to
API callers at the time. Now that the need for such has surfaced, it is
desirable to use a ready-made exception system rather than compelling 3rd-party
developers to roll their own.

It would be problematic, however, to expose our entire internal exception
system to 3rd-party developers. That system is capable of far more things
than are useful for 3rd-party interaction with our code, and exposing those
would risk having a 3rd-party developer unwittingly build a dependency on a
part of the system that we would later alter.

This subset of cPanel’s exception system attempts to satisfy both concerns:
3rd-party developers get established, well-worn patterns out of the box,
while cPanel can limit what is exposed to external developers so as to reduce
the risk of accidental breakage.

=cut

use strict;
use warnings;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

my $WHITE_LIST_BASE_CLASS = sprintf( '%s::Base', __PACKAGE__ );

sub create {
    my ( $class, $args_hr ) = @_;

    if ( ref $class ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "The class name cannot be a reference ($class)." );
    }

    my $module = "Cpanel::Exception::$class";

    Cpanel::LoadModule::load_perl_module($module);

    if ( !$module->isa($WHITE_LIST_BASE_CLASS) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Exceptions of type “$class” are not white-listed for external consumption. ($WHITE_LIST_BASE_CLASS)" );
    }

    if ( defined $args_hr && 'HASH' ne ref $args_hr ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "The arguments, if given, must be in a hash reference, not “$args_hr”." );
    }

    #can() to avoid locale parsing
    return Cpanel::Exception->can('create')->( $class, $args_hr || () );
}

1;
