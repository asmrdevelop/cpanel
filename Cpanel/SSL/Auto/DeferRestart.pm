package Cpanel::SSL::Auto::DeferRestart;

# cpanel - Cpanel/SSL/Auto/DeferRestart.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Defer - defer restarts of services for AutoSSL

=head1 SYNOPSIS

    use Cpanel::SSL::Auto::DeferRestart;

    {
        my $deferral = Cpanel::SSL::Auto::DeferRestart->new('apache', ...);

        #...do stuff. Any of the services whose names were given to
        #the constructor above will silently refuse to restart.
    }

    #...and any services that were attempted to be restarted in the previous
    #block will now restart.

=head1 DESCRIPTION

This module provides a quick, kooky means of deferring
service restarts while several SSL certificates are being installed.

This relies on C<DESTROY()> for simplicity; however, that means
a bit of caution is indicated: it’s best not to create more than one
variable that refers to an instance of this class so that we can decisively
say that the services are restarted at a specific point.

Note that this module overwrites B<global> functions. As long as the
instance is only stored in one place, though, that should function
effectively the same as if the overwrite were local to a given scope.

=cut

use strict;
use warnings;

use Cpanel::Exception ();

use Cpanel::SSLInstall ();    # PPI USE OK - crawls the symbol table

sub new {
    my ( $class, @services ) = @_;

    my %restarter_globref = $class->_get_restarter_glob_refs();
    my %orig_restarter;
    my %to_restart;

    for my $svc (@services) {
        next if $restarter_globref{$svc};

        #should never happen
        die Cpanel::Exception->create_raw("AutoSSL doesn’t know how to defer restarts for a service named “$svc”!");
    }

    for my $svc (@services) {
        my $glob_ref = $restarter_globref{$svc};

        #Store a reference to the original code.
        $orig_restarter{$svc} = *{$glob_ref}{'CODE'};

        #Here is the “magic”: override the CODE reference
        #with a stub function that just tallies the number of calls
        #made to this function. When this object is DESTROYed,
        #we’ll call the original functions (once).
        no warnings 'redefine';
        *{$glob_ref} = sub {
            $to_restart{$svc}++;
            return;
        };
    }

    my $self = {
        _pid            => $$,
        _orig_restarter => \%orig_restarter,
        _to_restart     => \%to_restart,
    };

    return bless $self, $class;
}

sub DESTROY {
    my ($self) = @_;

    return if $self->{'_pid'} != $$;

    my %restarter_globref = $self->_get_restarter_glob_refs();

    for my $svc ( keys %{ $self->{'_orig_restarter'} } ) {
        my $glob_ref = $restarter_globref{$svc};

        #Here, finally, is the actual service restart.
        $self->{'_orig_restarter'}{$svc}->() if $self->{'_to_restart'}{$svc};

        #Now restore the original CODE reference so that service
        #restarts outside the context where this object lives
        #will function normally.
        no warnings 'redefine';
        *{$glob_ref} = $self->{'_orig_restarter'}{$svc};
    }

    return;
}

#overridden in tests
sub _get_restarter_glob_refs {
    my $ns = $Cpanel::{'SSLInstall::'} or do {
        die 'Cpanel::SSLInstall must be loaded!';    #shouldn’t happen
    };

    #These values are typeglobs, which we can use to override
    #the functions (i.e., CODE references) that reside in these
    #places within Perl’s namespace table.
    return (
        apache  => $ns->{'_restart_apache'},
        dovecot => $ns->{'_rebuild_doveconf_config_and_restart'},
    );
}

1;
