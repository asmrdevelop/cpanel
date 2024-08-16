package Whostmgr::Accounts::Create::Components::Base;

# cpanel - Whostmgr/Accounts/Create/Components/Base.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::Base

=head1 SYNOPSIS

    use parent 'Whostmgr::Accounts::Create::Components::Base';
    ...

=head1 DESCRIPTION

This module serves as the basis upon which to build the various account
creation component submodules. In your submodule, optionally set up a _run
method so that it actually does something other than print out that the
component itself is actually running.

=cut

use cPstrict;
use Whostmgr::UI ();

=head2 new

Returns OBJECT.

=cut

sub new ($class) {
    return bless {}, $class;
}

sub pretty_name {
    die "Must be defined in submodule!";
}

=head2 run

Accepts STRING REF of output to append to.

Returns BOOL on success or failure of the operation OR 1 if the operation
is not defined for the module in question.

Submodule authors should keep the above in mind, especially when
returning 0 but not dying. In this case you probably should set an error
with the error() method before returning.

=cut

my $wrap_task = sub ( $self, $sr, $out, $user, $action ) {
    if ( ref $sr ne 'CODE' ) {
        return 1;
    }
    $$out .= Whostmgr::UI::setstatus( $action . ' ' . $self->pretty_name() );

    local $@;
    my $ret = eval { $sr->( $out, $user ); };
    if ( !$ret || $@ ) {
        $self->error( $@ || "Unknown error" );
        $$out .= Whostmgr::UI::setstatuserror();
        return 0;
    }
    $$out .= Whostmgr::UI::setstatusdone();
    return 1;
};

sub run ( $self, $out, $user ) {
    return $wrap_task->( $self, $self->can("_run"), $out, $user, 'Setting up' );
}

=head2 error

Accepts STRING of what failed (so we can set it).

Returns STRING of what failed.

=cut

sub error ( $self, $msg = '' ) {
    if ( $self->{'_error'} && !$msg ) {
        return $self->{'_error'};
    }
    return $self->{'_error'} = $msg;
}

1;
