package Cpanel::Destruct::DestroyDetector;

# cpanel - Cpanel/Destruct/DestroyDetector.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Destruct::DestroyDetector

=head1 SYNOPSIS

    package MyThing;

    use parent 'Cpanel::Destruct::DestroyDetector';

=head1 DESCRIPTION

This tiny module provides a C<DESTROY()> that will C<warn()> if it runs
at global destruction time. This is useful for detecting memory leaks,
which can be particularly important when dealing with callback-oriented
code.

To use it, just have the class you want to check inherit from this module.

=head1 SPECIAL CASES

=head2 C<DESTROY()> in subclasses

If your subclass defines its own C<DESTROY()> method, be sure that that
method also calls this class’s C<DESTROY()>. For example:

    sub DESTROY ($self) {
        $self->SUPER::DESTROY();

        # ...
    }

=head2 Subprocesses

If an instance of this class forks you might see spurious global-destruction
warnings. Usually these aren’t a problem because generally we only care about
leaks in the same process that creates the object.

The usual trick to avoid stuff like this is to do something like:

    $self->{'_pid'} = $$;

… in your constructor, then in your destructor:

    return if $$ != $self->{'_pid'};

This class can’t implement that directly because here we don’t care
about the class instance’s interior structure. (Also there’s no
constructor-side logic to store the PID at creation time.)

To work around that, just implemnet the same check in a module that I<does>
know about the class instance’s interior structure—i.e., your code!
Put the PID check prior to calling this class’s C<DESTROY()>, e.g.:

    if ($$ == $self->{'_pid'}) {
        $self->SUPER::DESTROY();
    }

=cut

our $_DEBUG;

our $_DESTRUCT_PHASE;
BEGIN { $_DESTRUCT_PHASE = 'DESTRUCT'; }

sub DESTROY ($self) {
    warn "destroy: $self (${^GLOBAL_PHASE})\n" if $_DEBUG;

    if ( ${^GLOBAL_PHASE} eq $_DESTRUCT_PHASE ) {
        warn "PID $$ ($0): $self destroyed at global destruct!";
    }

    return;
}

1;
