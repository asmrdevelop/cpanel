package Whostmgr::Accounts::Component;

# cpanel - Whostmgr/Accounts/Component.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Component

=head1 SYNOPSIS

See L<Whostmgr::Packages::Info::Modular>.

=head1 DESCRIPTION

This is a base class that represents an item in a cPanel user’s account
data (i.e., cpuser file).

Ideally, anything we store in cpuser files can be represented as an
instance of this class.

=cut

#----------------------------------------------------------------------

use Carp ();

use Cpanel::Imports;
use Cpanel::Set ();

use constant _OPTIONAL_ACCESSORS => (
    'name_in_cpuser',
    'name_in_package',
    'help_text_var',
);

use constant _ACCESSORS => (
    _OPTIONAL_ACCESSORS,
    'name_in_api',
    'default',
    'label_var',
    'package_insert_before',
);

use constant _REQUIRED_NON_ACCESSORS => (
    'createacct_label_var',
    'removeacct_label_var',
    'createacct_cr',
    'modifyacct_cr',
    'removeacct_cr',
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

%OPTS are the data points to insert into the returned object.
These are named identically to their accessors, defined either here
or in subclasses.

=cut

sub new ( $class, %opts ) {
    my @allowed = ( $class->_ACCESSORS(), $class->_REQUIRED_NON_ACCESSORS() );

    my @needed = Cpanel::Set::difference(
        \@allowed,
        [ $class->_OPTIONAL_ACCESSORS() ],
    );

    my @missing = Cpanel::Set::difference(
        \@needed,
        [ keys %opts ],
    );

    Carp::croak("Missing: @missing") if @missing;

    my $self = { delete %opts{@allowed} };

    if ( my @extra = sort keys %opts ) {
        Carp::croak("Unrecognized: @extra");
    }

    my $apiname = $self->{'name_in_api'};

    # sanity check:
    if ( $apiname =~ tr<a-z_><>c ) {
        Carp::croak "name_in_api should be all lowercase and underscore!";
    }

    # These two are usually just uppercase transforms of the API name,
    # but some parameters (e.g., language/LOCALE/LANG) aren’t that simple.
    #
    for my $key (qw( name_in_package name_in_cpuser )) {
        $self->{$key} //= ( $apiname =~ tr<a-z><A-Z>r );
    }

    return bless $self, $class;
}

=head2 $text = I<OBJ>->label()

Returns I<OBJ>’s translated label.

=cut

sub label ($self) {
    return $self->_makevar('label_var');
}

=head2 $text = I<OBJ>->createacct_label()

Returns the label for I<OBJ>’s part of createacct.

=cut

sub createacct_label ($self) {
    return $self->_makevar('createacct_label_var');
}

=head2 $text = I<OBJ>->removeacct_label()

Returns the label for I<OBJ>’s part of removeacct.

=cut

sub removeacct_label ($self) {
    return $self->_makevar('removeacct_label_var');
}

=head1 OTHER ACCESSORS

=over

=item * C<name_in_api> - The parameter’s name as given in API calls.

B<NOTE:> For “legacy” account components—i.e., those that predate this
class—C<name_in_api> may not be accurate for every API. For example,
C<createacct>’s C<maxpop> parameter is C<MAXPOP> in C<modifyacct>.

=item * C<type> - (defined in subclass)

=item * C<name_in_cpuser> - The parameter’s name as stored in cpuser files.

=item * C<name_in_package> - The parameter’s name as stored in package files.

=item * C<default>

=item * C<label_var> - The makeZ<>text-translatable string that informs
the C<label()> accessor (above). Prefer C<label()> whenever possible.

=back

=cut

sub type ($self) {
    return $self->_type();
}

use Class::XSAccessor (
    getters => [_ACCESSORS],
);

#----------------------------------------------------------------------

=head1 OTHER METHODS

=head2 I<OBJ>->do_createacct( $USERNAME, $COMPONENT_VALUE )

Runs I<OBJ>’s part of createacct. Returns nothing.

=cut

sub do_createacct ( $self, $username, $value ) {
    return $self->{'createacct_cr'}->( $username, $value );
}

=head2 I<OBJ>->do_modifyacct( $USERNAME, $OLD_VALUE, $NEW_VALUE )

Runs I<OBJ>’s part of modifyacct. Returns nothing.

=cut

sub do_modifyacct ( $self, $username, $oldval, $newval ) {
    return $self->{'modifyacct_cr'}->( $username, $oldval, $newval );
}

=head2 I<OBJ>->do_removeacct( $USERNAME )

Runs I<OBJ>’s part of removeacct. Returns nothing.

=cut

sub do_removeacct ( $self, $username ) {
    return $self->{'removeacct_cr'}->($username);
}

=head2 $why = I<OBJ>->why_invalid( $SPECIMEN )

Returns a string that indicates why $SPECIMEN is invalid,
or undef if $SPECIMEN is, in fact, valid.

=cut

sub why_invalid ( $self, $specimen ) {
    return $self->_why_invalid($specimen);
}

#----------------------------------------------------------------------

sub _makevar ( $self, $locale_variable ) {
    my $var = $self->{$locale_variable};
    return $var && locale()->makevar($var);
}

1;
