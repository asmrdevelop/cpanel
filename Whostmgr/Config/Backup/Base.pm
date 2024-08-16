package Whostmgr::Config::Backup::Base;

# cpanel - Whostmgr/Config/Backup/Base.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::Base

=head1 DESCRIPTION

Base class for inter-server configuration transfer backup modules.

=head1 METHODS

The following methods are defined on this base class:

=head2 $obj = I<CLASS>->new()

Instantiates I<CLASS>.

=cut

sub new ($class) {
    return bless {}, $class;
}

#----------------------------------------------------------------------

=head2 $string = I<OBJ>->query_module_info()

Returns a string or data structure that indicates version information.

The default implementation returns C<${LEAF_MODULE_NAME}_Version=$CP_FULL_VERSION>. Some subclasses may need to override this.

TODO: Provide more detail.

=cut

sub query_module_info ($self) {

    require Cpanel::Version::Full;
    return $self->_module_name() . '_Version=' . Cpanel::Version::Full::getversion();
}

#----------------------------------------------------------------------

=head2 ($ok, $msg) = I<OBJ>->backup( $PARENT_OBJ )

Perform the actual backup.

This receives an object that
currently is an instance of L<Whostmgr::Config::Backup> but
should ideally be replaced with a “state” object that has methods
to inject data.

=cut

sub backup ( $self, $PARENT_OBJ ) {
    return $self->_backup($PARENT_OBJ);
}

#----------------------------------------------------------------------

=head2 $version = I<CLASS>->version()

May be called as either an instance method or a class method.
This just wraps L<Cpanel::Version::Full>’s C<getversion()> function.

TODO: Remove this.

=cut

sub version {
    require Cpanel::Version::Full;
    return Cpanel::Version::Full::getversion();
}

#----------------------------------------------------------------------

=head1 REQUIRED SUBCLASS METHODS

Subclasses B<must> implement the following methods:

=head2 I<OBJ>->_backup( $PARENT_OBJ )

Logic for C<backup()> above.

#----------------------------------------------------------------------

=head1 OPTIONAL SUBCLASS METHODS

Subclasses B<may> implement the following:

=head2 I<OBJ>->post_backup()

Logic that executes after the entire backup has run.

=cut

use constant post_backup => ();

#----------------------------------------------------------------------

sub _module_name ($self) {
    my $class_name = ref($self) || $self;
    return ( split m{::}, $class_name )[-1];
}

1;
