package Whostmgr::Packages::Info::Modular;

# cpanel - Whostmgr/Packages/Info/Modular.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Info::Modular

=head1 SYNOPSIS

    for my $component (Whostmgr::Packages::Info::Modular::get_enabled_components()) {
        ...
    }

=head1 DESCRIPTION

This module is the entry point to a framework that allows creation of
fully-pluggable package/plan (and thus cpuser) parameters. Using this
framework you can define these parameters in a single place, without
updating anything in the rest of cPanel & WHM.

See below for instructions on creating new parameters.

=head1 DESIGN CONSIDERATIONS

=over

=item * Seamless: Given a specific account component implemented via this
framework, a user of cPanel & WHM should see no indication that that
component is any less fully-integrated into the rest of cPanel & WHM
than any other.

=item * Local: B<For> B<now>, this framework’s intended users are
cPanel & WHM’s own developers, working on I<this> repository. Technical
debt should be minimized with maximum prejudice, even at the expense of
updating existing uses.

The framework is obviously useful for integrators (first- and third-party),
so once we’re satisfied that we have something suitable for those
consumers, we can add versioning and public documentation.

=item * Internally Complete: Any account component described via this
framework should be absent from the rest of cPanel & WHM’s account
configuration logic, e.g., package & account forms/APIs.

=item * General-Use: It should be possible—eventually, at least—to migrate
all data points in the cpuser file to this framework.

=back

=cut

#----------------------------------------------------------------------

use Cpanel::Context              ();
use Cpanel::LoadModule           ();
use Cpanel::LoadModule::AllNames ();

use constant {
    _NAMESPACE => __PACKAGE__,
};

my $_COMPONENT_NS = 'Whostmgr::Accounts::Component';

my %type_subclass = (
    numeric => 'Uint',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @components = get_enabled_components()

Returns a list of L<Whostmgr::Accounts::Component> instances, one
for each enabled modular parameter.

B<Must> be called in list context.

=cut

sub get_enabled_components () {
    Cpanel::Context::must_be_list();

    return _get_components(1);
}

=head2 @components = get_disabled_components()

Like C<get_enabled_components()> but returns
component objects for I<disabled> parameters.

(This is useful if, e.g., you want to fail on inputs for disabled
parameters while ignoring other unexpected inputs.)

=cut

sub get_disabled_components () {
    Cpanel::Context::must_be_list();

    return _get_components(0);
}

#----------------------------------------------------------------------

# NB: If we ever need to version this logic, this is likely where that
# awareness would be.
#
sub _get_components ($enabled_yn) {
    my @components;

    for my $ns ( _load_modules() ) {
        my @entries = $ns->can('get_entries')->();

        for my $info_hr (@entries) {
            next if !!$info_hr->{'enabled_cr'}->() ne !!$enabled_yn;

            my $subclass = $type_subclass{ $info_hr->{'type'} };
            my $cmp_ns   = Cpanel::LoadModule::load_perl_module("${_COMPONENT_NS}::$subclass");

            delete @{$info_hr}{ 'enabled_cr', 'type' };

            push @components, $cmp_ns->new(%$info_hr);
        }
    }

    return @components;
}

sub _load_modules {
    my $name_path_hr = Cpanel::LoadModule::AllNames::get_loadable_modules_in_namespace(_NAMESPACE);
    return map { Cpanel::LoadModule::load_perl_module($_) } keys %$name_path_hr;
}

#----------------------------------------------------------------------

=head1 HOW TO CREATE NEW PARAMETERS

B<IMPORTANT:> Before you proceed, ensure that you understand
L</DESIGN CONSIDERATIONS> above.

New parameters are defined in modules: one module per group of parameters.
(As of this writing there’s nothing special about “groups”, though it’s
also feasible that they could inform the UI.) Each module B<MUST> be
under this module’s namespace.

That module B<MUST> expose a function, C<get_entries()>, that returns a list
of hash references, one per account parameter. (These hash references are
never used directly; instead, this module converts them to
L<Whostmgr::Accounts::Component> instances.)

Each hash reference B<MUST> contain the following. (See
L<Whostmgr::Accounts::Component> for more details.)

=over

=item * C<enabled_cr> - coderef whose return indicates whether the parameter
is enabled on the system

=item * C<createacct_cr> - coderef that implements the component’s
createacct action. Takes the account’s username and the component’s value;
the return is discarded.

=item * C<modifyacct_cr> - Like C<createacct_cr> but for modifyacct
B<and> other contexts where the stored value changes.
Takes the account’s username, the component’s current value, and the new
value.

=item * C<removeacct_cr> - Like C<createacct_cr> but for removeacct.
Takes the account’s username.

=item * C<type> - for now always C<numeric>

=item * C<name_in_api>

=item * C<default>

=item * C<label_var>

NB: This value will probably be the return of a
call to L<Locale::Maketext::Utils::MarkPhrase>’s
C<translatable()> function.

=item * C<createacct_label_var>

NB: To tell the account-creation system that there’s nothing to do for this
component, define this as the empty string.

=item * C<removeacct_label_var>

Like C<createacct_label_var> but for account removal.

=back

You can also, I<for> I<legacy> I<parameters> I<only>, pass in
C<name_in_cpuser> and C<name_in_package>. For new stuff we want those
to derive from C<name_in_api>, but for existing stuff that’s not always
possible.

C<numeric>-type parameters can also have:

=over

=item * C<minimum>

=item * C<maximum> (can be undef)

=back

=cut

1;
